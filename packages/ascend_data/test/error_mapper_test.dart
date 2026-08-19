import 'dart:async';
import 'dart:io';

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';

FirebaseException _firestore(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

void main() {
  group('ErrorMapper — Firebase Auth', () {
    test('unifica credenciales inválidas sin filtrar si el email existe', () {
      // Firebase agrupa estos códigos justamente para no revelar qué correos
      // están registrados. Mantenemos esa propiedad.
      for (final code in <String>[
        'invalid-credential',
        'wrong-password',
        'user-not-found',
        'invalid-email',
      ]) {
        final failure = ErrorMapper.map(
          FirebaseAuthException(code: code),
          StackTrace.empty,
        );
        expect(failure, isA<AuthFailure>());
        expect(failure.messageKey, 'failure.auth.invalidCredentials');
      }
    });

    test('mapea los códigos específicos de registro', () {
      expect(
        ErrorMapper.map(
          FirebaseAuthException(code: 'email-already-in-use'),
          StackTrace.empty,
        ).messageKey,
        'failure.auth.emailInUse',
      );
      expect(
        ErrorMapper.map(
          FirebaseAuthException(code: 'weak-password'),
          StackTrace.empty,
        ).messageKey,
        'failure.auth.weakPassword',
      );
      expect(
        ErrorMapper.map(
          FirebaseAuthException(code: 'user-disabled'),
          StackTrace.empty,
        ).messageKey,
        'failure.auth.accountDisabled',
      );
    });

    test('un fallo de red durante el login se clasifica como red', () {
      final failure = ErrorMapper.map(
        FirebaseAuthException(code: 'network-request-failed'),
        StackTrace.empty,
      );

      expect(failure, isA<NetworkFailure>());
      expect(failure.isRetryable, isTrue);
    });
  });

  group('ErrorMapper — Firestore y Storage', () {
    test(
      'permission-denied se clasifica como permisos y NO es reintentable',
      () {
        final failure = ErrorMapper.map(
          _firestore('permission-denied'),
          StackTrace.empty,
        );

        expect(failure, isA<PermissionFailure>());
        expect(
          failure.isRetryable,
          isFalse,
          reason: 'Ofrecer "Reintentar" ante un rechazo de reglas es engañar.',
        );
      },
    );

    test('unavailable se trata como falta de red y es reintentable', () {
      // Firestore ya guardó el cambio en la caché local: para la persona esto
      // es "sin conexión", no "error".
      final failure = ErrorMapper.map(
        _firestore('unavailable'),
        StackTrace.empty,
      );

      expect(failure, isA<NetworkFailure>());
      expect(failure.isRetryable, isTrue);
    });

    test('not-found y object-not-found comparten clasificación', () {
      expect(
        ErrorMapper.map(_firestore('not-found'), StackTrace.empty),
        isA<NotFoundFailure>(),
      );
      expect(
        ErrorMapper.map(
          FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
          ),
          StackTrace.empty,
        ),
        isA<NotFoundFailure>(),
      );
    });

    test('quota-exceeded se convierte en fallo de cuota', () {
      expect(
        ErrorMapper.map(_firestore('quota-exceeded'), StackTrace.empty),
        isA<QuotaFailure>(),
      );
    });

    test('conserva el código original para diagnóstico', () {
      final failure = ErrorMapper.map(
        _firestore('permission-denied'),
        StackTrace.empty,
      );

      expect(failure.code, 'permission-denied');
      expect(failure.cause, isA<FirebaseException>());
    });
  });

  group('ErrorMapper — Cloud Functions', () {
    test('resource-exhausted es la cuota de IA agotada, no un error', () {
      final failure = ErrorMapper.map(
        FirebaseFunctionsException(
          code: 'resource-exhausted',
          message: 'daily limit',
        ),
        StackTrace.empty,
      );

      expect(failure, isA<QuotaFailure>());
      expect(failure.messageKey, 'failure.quota.ai');
    });

    test('unauthenticated pide volver a iniciar sesión', () {
      final failure = ErrorMapper.map(
        FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'no token',
        ),
        StackTrace.empty,
      );

      expect(failure.messageKey, 'failure.auth.sessionExpired');
    });

    test('invalid-argument se trata como validación', () {
      expect(
        ErrorMapper.map(
          FirebaseFunctionsException(code: 'invalid-argument', message: 'bad'),
          StackTrace.empty,
        ),
        isA<ValidationFailure>(),
      );
    });
  });

  group('ErrorMapper — errores de plataforma', () {
    test('SocketException es falta de red', () {
      expect(
        ErrorMapper.map(const SocketException('sin ruta'), StackTrace.empty),
        isA<NetworkFailure>(),
      );
    });

    test('TimeoutException es tiempo agotado', () {
      expect(
        ErrorMapper.map(TimeoutException('lento'), StackTrace.empty),
        isA<TimeoutFailure>(),
      );
    });

    test('una respuesta malformada es fallo del servidor', () {
      final failure = ErrorMapper.map(
        const FormatException('JSON inválido'),
        StackTrace.empty,
      );

      expect(failure, isA<ServerFailure>());
      expect(failure.code, 'malformed-response');
    });
  });

  group('ErrorMapper — contrato general', () {
    test('cualquier excepción desconocida se degrada, nunca se propaga', () {
      // Esta es la garantía central: si Firebase inventa un código mañana, la
      // app muestra un mensaje amigable en vez de romperse.
      final failure = ErrorMapper.map(
        _firestore('un-codigo-que-todavia-no-existe'),
        StackTrace.empty,
      );

      expect(failure, isA<UnknownFailure>());
      expect(failure.code, 'un-codigo-que-todavia-no-existe');
    });

    test('un Failure ya mapeado no se envuelve dos veces', () {
      const original = PermissionFailure(code: 'x');
      expect(ErrorMapper.map(original, StackTrace.empty), same(original));
    });
  });

  group('runGuarded', () {
    test('devuelve Success cuando no hay excepción', () async {
      final result = await runGuarded<int>(() async => 42);
      expect(result.valueOrNull, 42);
    });

    test('atrapa la excepción y la convierte en Failure tipado', () async {
      final result = await runGuarded<int>(
        () async => throw _firestore('permission-denied'),
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<PermissionFailure>());
    });
  });

  group('guardStream', () {
    test('envuelve los datos en Success', () async {
      final results = await guardStream(
        Stream<int>.fromIterable(<int>[1, 2]),
      ).toList();

      expect(results.map((r) => r.valueOrNull), <int?>[1, 2]);
    });

    test('un error NO cierra el stream: emite Failed y sigue', () async {
      // Es lo que permite que una pantalla en tiempo real se recupere sola tras
      // un corte de red, en vez de quedarse muerta hasta que se reconstruya.
      final controller = StreamController<int>();
      final received = <Result<int>>[];
      final subscription = guardStream(controller.stream).listen(received.add);

      controller
        ..add(1)
        ..addError(_firestore('unavailable'));
      await Future<void>.delayed(Duration.zero);
      controller.add(2);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(3));
      expect(received[0].valueOrNull, 1);
      expect(received[1].failureOrNull, isA<NetworkFailure>());
      expect(received[2].valueOrNull, 2);

      await subscription.cancel();
      await controller.close();
    });
  });
}
