import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Contenedor de las cuatro secciones principales con la barra inferior.
///
/// Usa `StatefulShellRoute`, así que cada pestaña conserva su propia pila de
/// navegación: si entrás al detalle de un objetivo, vas a Comunidad y volvés,
/// seguís en el detalle. Perder ese estado es de las cosas que más molestan de
/// una app y no cuesta nada evitarlo.
class AppShell extends ConsumerWidget {
  /// Crea el shell.
  const AppShell({required this.navigationShell, super.key});

  /// Shell de navegación provisto por GoRouter.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El banner offline vive acá, encima del contenido: se ve en toda la app
    // sin que cada pantalla tenga que acordarse de mostrarlo.
    // Ante la duda se asume que hay conexión: mostrar el banner de offline por
    // error es más molesto que no mostrarlo un segundo de más.
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

    return Scaffold(
      body: Column(
        children: <Widget>[
          if (!isOnline) const OfflineBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      floatingActionButton: navigationShell.currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => context.push(Routes.missionNew),
              tooltip: 'Nueva misión',
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today_rounded),
            label: 'Hoy',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag_rounded),
            label: 'Objetivos',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public_rounded),
            label: 'Comunidad',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Perfil',
          ),
        ],
      ),
      // Atajo a la pantalla de diagnóstico, nunca en producción.
      persistentFooterButtons: AppFlavor.current.showsDebugTools
          ? <Widget>[
              TextButton.icon(
                onPressed: () => context.push(Routes.devTools),
                icon: const Icon(Icons.bug_report_outlined, size: 16),
                label: const Text('Diagnóstico'),
              ),
            ]
          : null,
    );
  }

  void _onDestinationSelected(int index) {
    // Tocar la pestaña activa vuelve a su raíz: el gesto que todo el mundo
    // espera y que casi ninguna app implementa.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
