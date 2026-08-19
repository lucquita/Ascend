import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';

/// Textos e iconos de presentación de [GoalStatus].
///
/// Vive en la capa de presentación y no en el enum del dominio: el dominio no
/// sabe de idiomas ni de iconos de Material, y meterlo ahí lo acoplaría a
/// Flutter.
extension GoalStatusPresentation on GoalStatus {
  /// Etiqueta corta para chips y menús.
  String get label => switch (this) {
    GoalStatus.draft => 'Borrador',
    GoalStatus.active => 'En curso',
    GoalStatus.paused => 'En pausa',
    GoalStatus.completed => 'Completado',
    GoalStatus.archived => 'Archivado',
  };

  /// Icono asociado.
  IconData get icon => switch (this) {
    GoalStatus.draft => Icons.edit_note_rounded,
    GoalStatus.active => Icons.play_circle_outline_rounded,
    GoalStatus.paused => Icons.pause_circle_outline_rounded,
    GoalStatus.completed => Icons.check_circle_outline_rounded,
    GoalStatus.archived => Icons.inventory_2_outlined,
  };
}

/// Textos de presentación de [MissionDifficulty].
extension MissionDifficultyPresentation on MissionDifficulty {
  /// Etiqueta corta.
  String get label => switch (this) {
    MissionDifficulty.easy => 'Fácil',
    MissionDifficulty.medium => 'Media',
    MissionDifficulty.hard => 'Difícil',
  };
}

/// Convierte `#RRGGBB` en un [Color].
///
/// Devuelve `null` ante cualquier cosa que no sea un color válido en vez de
/// lanzar: un `colorHex` corrupto en un documento no puede tumbar la lista.
Color? parseHexColor(String? hex) {
  if (hex == null) {
    return null;
  }
  final cleaned = hex.replaceFirst('#', '').trim();
  if (cleaned.length != 6) {
    return null;
  }
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// Chip de estado de un objetivo.
class GoalStatusChip extends StatelessWidget {
  /// Crea el chip.
  const GoalStatusChip({required this.status, super.key});

  /// Estado a mostrar.
  final GoalStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      GoalStatus.completed => context.ascend.success,
      GoalStatus.paused => context.ascend.warning,
      GoalStatus.archived => context.ascend.textDisabled,
      _ => context.colors.primary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AscendSpacing.sm,
        vertical: AscendSpacing.xxs,
      ),
      decoration: BoxDecoration(
        // Fondo tenue del mismo tono: el color pleno con texto encima no llega
        // a contraste AA en varios de estos tonos.
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AscendRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(status.icon, size: 14, color: color),
          const SizedBox(width: AscendSpacing.xs),
          Text(
            status.label,
            style: context.texts.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de un objetivo en la lista.
class GoalCard extends StatelessWidget {
  /// Crea la tarjeta.
  const GoalCard({
    required this.goal,
    required this.onTap,
    this.categoryName,
    super.key,
  });

  /// Objetivo a mostrar.
  final Goal goal;

  /// Nombre de la categoría ya resuelto. Si es `null` se omite el chip.
  final String? categoryName;

  /// Acción al tocar la tarjeta.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent =
        parseHexColor(goal.colorHex) ??
        (goal.status == GoalStatus.completed
            ? context.ascend.success
            : context.colors.primary);
    final overdue = goal.isOverdue();

    return Padding(
      padding: const EdgeInsets.only(bottom: AscendSpacing.md),
      child: Material(
        color: context.colors.surface,
        borderRadius: AscendRadius.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AscendRadius.cardRadius,
          child: Container(
            padding: AscendSpacing.card,
            decoration: BoxDecoration(
              borderRadius: AscendRadius.cardRadius,
              border: Border.all(color: context.colors.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ProgressRing(
                  progress: goal.progress.fraction,
                  size: 48,
                  strokeWidth: 5,
                  color: accent,
                  child: Text(
                    '${goal.progress.percent.round()}%',
                    style: context.texts.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AscendSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        goal.title,
                        style: context.texts.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AscendSpacing.xs),
                      Text(
                        goal.progress.missionsTotal == 0
                            // Sin misiones el porcentaje siempre sería 0% y
                            // parecería un objetivo abandonado. Se dice lo que
                            // realmente pasa y qué hacer al respecto.
                            ? 'Todavía sin misiones'
                            : '${goal.progress.missionsCompleted} de '
                                  '${goal.progress.missionsTotal} misiones',
                        style: context.texts.bodySmall?.copyWith(
                          color: context.ascend.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AscendSpacing.sm),
                      // `Wrap` y no `Row`: con el texto escalado por
                      // accesibilidad, tres chips en fila desbordan.
                      Wrap(
                        spacing: AscendSpacing.sm,
                        runSpacing: AscendSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          GoalStatusChip(status: goal.status),
                          if (categoryName != null)
                            Text(
                              categoryName!,
                              style: context.texts.labelSmall?.copyWith(
                                color: context.ascend.textSecondary,
                              ),
                            ),
                          if (overdue)
                            Text(
                              'Fecha vencida',
                              style: context.texts.labelSmall?.copyWith(
                                color: context.colors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de un hito, con su casilla.
class MilestoneTile extends StatelessWidget {
  /// Crea la fila.
  const MilestoneTile({
    required this.milestone,
    required this.onToggle,
    this.enabled = true,
    super.key,
  });

  /// Hito a mostrar.
  final Milestone milestone;

  /// Se dispara al cambiar la casilla.
  final ValueChanged<bool> onToggle;

  /// Si acepta interacción.
  final bool enabled;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: milestone.done,
    onChanged: enabled ? (value) => onToggle(value ?? false) : null,
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(
      milestone.title,
      style: context.texts.bodyMedium?.copyWith(
        decoration: milestone.done ? TextDecoration.lineThrough : null,
        color: milestone.done ? context.ascend.textSecondary : null,
      ),
    ),
  );
}
