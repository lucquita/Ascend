import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_l10n/ascend_l10n.dart';
import 'package:ascend_mobile/features/notifications/application/push_deep_links.dart';
import 'package:ascend_mobile/router/app_router.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Modo de tema efectivo, leído de los ajustes de la persona.
///
/// Si todavía no hay perfil cargado —o falló su lectura— se usa el del sistema.
/// Un fallo al leer preferencias no puede impedir que la app se pinte.
final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>((ref) {
  final profile = ref.watch(profileProvider).value?.valueOrNull;
  return switch (profile?.settings.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}, name: 'themeMode');

/// Raíz de la aplicación móvil.
class AscendApp extends ConsumerWidget {
  /// Crea la app.
  const AscendApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return AscendFailureMessages(
      // Instala el traductor de fallos para toda la app: a partir de acá,
      // cualquier `ErrorStateView` sabe cómo hablarle a la persona.
      resolve: AscendFailureMessages.defaultResolver,
      child: MaterialApp.router(
        title: AppFlavor.current.appName,
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        theme: AscendTheme.light,
        darkTheme: AscendTheme.dark,
        themeMode: themeMode,
        localizationsDelegates: AscendL10n.localizationsDelegates,
        supportedLocales: AscendL10n.supportedLocales,
        builder: (context, child) {
          // Tope al escalado de texto: respetamos la preferencia de
          // accesibilidad del sistema hasta 1.5x, que es donde nuestros
          // layouts siguen funcionando sin desbordarse.
          final scale = MediaQuery.textScalerOf(
            context,
          ).clamp(maxScaleFactor: 1.5);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scale),
            // Los dos envoltorios van acá adentro y no afuera del router: los
            // deep links necesitan un `context` que ya tenga el `GoRouter`
            // montado, y el registro del dispositivo tiene que sobrevivir a
            // los cambios de pantalla.
            child: DeviceRegistrar(
              child: PushDeepLinks(child: child ?? const SizedBox.shrink()),
            ),
          );
        },
      ),
    );
  }
}
