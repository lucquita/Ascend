/// Casos de uso de evidencias.
///
/// ## Storage todavía no está habilitado
///
/// El plan del proyecto Firebase no incluye Cloud Storage, así que la subida
/// real no se puede ejecutar. Eso **no** impide construir la fase: la validación,
/// la cola de subida, los estados y las reglas son independientes del backend de
/// archivos. Lo único que queda esperando es el `EvidenceUploader`, que hoy
/// devuelve un fallo tipado y mañana sube de verdad sin que cambie nada más.
///
/// El diseño es deliberadamente **offline-first**: la misión se completa en el
/// momento con la foto guardada localmente, y el archivo viaja después. Eso es
/// lo que permite cerrar una misión en modo avión, y de paso hace que la falta
/// de Storage degrade con elegancia en vez de bloquear el producto.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/mission.dart';
import 'package:ascend_domain/src/repositories/repositories.dart';

/// Peso máximo de una evidencia, en bytes.
///
/// Coincide con `maxSize(10)` de `storage.rules`. Validar acá evita subir
/// 10 MB por una red móvil para que el servidor los rechace al final.
const int kMaxEvidenceBytes = 10 * 1024 * 1024;

/// Longitud máxima de la nota que acompaña a la evidencia.
const int kMaxEvidenceNoteLength = 280;

/// Extensiones de imagen aceptadas.
///
/// Se valida por extensión y no por MIME porque el dominio no puede leer el
/// archivo: es Dart puro. Las reglas de Storage revalidan el `contentType` real
/// del lado del servidor, que es la comprobación que no se puede eludir.
const Set<String> kAllowedEvidenceExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'heic',
  'webp',
};

/// Resultado de validar un archivo antes de encolarlo.
///
/// Es una función pura para poder testear la tabla completa de casos sin tocar
/// el disco ni levantar Firebase.
Result<void> validateEvidenceFile({
  required String localPath,
  int? sizeBytes,
  String? note,
}) {
  if (localPath.trim().isEmpty) {
    return const Failed<void>(
      ValidationFailure(
        messageKey: 'validation.evidence.fileRequired',
        field: 'localPath',
      ),
    );
  }

  final extension = _extensionOf(localPath);
  if (extension == null || !kAllowedEvidenceExtensions.contains(extension)) {
    return const Failed<void>(
      ValidationFailure(
        messageKey: 'validation.evidence.notAnImage',
        field: 'localPath',
      ),
    );
  }

  // Un archivo de 15 MB tiene que rechazarse con un mensaje claro, no con un
  // crash ni con una subida que falla después de tres minutos.
  if (sizeBytes != null && sizeBytes > kMaxEvidenceBytes) {
    return const Failed<void>(
      ValidationFailure(
        messageKey: 'validation.evidence.tooLarge',
        field: 'localPath',
      ),
    );
  }

  if (sizeBytes != null && sizeBytes <= 0) {
    return const Failed<void>(
      ValidationFailure(
        messageKey: 'validation.evidence.emptyFile',
        field: 'localPath',
      ),
    );
  }

  if (note != null && note.trim().length > kMaxEvidenceNoteLength) {
    return const Failed<void>(
      ValidationFailure(
        messageKey: 'validation.evidence.noteTooLong',
        field: 'note',
      ),
    );
  }

  return const Success<void>(null);
}

String? _extensionOf(String path) {
  final normalized = path.toLowerCase().split('?').first;
  final dot = normalized.lastIndexOf('.');
  if (dot == -1 || dot == normalized.length - 1) {
    return null;
  }
  return normalized.substring(dot + 1);
}

/// Adjunta una evidencia a una misión y la deja en la cola de subida.
class AttachEvidenceUseCase {
  /// Crea el caso de uso.
  const AttachEvidenceUseCase(this._evidence);

  final EvidenceRepository _evidence;

  /// Valida el archivo y lo encola.
  ///
  /// Devuelve la evidencia en estado `pending`: la misión ya puede completarse
  /// con ella, aunque el archivo todavía no haya viajado.
  Future<Result<Evidence>> call({
    required String uid,
    required String missionId,
    required String localPath,
    int? sizeBytes,
    String? note,
  }) async {
    final validation = validateEvidenceFile(
      localPath: localPath,
      sizeBytes: sizeBytes,
      note: note,
    );
    if (validation case Failed<void>(:final failure)) {
      return Failed<Evidence>(failure);
    }

    final trimmed = note?.trim();
    return _evidence.enqueueUpload(
      uid: uid,
      missionId: missionId,
      localPath: localPath,
      note: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
  }
}

/// Procesa la cola de subidas pendientes.
class ProcessPendingUploadsUseCase {
  /// Crea el caso de uso.
  const ProcessPendingUploadsUseCase(this._evidence);

  final EvidenceRepository _evidence;

  /// Intenta subir lo que quedó pendiente. Devuelve cuántas subió.
  ///
  /// Se invoca al recuperar la conexión. Es idempotente: lo que ya subió no
  /// vuelve a subir.
  Future<Result<int>> call() => _evidence.processPendingUploads();
}

/// Observa cuántas evidencias quedan sin subir.
class WatchPendingUploadsUseCase {
  /// Crea el caso de uso.
  const WatchPendingUploadsUseCase(this._evidence);

  final EvidenceRepository _evidence;

  /// Alimenta el indicador de "pendiente de sincronizar".
  Stream<int> call() => _evidence.watchPendingCount();
}

/// Elimina la evidencia de una misión.
class RemoveEvidenceUseCase {
  /// Crea el caso de uso.
  const RemoveEvidenceUseCase(this._evidence);

  final EvidenceRepository _evidence;

  /// Borra la evidencia y su archivo.
  ///
  /// Si la misión ya está completada **no** se borra: la evidencia es lo que
  /// acredita el logro por el que se otorgó Aura, y quitarla dejaría un
  /// completado sin respaldo.
  Future<Result<void>> call({
    required String uid,
    required Mission mission,
  }) async {
    if (mission.status.isCompleted) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.evidence.completedMission',
          field: 'evidence',
        ),
      );
    }
    return _evidence.deleteEvidence(uid: uid, missionId: mission.id);
  }
}
