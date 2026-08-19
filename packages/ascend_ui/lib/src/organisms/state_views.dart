import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_ui/src/organisms/failure_messages.dart';
import 'package:ascend_ui/src/theme/ascend_theme.dart';
import 'package:ascend_ui/src/tokens/ascend_tokens.dart';
import 'package:flutter/material.dart';

/// Vista de error amigable.
///
/// Nunca muestra la excepción cruda. Muestra qué pasó, qué puede hacer la
/// persona y un botón de reintentar solo cuando reintentar tiene sentido
/// (`Failure.isRetryable`): ofrecer "Reintentar" ante un error de permisos es
/// mentirle al usuario.
class ErrorStateView extends StatelessWidget {
  /// Crea la vista de error a partir de un [Failure].
  const ErrorStateView({
    required this.failure,
    this.onRetry,
    this.compact = false,
    super.key,
  });

  /// El fallo a comunicar.
  final Failure failure;

  /// Acción de reintento. Si es `null` no se muestra el botón.
  final VoidCallback? onRetry;

  /// Versión reducida, para incrustar dentro de una tarjeta o lista.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final display = AscendFailureMessages.describe(failure);
    final showRetry = onRetry != null && failure.isRetryable;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(AscendSpacing.lg),
        child: Row(
          children: <Widget>[
            Icon(_iconFor(failure), color: context.colors.error, size: 20),
            const SizedBox(width: AscendSpacing.md),
            Expanded(
              child: Text(display.message, style: context.texts.bodyMedium),
            ),
            if (showRetry)
              TextButton(
                onPressed: onRetry,
                child: Text(display.actionLabel ?? 'Reintentar'),
              ),
          ],
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AscendSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _StateIcon(icon: _iconFor(failure), color: context.colors.error),
            const SizedBox(height: AscendSpacing.xl),
            Text(
              display.title,
              style: context.texts.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AscendSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                display.message,
                style: context.texts.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            if (showRetry) ...<Widget>[
              const SizedBox(height: AscendSpacing.xl),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(display.actionLabel ?? 'Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(Failure failure) => switch (failure) {
    NetworkFailure() || QueuedOfflineFailure() => Icons.wifi_off_rounded,
    TimeoutFailure() => Icons.hourglass_empty_rounded,
    PermissionFailure() => Icons.lock_outline_rounded,
    NotFoundFailure() => Icons.search_off_rounded,
    QuotaFailure() => Icons.hourglass_bottom_rounded,
    UnsupportedVersionFailure() => Icons.system_update_rounded,
    ValidationFailure() => Icons.edit_note_rounded,
    AuthFailure() => Icons.person_off_outlined,
    ServerFailure() || UnknownFailure() => Icons.cloud_off_rounded,
  };
}

/// Estado vacío con ilustración, explicación y llamada a la acción.
///
/// En Ascend un estado vacío nunca es solo "No hay nada": siempre propone el
/// siguiente paso. Una lista vacía sin salida es una pantalla muerta.
class EmptyStateView extends StatelessWidget {
  /// Crea un estado vacío.
  const EmptyStateView({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Título del estado vacío.
  final String title;

  /// Explicación y sugerencia de qué hacer.
  final String message;

  /// Icono ilustrativo.
  final IconData icon;

  /// Etiqueta del botón principal.
  final String? actionLabel;

  /// Acción del botón principal.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AscendSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StateIcon(icon: icon, color: context.colors.primary),
          const SizedBox(height: AscendSpacing.xl),
          Text(
            title,
            style: context.texts.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AscendSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message,
              style: context.texts.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: AscendSpacing.xl),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

/// Banner persistente de "sin conexión".
///
/// Se muestra arriba del contenido, no encima: la persona sigue viendo y
/// usando sus datos cacheados. Bloquear la app por falta de red convertiría un
/// inconveniente en una pared.
class OfflineBanner extends StatelessWidget {
  /// Crea el banner de estado offline.
  const OfflineBanner({
    this.message = 'Sin conexión. Tus cambios se sincronizan solos.',
    this.pendingCount = 0,
    super.key,
  });

  /// Texto a mostrar.
  final String message;

  /// Cantidad de operaciones esperando en la cola de subida.
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final ascend = context.ascend;
    return Material(
      color: ascend.warning.withValues(alpha: 0.12),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AscendSpacing.lg,
            vertical: AscendSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.cloud_off_rounded, size: 18, color: ascend.warning),
              const SizedBox(width: AscendSpacing.md),
              Expanded(
                child: Text(
                  pendingCount > 0
                      ? '$message ($pendingCount pendiente'
                            '${pendingCount == 1 ? '' : 's'})'
                      : message,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    height: 88,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 40, color: color),
  );
}
