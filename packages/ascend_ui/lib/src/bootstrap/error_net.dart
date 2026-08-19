import 'dart:async';

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_ui/src/organisms/async_state_builder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Red de captura global de errores, compartida por la app y por el panel.
///
/// Este archivo es el que sostiene el requisito "la app jamás muestra un error
/// de Flutter". Instala cuatro trampas complementarias:
///
/// 1. `FlutterError.onError` — errores del framework durante build/layout/paint.
/// 2. `PlatformDispatcher.onError` — errores asincrónicos fuera de una zona.
/// 3. `runZonedGuarded` — todo lo demás que ocurra en el árbol de ejecución.
/// 4. `ErrorWidget.builder` — reemplaza la pantalla roja por una nuestra,
///    también en release.
///
/// Sin la cuarta, un error dentro de un `build()` seguiría pintando el cuadro
/// gris de Flutter en producción. Con ella, la persona ve un mensaje humano.
///
/// ## Por qué vive en el design system y no en cada app
///
/// Estaba duplicado en el arranque de la app móvil y hacía falta otra vez en el
/// panel. Una red de seguridad copiada es una red que se desincroniza: la
/// segunda copia se queda sin la trampa que se agregó en la primera, y el
/// síntoma aparece meses después como una pantalla gris en producción. El
/// design system ya es el dueño de los estados de error visibles, así que la
/// pantalla de último recurso le corresponde.
Future<void> runAscendGuarded(
  Future<void> Function() body, {
  String loggerName = 'bootstrap',
}) async {
  final logger = AscendLogger(loggerName);

  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // En release solo viajan advertencias y errores: los logs de depuración
      // gastan batería y pueden filtrar datos personales.
      AscendLogger.minimumLevel = kReleaseMode
          ? LogLevel.warning
          : LogLevel.debug;

      // Trampa 4: la pantalla roja deja de existir para el usuario final.
      ErrorWidget.builder = (FlutterErrorDetails details) {
        logger.error(
          'Error al construir un widget',
          error: details.exception,
          stackTrace: details.stack,
          context: <String, Object?>{'library': details.library ?? 'unknown'},
        );
        return AscendErrorFallback(
          details: details,
          showDetails: !kReleaseMode,
        );
      };

      // Trampa 1: errores del framework.
      FlutterError.onError = (FlutterErrorDetails details) {
        logger.error(
          'FlutterError',
          error: details.exception,
          stackTrace: details.stack,
        );
        if (!kReleaseMode) {
          FlutterError.presentError(details);
        }
      };

      // Trampa 2: errores asincrónicos que escapan de la zona.
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        logger.error(
          'Error no capturado en la plataforma',
          error: error,
          stackTrace: stack,
        );
        return true; // manejado: no se propaga y no mata la app
      };

      await body();
    },
    // Trampa 3: cualquier cosa que se haya escapado de las anteriores.
    (Object error, StackTrace stackTrace) => logger.error(
      'Error no capturado en la zona raíz',
      error: error,
      stackTrace: stackTrace,
    ),
  );
}

/// Registra los fallos que ocurren dentro de los providers.
///
/// Un error en un provider puede quedar contenido en su `AsyncValue` y no
/// aparecer nunca en los logs. Esto garantiza que igual quede registrado.
final class AscendProviderLogger extends ProviderObserver {
  /// Crea el observador.
  const AscendProviderLogger({String loggerName = 'providers'})
    : _loggerName = loggerName;

  final String _loggerName;

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    AscendLogger(_loggerName).error(
      'Provider falló: ${context.provider.name ?? context.provider.runtimeType}',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
