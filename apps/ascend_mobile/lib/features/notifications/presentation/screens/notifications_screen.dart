import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/notifications/application/notifications_controller.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Bandeja de notificaciones.
///
/// Se alimenta de Firestore, **no de las push**. Sin permiso de notificaciones,
/// sin token o sin conexión en el momento del envío, lo que pasó igual está
/// acá la próxima vez que se abre la app. Si dependiera de las push, rechazar
/// el permiso equivaldría a no enterarse nunca de nada.
class NotificationsScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationsProvider);
    final action = ref.watch(notificationsControllerProvider);
    final failure = action.error is Failure ? action.error! as Failure : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: <Widget>[
          IconButton(
            onPressed: action.isLoading
                ? null
                : () => ref
                      .read(notificationsControllerProvider.notifier)
                      .markAllRead(),
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Marcar todas como leídas',
          ),
          IconButton(
            onPressed: () => context.push(Routes.settingsNotifications),
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Preferencias',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (failure != null)
            Padding(
              padding: const EdgeInsets.all(AscendSpacing.lg),
              child: ErrorStateView(failure: failure, compact: true),
            ),
          const _PermissionBanner(),
          Expanded(
            child: AsyncStateBuilder<Result<List<AppNotification>>>(
              value: inbox,
              onRetry: () => ref.invalidate(notificationsProvider),
              data: (Result<List<AppNotification>> result) =>
                  result.fold<Widget>(
                    onFailure: (Failure f) => ErrorStateView(
                      failure: f,
                      onRetry: () => ref.invalidate(notificationsProvider),
                    ),
                    onSuccess: (List<AppNotification> items) => items.isEmpty
                        ? const EmptyStateView(
                            title: 'Nada por acá',
                            message:
                                'Los avisos de tus misiones, tu racha y tu '
                                'comunidad van a aparecer en esta pantalla.',
                            icon: Icons.notifications_none_rounded,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              vertical: AscendSpacing.sm,
                            ),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, int index) =>
                                _NotificationTile(notification: items[index]),
                          ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Explicación previa al pedido de permiso.
///
/// El diálogo del sistema se muestra **una sola vez**. Lanzarlo al abrir la app,
/// antes de que se entienda para qué sirve, hace que la mayoría lo rechace — y
/// ese rechazo solo se revierte desde los ajustes del sistema, que casi nadie
/// abre. Con una explicación propia se puede volver a ofrecer más adelante sin
/// gastar la única oportunidad.
class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(notificationPermissionProvider).value;
    if (permission == null || permission == NotificationPermission.granted) {
      return const SizedBox.shrink();
    }

    final canAsk = shouldExplainBeforeAsking(permission);

    return Container(
      margin: const EdgeInsets.all(AscendSpacing.lg),
      padding: const EdgeInsets.all(AscendSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AscendRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.notifications_active_outlined,
                color: context.colors.primary,
              ),
              const SizedBox(width: AscendSpacing.md),
              Expanded(
                child: Text(
                  canAsk
                      ? 'Activá los avisos para que no se te pase una misión '
                            'ni se te corte la racha.'
                      : 'Los avisos están desactivados. Se vuelven a activar '
                            'desde los ajustes del sistema.',
                  style: context.texts.bodySmall,
                ),
              ),
            ],
          ),
          if (canAsk) ...<Widget>[
            const SizedBox(height: AscendSpacing.md),
            AscendButton(
              label: 'Activar avisos',
              onPressed: () =>
                  ref.read(notificationsControllerProvider.notifier).enable(),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final route = await ref
        .read(notificationsControllerProvider.notifier)
        .open(notification);

    if (route == null || !context.mounted) {
      return;
    }
    context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    // El fondo distingue leídas de no leídas sin un punto de color extra: la
    // bandeja se escanea de un vistazo y un indicador diminuto no se ve.
    tileColor: notification.read
        ? null
        : context.colors.primary.withValues(alpha: 0.06),
    leading: CircleAvatar(
      backgroundColor: context.colors.primary.withValues(alpha: 0.14),
      child: Icon(
        _iconFor(notification.type),
        size: 20,
        color: context.colors.primary,
      ),
    ),
    title: Text(
      notification.title,
      style: context.texts.bodyMedium?.copyWith(
        fontWeight: notification.read ? FontWeight.w500 : FontWeight.w700,
      ),
    ),
    subtitle: Text(notification.body, style: context.texts.bodySmall),
    trailing: Text(
      AscendDateUtils.relativeLabel(notification.createdAt),
      style: context.texts.labelSmall?.copyWith(
        color: context.ascend.textSecondary,
      ),
    ),
    onTap: () => _open(context, ref),
  );

  static IconData _iconFor(NotificationType type) => switch (type) {
    NotificationType.missionReminder => Icons.task_alt_rounded,
    NotificationType.streakWarning => Icons.local_fire_department_rounded,
    NotificationType.auraGained => Icons.auto_awesome_rounded,
    NotificationType.levelUp => Icons.military_tech_rounded,
    NotificationType.newLike => Icons.favorite_rounded,
    NotificationType.newComment => Icons.mode_comment_rounded,
    NotificationType.newFollower => Icons.person_add_alt_rounded,
    NotificationType.aiSuggestion => Icons.smart_toy_rounded,
    NotificationType.moderationAction => Icons.gavel_rounded,
    NotificationType.system => Icons.campaign_rounded,
  };
}
