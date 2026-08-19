import 'dart:math';

import 'package:ascend_core/ascend_core.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy.delayFor', () {
    test('crece exponencialmente', () {
      const policy = RetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        jitterFactor: 0,
      );

      expect(policy.delayFor(1).inMilliseconds, 100);
      expect(policy.delayFor(2).inMilliseconds, 200);
      expect(policy.delayFor(3).inMilliseconds, 400);
    });

    test('respeta el tope máximo', () {
      const policy = RetryPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 5),
        jitterFactor: 0,
      );

      expect(policy.delayFor(10).inSeconds, 5);
    });

    test('el jitter mantiene la espera dentro de la banda esperada', () {
      // jitterFactor queda en su valor por defecto (0.25).
      const policy = RetryPolicy(initialDelay: Duration(milliseconds: 1000));
      final rng = Random(42);

      for (var i = 0; i < 50; i++) {
        final delay = policy.delayFor(1, random: rng).inMilliseconds;
        expect(delay, inInclusiveRange(750, 1250));
      }
    });
  });

  group('RetryPolicy.execute', () {
    test('no reintenta cuando la primera llamada tiene éxito', () async {
      var calls = 0;
      const policy = RetryPolicy(initialDelay: Duration.zero);

      final result = await policy.execute<int>(() async {
        calls++;
        return const Result<int>.success(1);
      });

      expect(calls, 1);
      expect(result.isSuccess, isTrue);
    });

    test('reintenta hasta maxAttempts ante fallos recuperables', () async {
      var calls = 0;
      const policy = RetryPolicy(maxAttempts: 4, initialDelay: Duration.zero);

      final result = await policy.execute<int>(() async {
        calls++;
        return const Result<int>.failure(NetworkFailure());
      });

      expect(calls, 4);
      expect(result.isFailure, isTrue);
    });

    test('devuelve el éxito en cuanto lo consigue', () async {
      var calls = 0;
      const policy = RetryPolicy(maxAttempts: 5, initialDelay: Duration.zero);

      final result = await policy.execute<int>(() async {
        calls++;
        return calls < 3
            ? const Result<int>.failure(ServerFailure())
            : const Result<int>.success(99);
      });

      expect(calls, 3);
      expect(result.valueOrNull, 99);
    });

    test('NO reintenta fallos no recuperables', () async {
      // Reintentar un fallo de permisos o de validación solo gasta batería y
      // cuota: el resultado va a ser el mismo.
      var calls = 0;
      const policy = RetryPolicy(maxAttempts: 5, initialDelay: Duration.zero);

      final result = await policy.execute<int>(() async {
        calls++;
        return const Result<int>.failure(PermissionFailure());
      });

      expect(calls, 1);
      expect(result.failureOrNull, isA<PermissionFailure>());
    });

    test('shouldRetry permite anular la decisión por defecto', () async {
      var calls = 0;
      const policy = RetryPolicy(maxAttempts: 4, initialDelay: Duration.zero);

      await policy.execute<int>(() async {
        calls++;
        return const Result<int>.failure(PermissionFailure());
      }, shouldRetry: (_) => true);

      expect(calls, 4);
    });
  });
}
