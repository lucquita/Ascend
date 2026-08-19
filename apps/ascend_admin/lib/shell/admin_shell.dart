import 'package:ascend_admin/features/auth/application/admin_session.dart';
import 'package:ascend_admin/router/admin_router.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Marco del panel: barra superior más menú lateral.
///
/// Es responsive por decisión de producto, no por capricho: el equipo de
/// moderación va a resolver reportes desde el celular tanto como desde el
/// escritorio. Por encima de 1024px el menú queda fijo; por debajo se convierte
/// en un drawer.
class AdminShell extends ConsumerWidget {
  /// Crea el marco del panel.
  const AdminShell({required this.child, required this.location, super.key});

  /// Contenido de la sección activa.
  final Widget child;

  /// Ruta actual, para marcar la sección seleccionada.
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ResponsiveBuilder(
    builder: (context, size, constraints) {
      final isWide = size == ScreenSize.desktop;

      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: <Widget>[
              Icon(Icons.trending_up_rounded, color: context.colors.primary),
              const SizedBox(width: AscendSpacing.sm),
              Text('Ascend', style: context.texts.titleLarge),
              const SizedBox(width: AscendSpacing.sm),
              Text(
                'Panel',
                style: context.texts.labelMedium?.copyWith(
                  color: context.ascend.textSecondary,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            // Quién está operando el panel se muestra siempre: en un backoffice
            // compartido, actuar creyendo ser otra persona es la forma más
            // fácil de suspender la cuenta equivocada.
            Text(
              ref.watch(adminUserProvider)?.email ?? '',
              style: context.texts.bodySmall?.copyWith(
                color: context.ascend.textSecondary,
              ),
            ),
            const SizedBox(width: AscendSpacing.md),
            IconButton(
              onPressed: () =>
                  ref.read(adminAuthControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Cerrar sesión',
            ),
            const SizedBox(width: AscendSpacing.lg),
          ],
        ),
        drawer: isWide ? null : Drawer(child: _Menu(location: location)),
        body: Row(
          children: <Widget>[
            if (isWide)
              SizedBox(
                width: 260,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    border: Border(
                      right: BorderSide(color: context.colors.outline),
                    ),
                  ),
                  child: _Menu(location: location),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      );
    },
  );
}

class _Menu extends StatelessWidget {
  const _Menu({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: AscendSpacing.md),
    children: <Widget>[
      for (final section in AdminSection.values)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AscendSpacing.md,
            vertical: AscendSpacing.xxs,
          ),
          child: _MenuItem(
            section: section,
            selected: location == section.path,
          ),
        ),
    ],
  );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.section, required this.selected});

  final AdminSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.colors.primary
        : context.ascend.textSecondary;

    return Material(
      color: selected
          ? context.colors.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: AscendRadius.buttonRadius,
      child: InkWell(
        borderRadius: AscendRadius.buttonRadius,
        onTap: () => context.go(section.path),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AscendSpacing.md,
            vertical: AscendSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Icon(section.icon, size: 20, color: color),
              const SizedBox(width: AscendSpacing.md),
              Expanded(
                child: Text(
                  section.label,
                  style: context.texts.labelMedium?.copyWith(
                    color: selected ? color : context.colors.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              // Se marca lo que todavía es un placeholder en vez de dejar que
              // alguien lo descubra recién al hacer clic.
              if (!section.isImplemented)
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: context.ascend.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
