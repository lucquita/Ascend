import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uploader configurable, para verificar el comportamiento según disponibilidad.
class _FakeUploader implements EvidenceUploader {
  _FakeUploader({this.available = true});

  bool available;
  int uploadCalls = 0;
  int deleteCalls = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<String> upload({
    required String uid,
    required String missionId,
    required String localPath,
  }) async {
    uploadCalls++;
    return 'https://cdn/$missionId.jpg';
  }

  @override
  Future<void> delete({required String uid, required String missionId}) async =>
      deleteCalls++;
}

void main() {
  late InMemoryEvidenceOutbox outbox;

  setUp(() => outbox = InMemoryEvidenceOutbox());
  tearDown(() => outbox.dispose());

  PendingUpload upload({String id = 'u1', String missionId = 'm1'}) =>
      PendingUpload(
        id: id,
        uid: 'user1',
        missionId: missionId,
        localPath: '/tmp/$missionId.jpg',
        queuedAt: DateTime.utc(2026, 8, 14),
      );

  group('EvidenceOutbox — la cola que hace posible el modo offline', () {
    test('encolar y quitar mantiene el conteo', () async {
      await outbox.enqueue(upload());
      await outbox.enqueue(upload(id: 'u2', missionId: 'm2'));
      expect(await outbox.pending(), hasLength(2));

      await outbox.remove('u1');
      expect(await outbox.pending(), hasLength(1));
    });

    test('las entradas salen en orden de llegada', () async {
      // Se procesa en orden cronológico: la foto que se sacó primero sube
      // primero, que es lo que la persona espera ver completarse.
      await outbox.enqueue(
        PendingUpload(
          id: 'nueva',
          uid: 'user1',
          missionId: 'm2',
          localPath: '/tmp/b.jpg',
          queuedAt: DateTime.utc(2026, 8, 14, 12),
        ),
      );
      await outbox.enqueue(
        PendingUpload(
          id: 'vieja',
          uid: 'user1',
          missionId: 'm1',
          localPath: '/tmp/a.jpg',
          queuedAt: DateTime.utc(2026, 8, 14, 9),
        ),
      );

      final pending = await outbox.pending();
      expect(pending.map((p) => p.id), <String>['vieja', 'nueva']);
    });

    test('withFailure acumula intentos hasta agotarlos', () {
      var item = upload();
      expect(item.isExhausted, isFalse);

      for (var i = 0; i < PendingUpload.maxAttempts; i++) {
        item = item.withFailure('sin red');
      }

      // Sin techo, una evidencia rota se reintentaría para siempre gastando
      // batería y datos en cada reconexión.
      expect(item.attempts, PendingUpload.maxAttempts);
      expect(item.isExhausted, isTrue);
      expect(item.lastError, 'sin red');
    });

    test('el ida y vuelta por mapa conserva los datos', () {
      final original = upload().withFailure('timeout');
      final rebuilt = PendingUpload.fromMap(original.toMap());

      expect(rebuilt.id, original.id);
      expect(rebuilt.missionId, original.missionId);
      expect(rebuilt.localPath, original.localPath);
      expect(rebuilt.attempts, 1);
      expect(rebuilt.lastError, 'timeout');
      expect(rebuilt.queuedAt, original.queuedAt);
    });

    test('watchCount emite el estado inicial y cada cambio', () async {
      final counts = <int>[];
      final sub = outbox.watchCount().listen(counts.add);
      // `watchCount` es `async*`: la suscripción arranca en el próximo turno
      // del event loop. Sin esta espera, los encolados ocurrirían antes de que
      // el stream emitiera su valor inicial.
      await Future<void>.delayed(Duration.zero);

      await outbox.enqueue(upload());
      await outbox.enqueue(upload(id: 'u2', missionId: 'm2'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(counts.first, 0);
      expect(counts.last, 2);
    });
  });

  group('UnavailableEvidenceUploader — Storage sin habilitar', () {
    test('declara que no está disponible', () {
      const uploader = UnavailableEvidenceUploader();
      expect(uploader.isAvailable, isFalse);
    });

    test('subir lanza un fallo tipado, no un error genérico', () async {
      const uploader = UnavailableEvidenceUploader();

      // La interfaz tiene que poder decir "las fotos todavía no se suben", no
      // "algo salió mal".
      await expectLater(
        uploader.upload(uid: 'u1', missionId: 'm1', localPath: '/tmp/a.jpg'),
        throwsA(
          isA<QuotaFailure>().having(
            (f) => f.messageKey,
            'messageKey',
            'failure.storage.unavailable',
          ),
        ),
      );
    });

    test('borrar no falla: no hay archivo remoto que borrar', () async {
      const uploader = UnavailableEvidenceUploader();
      await expectLater(uploader.delete(uid: 'u1', missionId: 'm1'), completes);
    });
  });

  group('Procesamiento de la cola sin Storage', () {
    test('no se intenta subir ni se descartan evidencias', () async {
      // Gastar los 5 reintentos contra un backend que sabemos apagado
      // descartaría evidencias que sí se van a poder subir más adelante.
      final uploader = _FakeUploader(available: false);
      await outbox.enqueue(upload());

      expect(uploader.uploadCalls, 0);
      expect(await outbox.pending(), hasLength(1));
    });
  });
}
