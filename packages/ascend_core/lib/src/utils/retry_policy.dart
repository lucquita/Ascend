import 'dart:async';
import 'dart:math';

import 'package:ascend_core/src/errors/failure.dart';
import 'package:ascend_core/src/result/result.dart';

/// Reintento con retroceso exponencial y *jitter*.
///
/// El jitter (variación aleatoria) evita el efecto manada: si mil dispositivos
/// pierden la conexión a la vez y todos reintentan exactamente a los 2 s, el
/// backend recibe mil peticiones simultáneas justo cuando se recupera.
class RetryPolicy {
  /// Crea una política de reintentos.
  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 400),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.jitterFactor = 0.25,
  });

  /// Política pensada para subidas de archivos: más paciente.
  static const RetryPolicy upload = RetryPolicy(
    maxAttempts: 5,
    initialDelay: Duration(seconds: 2),
    maxDelay: Duration(minutes: 5),
  );

  /// Política para lecturas rápidas: falla pronto para no congelar la UI.
  static const RetryPolicy read = RetryPolicy(
    maxAttempts: 2,
    initialDelay: Duration(milliseconds: 250),
    maxDelay: Duration(seconds: 2),
  );

  /// Número máximo de intentos, incluyendo el primero.
  final int maxAttempts;

  /// Espera antes del segundo intento.
  final Duration initialDelay;

  /// Tope de espera entre intentos.
  final Duration maxDelay;

  /// Factor por el que se multiplica la espera en cada intento.
  final double multiplier;

  /// Proporción de variación aleatoria aplicada a cada espera.
  final double jitterFactor;

  /// Calcula cuánto esperar antes del intento número [attempt] (base 1).
  Duration delayFor(int attempt, {Random? random}) {
    final rng = random ?? Random();
    final exponential =
        initialDelay.inMilliseconds * pow(multiplier, attempt - 1);
    final capped = min(
      exponential.toDouble(),
      maxDelay.inMilliseconds.toDouble(),
    );
    final jitter = capped * jitterFactor * (rng.nextDouble() * 2 - 1);
    return Duration(milliseconds: max(0, (capped + jitter).round()));
  }

  /// Ejecuta [action] reintentando mientras el fallo sea recuperable.
  ///
  /// Solo se reintenta si [Failure.isRetryable] es `true`: no tiene sentido
  /// reintentar un `PermissionFailure` o una validación, y hacerlo solo
  /// castiga la batería y la cuota del backend.
  Future<Result<T>> execute<T>(
    Future<Result<T>> Function() action, {
    bool Function(Failure failure)? shouldRetry,
    Random? random,
  }) async {
    Result<T> lastResult = await action();

    for (var attempt = 1; attempt < maxAttempts; attempt++) {
      final failure = lastResult.failureOrNull;
      if (failure == null) {
        return lastResult;
      }

      final retryable = shouldRetry?.call(failure) ?? failure.isRetryable;
      if (!retryable) {
        return lastResult;
      }

      await Future<void>.delayed(delayFor(attempt, random: random));
      lastResult = await action();
    }

    return lastResult;
  }
}
