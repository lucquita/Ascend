import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Arranque de la aplicación móvil.
///
/// La red de captura de errores —las cuatro trampas que garantizan que nunca se
/// vea una pantalla roja de Flutter— vive en `runAscendGuarded`, dentro del
/// design system, porque el panel de administración necesita exactamente la
/// misma y una copia se desincroniza tarde o temprano.
///
/// Acá queda solo lo propio del móvil: bloquear la orientación e inicializar
/// Firebase.
Future<void> bootstrap(Widget Function() builder) => runAscendGuarded(() async {
  const logger = AscendLogger('bootstrap');

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  await FirebaseConfig.initialize();

  logger.info(
    'Ascend arrancando',
    context: <String, Object?>{
      'flavor': AppFlavor.current.key,
      'backend': FirebaseConfig.isAvailable ? 'firebase' : 'sin backend',
    },
  );

  runApp(
    ProviderScope(
      observers: const <ProviderObserver>[AscendProviderLogger()],
      child: builder(),
    ),
  );
});
