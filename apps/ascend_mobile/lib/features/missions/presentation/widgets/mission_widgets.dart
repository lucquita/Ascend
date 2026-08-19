import 'package:ascend_domain/ascend_domain.dart';
// `MissionDifficultyPresentation` vive en la feature de objetivos porque nació
// ahí: la dificultad es un atributo del objetivo además de la misión. La
// dependencia va en un solo sentido (misiones → objetivos), igual que en el
// modelo, donde una misión no existe sin su objetivo.
import 'package:ascend_mobile/features/goals/presentation/widgets/goal_widgets.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';

/// Textos e iconos de presentación de [MissionBudget].
extension MissionBudgetPresentation on MissionBudget {
  /// Etiqueta corta.
  String get label => switch (this) {
    MissionBudget.free => 'Gratis',
    MissionBudget.low => 'Bajo',
    MissionBudget.medium => 'Medio',
    MissionBudget.high => 'Alto',
  };

  /// Icono asociado.
  IconData get icon => switch (this) {
    MissionBudget.free => Icons.money_off_rounded,
    MissionBudget.low => Icons.attach_money_rounded,
    MissionBudget.medium => Icons.payments_outlined,
    MissionBudget.high => Icons.account_balance_wallet_outlined,
  };
}

/// Textos de presentación de [MissionStatus].
extension MissionStatusPresentation on MissionStatus {
  /// Etiqueta corta.
  String get label => switch (this) {
    MissionStatus.pending => 'Pendiente',
    MissionStatus.inProgress => 'En curso',
    MissionStatus.completed => 'Completada',
    MissionStatus.skipped => 'Salteada',
    MissionStatus.expired => 'Vencida',
  };
}

/// Fila de una misión, con su casilla de completado.
///
/// Es el componente más tocado de la app: aparece en "Hoy", en el detalle del
/// objetivo y en el historial.
class MissionTile extends StatelessWidget {
  /// Crea la fila.
  const MissionTile({
    required this.mission,
    required this.onToggle,
    this.onTap,
    this.enabled = true,
    this.showGoal = false,
    super.key,
  });

  /// Misión a mostrar.
  final Mission mission;

  /// Se dispara al tocar la casilla.
  final VoidCallback onToggle;

  /// Se dispara al tocar la fila.
  final VoidCallback? onTap;

  /// Si acepta interacción.
  final bool enabled;

  /// Si muestra el objetivo al que pertenece. Se usa en "Hoy", donde conviven
  /// misiones de varios objetivos.
  final bool showGoal;

  @override
  Widget build(BuildContext context) {
    final done = mission.status.isCompleted;
    final closed = !mission.status.isOpen;
    final overdue = mission.isOverdue();

    return Padding(
      padding: const EdgeInsets.only(bottom: AscendSpacing.sm),
      child: Material(
        color: context.colors.surface,
        borderRadius: AscendRadius.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AscendRadius.cardRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AscendSpacing.md,
              vertical: AscendSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: AscendRadius.cardRadius,
              border: Border.all(color: context.colors.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Checkbox(
                  value: done,
                  // Una misión cerrada —completada, salteada o vencida— no se
                  // vuelve a tocar desde acá: `canComplete` ya lo impide en el
                  // dominio y deshabilitarlo evita el toque inútil.
                  onChanged: enabled && !closed ? (_) => onToggle() : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: AscendSpacing.md),
                      Text(
                        mission.title,
                        style: context.texts.bodyLarge?.copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: closed ? context.ascend.textSecondary : null,
                        ),
                      ),
                      if (showGoal && mission.goalTitle != null) ...<Widget>[
                        const SizedBox(height: AscendSpacing.xxs),
                        Text(
                          mission.goalTitle!,
                          style: context.texts.labelSmall?.copyWith(
                            color: context.ascend.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AscendSpacing.sm),
                      // `Wrap` y no `Row`: con el texto escalado por
                      // accesibilidad, cuatro metadatos en fila desbordan.
                      Wrap(
                        spacing: AscendSpacing.md,
                        runSpacing: AscendSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          _Meta(
                            icon: Icons.speed_rounded,
                            label: mission.difficulty.label,
                          ),
                          if (!mission.budget.isFree)
                            _Meta(
                              icon: mission.budget.icon,
                              label: mission.budget.label,
                            ),
                          if (mission.estimatedMinutes != null)
                            _Meta(
                              icon: Icons.schedule_rounded,
                              label: '${mission.estimatedMinutes} min',
                            ),
                          if (mission.requiresEvidence)
                            const _Meta(
                              icon: Icons.photo_camera_outlined,
                              label: 'Con foto',
                            ),
                          if (overdue)
                            _Meta(
                              icon: Icons.warning_amber_rounded,
                              label: 'Vencida',
                              color: context.colors.error,
                            ),
                          if (mission.status == MissionStatus.skipped)
                            _Meta(
                              icon: Icons.skip_next_rounded,
                              label: mission.status.label,
                            ),
                        ],
                      ),
                      const SizedBox(height: AscendSpacing.sm),
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

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? context.ascend.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: effective),
        const SizedBox(width: AscendSpacing.xs),
        Text(
          label,
          style: context.texts.labelSmall?.copyWith(color: effective),
        ),
      ],
    );
  }
}

/// Cabecera de "Hoy": cuánto se avanzó en el día.
class DailyProgressHeader extends StatelessWidget {
  /// Crea la cabecera.
  const DailyProgressHeader({required this.progress, super.key});

  /// Resumen del día.
  final DailyProgress progress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AscendSpacing.lg,
      vertical: AscendSpacing.md,
    ),
    child: Row(
      children: <Widget>[
        ProgressRing(
          progress: progress.fraction,
          size: 56,
          color: progress.isDone
              ? context.ascend.success
              : context.colors.primary,
          child: Text(
            '${progress.completed}/${progress.total}',
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
                progress.isDone ? '¡Día completo!' : 'Tu día',
                style: context.texts.titleMedium,
              ),
              const SizedBox(height: AscendSpacing.xxs),
              Text(
                switch (progress) {
                  DailyProgress(total: 0) => 'Nada agendado para hoy.',
                  DailyProgress(isDone: true) =>
                    'Completaste todo lo que te propusiste.',
                  final p =>
                    'Te ${p.remaining == 1 ? 'queda' : 'quedan'} '
                        '${p.remaining} ${p.remaining == 1 ? 'misión' : 'misiones'}.',
                },
                style: context.texts.bodySmall?.copyWith(
                  color: context.ascend.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
