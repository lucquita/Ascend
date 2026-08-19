import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

class _FakeEvidenceRepository implements EvidenceRepository {
  String? enqueuedPath;
  String? enqueuedNote;
  String? deletedMissionId;
  int writeCount = 0;

  @override
  Future<Result<Evidence>> enqueueUpload({
    required String uid,
    required String missionId,
    required String localPath,
    String? note,
  }) async {
    writeCount++;
    enqueuedPath = localPath;
    enqueuedNote = note;
    return Success<Evidence>(
      Evidence(
        capturedAt: DateTime.utc(2026, 8, 14),
        localPath: localPath,
        note: note,
      ),
    );
  }

  @override
  Future<Result<int>> processPendingUploads() async => const Success<int>(0);

  @override
  Stream<int> watchPendingCount() => Stream<int>.value(0);

  @override
  Future<Result<void>> deleteEvidence({
    required String uid,
    required String missionId,
  }) async {
    writeCount++;
    deletedMissionId = missionId;
    return const Success<void>(null);
  }
}

Mission _mission({MissionStatus status = MissionStatus.pending}) => Mission(
  id: 'm1',
  ownerId: 'u1',
  goalId: 'g1',
  title: 'Ver un capítulo',
  createdAt: DateTime.utc(2026, 8),
  status: status,
);

void main() {
  late _FakeEvidenceRepository repository;

  setUp(() => repository = _FakeEvidenceRepository());

  group('validateEvidenceFile — la validación que evita subir basura', () {
    test('acepta las extensiones de imagen previstas', () {
      for (final ext in kAllowedEvidenceExtensions) {
        final result = validateEvidenceFile(
          localPath: '/tmp/foto.$ext',
          sizeBytes: 1024,
        );
        expect(result.isSuccess, isTrue, reason: 'Debería aceptar .$ext');
      }
    });

    test('rechaza lo que no es una imagen', () {
      // Las reglas de Storage revalidan el contentType real; esto evita el
      // viaje de ida y vuelta por una red móvil.
      for (final path in <String>[
        '/tmp/documento.pdf',
        '/tmp/video.mp4',
        '/tmp/sin_extension',
        '/tmp/termina_en_punto.',
      ]) {
        final result = validateEvidenceFile(localPath: path, sizeBytes: 1024);
        expect(
          result.failureOrNull?.messageKey,
          'validation.evidence.notAnImage',
          reason: 'Debería rechazar $path',
        );
      }
    });

    test('la extensión se compara sin distinguir mayúsculas', () {
      expect(
        validateEvidenceFile(
          localPath: '/tmp/FOTO.JPG',
          sizeBytes: 1024,
        ).isSuccess,
        isTrue,
      );
    });

    test('rechaza un archivo de más de 10 MB', () {
      // Coincide con `maxSize(10)` de storage.rules: un 15 MB tiene que fallar
      // con un mensaje claro, no con un crash ni tras tres minutos de subida.
      final result = validateEvidenceFile(
        localPath: '/tmp/foto.jpg',
        sizeBytes: kMaxEvidenceBytes + 1,
      );

      expect(result.failureOrNull?.messageKey, 'validation.evidence.tooLarge');
    });

    test('acepta exactamente el límite', () {
      expect(
        validateEvidenceFile(
          localPath: '/tmp/foto.jpg',
          sizeBytes: kMaxEvidenceBytes,
        ).isSuccess,
        isTrue,
      );
    });

    test('rechaza un archivo vacío', () {
      expect(
        validateEvidenceFile(
          localPath: '/tmp/foto.jpg',
          sizeBytes: 0,
        ).failureOrNull?.messageKey,
        'validation.evidence.emptyFile',
      );
    });

    test('rechaza una ruta vacía', () {
      expect(
        validateEvidenceFile(localPath: '   ').failureOrNull?.messageKey,
        'validation.evidence.fileRequired',
      );
    });

    test('rechaza una nota larguísima', () {
      expect(
        validateEvidenceFile(
          localPath: '/tmp/foto.jpg',
          sizeBytes: 1024,
          note: 'a' * (kMaxEvidenceNoteLength + 1),
        ).failureOrNull?.messageKey,
        'validation.evidence.noteTooLong',
      );
    });

    test('sin tamaño conocido no se rechaza por peso', () {
      // La cámara puede no informar el tamaño; la validación real la hace
      // Storage. No inventamos un rechazo por un dato que no tenemos.
      expect(
        validateEvidenceFile(localPath: '/tmp/foto.jpg').isSuccess,
        isTrue,
      );
    });
  });

  group('AttachEvidenceUseCase', () {
    test('encola la evidencia válida', () async {
      final result = await AttachEvidenceUseCase(repository).call(
        uid: 'u1',
        missionId: 'm1',
        localPath: '/tmp/foto.jpg',
        sizeBytes: 2048,
        note: '  Terminé el capítulo 3  ',
      );

      expect(result.isSuccess, isTrue);
      expect(repository.enqueuedPath, '/tmp/foto.jpg');
      expect(repository.enqueuedNote, 'Terminé el capítulo 3');
    });

    test('una nota vacía se guarda como nula', () async {
      await AttachEvidenceUseCase(repository).call(
        uid: 'u1',
        missionId: 'm1',
        localPath: '/tmp/foto.jpg',
        note: '   ',
      );

      expect(repository.enqueuedNote, isNull);
    });

    test('un archivo inválido NO llega al repositorio', () async {
      final result = await AttachEvidenceUseCase(
        repository,
      ).call(uid: 'u1', missionId: 'm1', localPath: '/tmp/documento.pdf');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repository.writeCount, 0);
    });
  });

  group('RemoveEvidenceUseCase', () {
    test('quita la evidencia de una misión abierta', () async {
      final result = await RemoveEvidenceUseCase(
        repository,
      ).call(uid: 'u1', mission: _mission());

      expect(result.isSuccess, isTrue);
      expect(repository.deletedMissionId, 'm1');
    });

    test('NO se puede quitar la evidencia de una misión completada', () async {
      // Es lo que respalda el logro por el que ya se otorgó Aura: quitarla
      // dejaría un completado sin evidencia.
      final result = await RemoveEvidenceUseCase(repository).call(
        uid: 'u1',
        mission: _mission(status: MissionStatus.completed),
      );

      expect(
        result.failureOrNull?.messageKey,
        'validation.evidence.completedMission',
      );
      expect(repository.writeCount, 0);
    });
  });

  group('Evidence — estados de subida y de revisión son independientes', () {
    test('una evidencia subida pero rechazada NO acredita el logro', () {
      // El archivo llegó perfecto; el contenido no corresponde. Son dos cosas
      // distintas y el modelo tiene que poder expresarlas a la vez.
      final evidence = Evidence(
        capturedAt: DateTime.utc(2026, 8, 14),
        photoUrl: 'https://cdn/e.jpg',
        uploadStatus: EvidenceUploadStatus.uploaded,
        reviewStatus: EvidenceReviewStatus.rejected,
      );

      expect(evidence.hasImage, isTrue);
      expect(evidence.isValidProof, isFalse);
    });

    test('una evidencia local sin revisar sí acredita', () {
      final evidence = Evidence(
        capturedAt: DateTime.utc(2026, 8, 14),
        localPath: '/tmp/foto.jpg',
      );

      expect(evidence.uploadStatus, EvidenceUploadStatus.pending);
      expect(evidence.reviewStatus, EvidenceReviewStatus.pending);
      expect(evidence.isValidProof, isTrue);
    });

    test('un estado de revisión desconocido degrada a pendiente', () {
      expect(
        EvidenceReviewStatus.fromWire('inventado'),
        EvidenceReviewStatus.pending,
      );
      expect(EvidenceReviewStatus.fromWire(null), EvidenceReviewStatus.pending);
    });

    test('el ida y vuelta por wireValue es estable', () {
      for (final status in EvidenceReviewStatus.values) {
        expect(EvidenceReviewStatus.fromWire(status.wireValue), status);
      }
    });
  });
}
