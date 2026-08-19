import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Acceso a la bandeja, con la cantidad sin leer.
///
/// La insignia es lo que hace descubrible a la bandeja: sin un número visible,
/// nadie entra a una pantalla a ver si pasó algo. Y es lo que sostiene la
/// promesa de que sin permiso de notificaciones igual se puede uno enterar.
class NotificationBell extends ConsumerWidget {
  /// Crea el acceso.
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Un fallo leyendo el contador se trata como cero: la campana tiene que
    // seguir llevando a la bandeja aunque no se sepa cuántas hay.
    final badge = UnreadBadge(
      ref.watch(unreadNotificationsProvider).value ?? 0,
    );

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        IconButton(
          onPressed: () => context.push(Routes.notifications),
          icon: const Icon(Icons.notifications_outlined),
          tooltip: 'Notificaciones',
        ),
        if (badge.isVisible)
          Positioned(
            top: 6,
            right: 4,
            // `IgnorePointer` para que la insignia no se coma el toque: sin
            // esto, tocar justo el número no abre la bandeja.
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AscendSpacing.xxs,
                ),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: context.colors.error,
                  borderRadius: BorderRadius.circular(AscendRadius.full),
                ),
                child: Text(
                  badge.label,
                  textAlign: TextAlign.center,
                  style: context.texts.labelSmall?.copyWith(
                    color: context.colors.onError,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
