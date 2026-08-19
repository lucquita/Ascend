import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Arranque del panel de administración.
///
/// Usa la misma red de captura de errores que la app móvil (`runAscendGuarded`,
/// en el design system). En un panel interno una pantalla rota sin explicación
/// cuesta tanto tiempo como en producción: quien lo usa no puede leer el stack
/// trace en la consola del navegador para saber qué hacer.
///
/// A diferencia del móvil no bloquea la orientación —es web— y no hay nada más
/// específico: la inicialización de Firebase es idéntica, contra el mismo
/// proyecto y con el mismo App Check.
Future<void> bootstrap(Widget Function() builder) =>
    runAscendGuarded(loggerName: 'admin', () async {
      const logger = AscendLogger('admin');

      await FirebaseConfig.initialize();

      logger.info(
        'Panel de Ascend arrancando',
        context: <String, Object?>{
          'flavor': AppFlavor.current.key,
          'backend': FirebaseConfig.isAvailable ? 'firebase' : 'sin backend',
        },
      );

      runApp(
        ProviderScope(
          observers: const <ProviderObserver>[
            AscendProviderLogger(loggerName: 'admin.providers'),
          ],
          child: builder(),
        ),
      );
    });
