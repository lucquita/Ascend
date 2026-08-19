import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/local/evidence_outbox.dart';
import 'package:ascend_data/src/datasources/remote/firestore_mission_datasource.dart';
import 'package:ascend_data/src/dtos/mission_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';

/// Sube el archivo de una evidencia y devuelve su URL.
///
/// Es un **puerto**: aísla lo único de esta fase que depende de Cloud Storage.
/// Todo lo demás —validación, cola, estados, reglas— funciona sin él.
abstract interface class EvidenceUploader {
  /// `true` si el backend de archivos está operativo.
  bool get isAvailable;

  /// Sube el archivo y devuelve la URL pública.
  Future<String> upload({
    required String uid,
    required String missionId,
    required String localPath,
  });

  /// Borra el archivo remoto.
  Future<void> delete({required String uid, required String missionId});
}

/// Uploader que no puede subir nada porque Storage no está habilitado.
///
/// El proyecto Firebase está en plan gratuito y Cloud Storage requiere plan
/// pago. En vez de dejar el código a medio escribir o simular una subida que no
/// ocurre, se declara explícitamente que no está disponible: la cola retiene la
/// evidencia, la interfaz lo informa, y nadie cree que la foto viajó.
///
/// Cuando se habilite Storage, se reemplaza este objeto por el que usa
/// `FirebaseStorage` y **no cambia nada más**.
class UnavailableEvidenceUploader implements EvidenceUploader {
  /// Crea el uploader inactivo.
  const UnavailableEvidenceUploader();

  @override
  bool get isAvailable => false;

  @override
  Future<String> upload({
    required String uid,
    required String missionId,
    required String localPath,
  }) async => throw const QuotaFailure(
    messageKey: 'failure.storage.unavailable',
    code: 'storage-not-enabled',
  );

  @override
  Future<void> delete({required String uid, required String missionId}) async {
    // Borrar lo que nunca subió no es un error: la entrada de la cola se quita
    // igual y la misión queda sin evidencia, que es el resultado buscado.
  }
}

/// Implementación de [EvidenceRepository] sobre la cola local y el uploader.
///
/// El orden importa: **primero se registra la evidencia en la misión**, con su
/// ruta local, y recién después se intenta subir. Así la misión se puede
/// completar en el momento aunque no haya red, que es el requisito central del
/// modo offline.
class EvidenceRepositoryImpl implements EvidenceRepository {
  /// Crea el repositorio.
  const EvidenceRepositoryImpl({
    required EvidenceOutbox outbox,
    required FirestoreMissionDataSource missionDataSource,
    required EvidenceUploader uploader,
  }) : _outbox = outbox,
       _missions = missionDataSource,
       _uploader = uploader;

  static const AscendLogger _logger = AscendLogger('EvidenceRepository');

  final EvidenceOutbox _outbox;
  final FirestoreMissionDataSource _missions;
  final EvidenceUploader _uploader;

  @override
  Future<Result<Evidence>> enqueueUpload({
    required String uid,
    required String missionId,
    required String localPath,
    String? note,
  }) => runGuarded(() async {
    final evidence = Evidence(
      capturedAt: DateTime.now().toUtc(),
      localPath: localPath,
      note: note,
    );

    // La evidencia queda anotada en la misión antes de intentar subir nada.
    // Si el proceso muere acá, la persona ve su foto igual y la cola la
    // levanta en el próximo arranque.
    await _missions.updateMission(
      uid: uid,
      missionId: missionId,
      data: MissionDto.evidenceUpdate(evidence),
    );

    await _outbox.enqueue(
      PendingUpload(
        id: newUploadId(),
        uid: uid,
        missionId: missionId,
        localPath: localPath,
        queuedAt: DateTime.now().toUtc(),
        note: note,
      ),
    );

    return evidence;
  });

  @override
  Future<Result<int>> processPendingUploads() => runGuarded(() async {
    if (!_uploader.isAvailable) {
      // No se vacía la cola ni se marcan como fallidas: quedan esperando a que
      // Storage exista. Gastar los 5 reintentos contra un backend que sabemos
      // apagado solo lograría descartar evidencias que sí se podrían subir.
      _logger.warning(
        'Storage no está habilitado: la cola de evidencias queda en espera.',
      );
      return 0;
    }

    final pending = await _outbox.pending();
    var uploaded = 0;

    for (final item in pending) {
      try {
        final url = await _uploader.upload(
          uid: item.uid,
          missionId: item.missionId,
          localPath: item.localPath,
        );

        await _missions.updateMission(
          uid: item.uid,
          missionId: item.missionId,
          data: MissionDto.evidenceUpdate(
            Evidence(
              capturedAt: item.queuedAt,
              photoUrl: url,
              note: item.note,
              uploadStatus: EvidenceUploadStatus.uploaded,
            ),
          ),
        );

        await _outbox.remove(item.id);
        uploaded++;
      } on Object catch (error, stackTrace) {
        // Un fallo en una evidencia no puede frenar las demás: se registra, se
        // cuenta el intento y se sigue con la siguiente.
        final failed = item.withFailure(error.toString());
        _logger.warning(
          'Falló la subida de una evidencia',
          error: error,
          stackTrace: stackTrace,
          context: <String, Object?>{
            'missionId': item.missionId,
            'attempts': failed.attempts,
          },
        );

        if (failed.isExhausted) {
          await _outbox.remove(failed.id);
          await _markFailed(failed);
        } else {
          await _outbox.update(failed);
        }
      }
    }

    return uploaded;
  });

  @override
  Stream<int> watchPendingCount() => _outbox.watchCount();

  @override
  Future<Result<void>> deleteEvidence({
    required String uid,
    required String missionId,
  }) => runGuarded(() async {
    await _uploader.delete(uid: uid, missionId: missionId);

    // También hay que sacarla de la cola: si no, la próxima sincronización
    // volvería a subir una evidencia que la persona acaba de borrar.
    final pending = await _outbox.pending();
    for (final item in pending.where((i) => i.missionId == missionId)) {
      await _outbox.remove(item.id);
    }

    await _missions.updateMission(
      uid: uid,
      missionId: missionId,
      data: <String, Object?>{'evidence': null},
    );
  });

  /// Marca la evidencia como fallida tras agotar los reintentos.
  ///
  /// Se deja constancia en la misión en lugar de borrarla en silencio: la
  /// persona tiene que poder ver que su foto no subió y volver a intentarlo.
  Future<void> _markFailed(PendingUpload item) async {
    try {
      await _missions.updateMission(
        uid: item.uid,
        missionId: item.missionId,
        data: MissionDto.evidenceUpdate(
          Evidence(
            capturedAt: item.queuedAt,
            localPath: item.localPath,
            note: item.note,
            uploadStatus: EvidenceUploadStatus.failed,
          ),
        ),
      );
    } on Object catch (error) {
      _logger.error(
        'No se pudo marcar la evidencia como fallida',
        error: error,
      );
    }
  }
}
