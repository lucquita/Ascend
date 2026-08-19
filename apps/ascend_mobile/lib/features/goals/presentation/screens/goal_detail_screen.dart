import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/goals/application/goals_controller.dart';
import 'package:ascend_mobile/features/goals/presentation/widgets/goal_widgets.dart';
import 'package:ascend_mobile/features/missions/application/missions_controller.dart';
import 'package:ascend_mobile/features/missions/presentation/widgets/mission_widgets.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Detalle de un objetivo: progreso, hitos y acciones de estado.
class GoalDetailScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const GoalDetailScreen({required this.goalId, super.key});

  /// Id del objetivo.
  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(goalDetailProvider(goalId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Objetivo'),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.push(Routes.goalEdit(goalId)),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar',
          ),
        ],
      ),
      body: AsyncStateBuilder<Result<Goal>>(
        value: goal,
        onRetry: () => ref.invalidate(goalDetailProvider(goalId)),
        data: (Result<Goal> result) => result.fold<Widget>(
          onSuccess: (Goal value) => _GoalDetailBody(goal: value),
          onFailure: (Failure failure) => ErrorStateView(
            failure: failure,
            onRetry: () => ref.invalidate(goalDetailProvider(goalId)),
          ),
        ),
      ),
    );
  }
}

class _GoalDetailBody extends ConsumerWidget {
  const _GoalDetailBody({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goalControllerProvider);
    final isBusy = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;
    final accent =
        parseHexColor(goal.colorHex) ??
        (goal.status == GoalStatus.completed
            ? context.ascend.success
            : context.colors.primary);

    return ListView(
      padding: const EdgeInsets.all(AscendSpacing.lg),
      children: <Widget>[
        if (failure != null) ...<Widget>[
          ErrorStateView(failure: failure, compact: true),
          const SizedBox(height: AscendSpacing.lg),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ProgressRing(
              progress: goal.progress.fraction,
              size: 72,
              strokeWidth: 7,
              color: accent,
              child: Text(
                '${goal.progress.percent.round()}%',
                style: context.texts.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AscendSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(goal.title, style: context.texts.headlineSmall),
                  const SizedBox(height: AscendSpacing.sm),
                  GoalStatusChip(status: goal.status),
                ],
              ),
            ),
          ],
        ),
        if (goal.description != null) ...<Widget>[
          const SizedBox(height: AscendSpacing.xl),
          Text(goal.description!, style: context.texts.bodyMedium),
        ],
        const SizedBox(height: AscendSpacing.xl),
        _InfoRow(
          icon: Icons.speed_rounded,
          label: 'Exigencia',
          value: goal.difficulty.label,
        ),
        if (goal.targetDate != null)
          _InfoRow(
            icon: Icons.event_outlined,
            label: 'Fecha objetivo',
            value: MaterialLocalizations.of(
              context,
            ).formatMediumDate(goal.targetDate!),
            highlight: goal.isOverdue(),
          ),
        _InfoRow(
          icon: Icons.task_alt_rounded,
          label: 'Misiones',
          value: goal.progress.missionsTotal == 0
              // El progreso lo calcula el servidor; mientras no exista el
              // trigger, decir "0 de 0" parecería un error. La lista de abajo
              // muestra las misiones reales igual.
              ? 'Sin progreso calculado'
              : '${goal.progress.missionsCompleted} de '
                    '${goal.progress.missionsTotal} completadas',
        ),
        if (goal.auraEarned > 0)
          _InfoRow(
            icon: Icons.auto_awesome_rounded,
            label: 'Aura ganada',
            value: '${goal.auraEarned}',
          ),
        if (goal.milestones.isNotEmpty) ...<Widget>[
          const SizedBox(height: AscendSpacing.xl),
          Text('Hitos', style: context.texts.titleMedium),
          const SizedBox(height: AscendSpacing.sm),
          for (final milestone in goal.milestones)
            MilestoneTile(
              milestone: milestone,
              enabled: !isBusy && goal.status.isEditable,
              onToggle: (done) => ref
                  .read(goalControllerProvider.notifier)
                  .toggleMilestone(
                    goalId: goal.id,
                    milestoneId: milestone.id,
                    done: done,
                  ),
            ),
        ],
        const SizedBox(height: AscendSpacing.xl),
        _MissionsSection(goal: goal),
        const SizedBox(height: AscendSpacing.xxl),
        _StatusActions(goal: goal, isBusy: isBusy),
        const SizedBox(height: AscendSpacing.lg),
        _DeleteButton(goal: goal, isBusy: isBusy),
      ],
    );
  }
}

/// Misiones del objetivo, en vivo.
///
/// Va embebida en el detalle y no en una pantalla aparte: un objetivo sin sus
/// misiones a la vista es una promesa sin plan, y el salto extra de navegación
/// desalienta justamente la acción que el producto quiere provocar.
class _MissionsSection extends ConsumerWidget {
  const _MissionsSection({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missions = ref.watch(missionsByGoalProvider(goal.id));
    final isBusy = ref.watch(missionControllerProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Misiones', style: context.texts.titleMedium),
            const Spacer(),
            if (goal.status.isEditable)
              TextButton.icon(
                onPressed: () => context.push(Routes.goalMissionNew(goal.id)),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Agregar'),
              ),
          ],
        ),
        const SizedBox(height: AscendSpacing.sm),
        AsyncStateBuilder<Result<List<Mission>>>(
          value: missions,
          // Skeletons en `Column` y no `AscendSkeletonList`: ese widget es un
          // `ListView`, y anidar un scroll vertical dentro del `ListView` del
          // detalle rompe el layout con "viewport was given unbounded height".
          loading: const Column(
            children: <Widget>[
              AscendSkeleton(height: 72),
              SizedBox(height: AscendSpacing.sm),
              AscendSkeleton(height: 72),
            ],
          ),
          onRetry: () => ref.invalidate(missionsByGoalProvider(goal.id)),
          isEmpty: (result) => result.valueOrNull?.isEmpty ?? false,
          emptyState: EmptyStateConfig(
            icon: Icons.checklist_rounded,
            title: 'Sin misiones todavía',
            message:
                'Un objetivo se cumple con acciones concretas. Agregá la '
                'primera.',
            actionLabel: goal.status.isEditable ? 'Agregar misión' : null,
            onAction: goal.status.isEditable
                ? () => context.push(Routes.goalMissionNew(goal.id))
                : null,
          ),
          data: (Result<List<Mission>> result) => result.fold<Widget>(
            onSuccess: (List<Mission> items) => Column(
              children: <Widget>[
                for (final mission in items)
                  MissionTile(
                    mission: mission,
                    enabled: !isBusy,
                    onTap: () => context.push(Routes.missionDetail(mission.id)),
                    onToggle: () => ref
                        .read(missionControllerProvider.notifier)
                        .complete(mission),
                  ),
              ],
            ),
            onFailure: (Failure failure) =>
                ErrorStateView(failure: failure, compact: true),
          ),
        ),
      ],
    );
  }
}

/// Acciones de cambio de estado disponibles según el estado actual.
class _StatusActions extends ConsumerWidget {
  const _StatusActions({required this.goal, required this.isBusy});

  final Goal goal;
  final bool isBusy;

  /// Transiciones que se ofrecen como botón, por estado de origen.
  ///
  /// Es un subconjunto de lo que permite `ChangeGoalStatusUseCase`: acá se
  /// eligen las que tienen sentido como acción principal de la pantalla. El
  /// caso de uso sigue siendo la autoridad y rechaza cualquier otra.
  static List<GoalStatus> _actionsFor(GoalStatus status) => switch (status) {
    GoalStatus.draft => <GoalStatus>[GoalStatus.active],
    GoalStatus.active => <GoalStatus>[GoalStatus.completed, GoalStatus.paused],
    GoalStatus.paused => <GoalStatus>[GoalStatus.active, GoalStatus.archived],
    GoalStatus.completed => <GoalStatus>[GoalStatus.archived],
    GoalStatus.archived => <GoalStatus>[GoalStatus.active],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = _actionsFor(goal.status);
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: <Widget>[
        for (final target in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: AscendSpacing.sm),
            child: AscendButton(
              label: _labelFor(target),
              icon: target.icon,
              variant: target == GoalStatus.completed
                  ? AscendButtonVariant.primary
                  : AscendButtonVariant.secondary,
              isLoading: isBusy,
              onPressed: isBusy
                  ? null
                  : () => ref
                        .read(goalControllerProvider.notifier)
                        .changeStatus(
                          goalId: goal.id,
                          from: goal.status,
                          to: target,
                        ),
            ),
          ),
      ],
    );
  }

  static String _labelFor(GoalStatus target) => switch (target) {
    GoalStatus.active => 'Retomar',
    GoalStatus.paused => 'Pausar',
    GoalStatus.completed => 'Marcar como completado',
    GoalStatus.archived => 'Archivar',
    GoalStatus.draft => 'Volver a borrador',
  };
}

/// Botón de borrado con confirmación.
class _DeleteButton extends ConsumerWidget {
  const _DeleteButton({required this.goal, required this.isBusy});

  final Goal goal;
  final bool isBusy;

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar este objetivo?'),
        content: const Text(
          'Se borran también sus misiones. Esta acción no se puede deshacer.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final deleted = await ref
        .read(goalControllerProvider.notifier)
        .delete(goal.id);
    // Solo se sale de la pantalla si el borrado salió bien: si falló, el
    // detalle sigue a la vista mostrando el error, en vez de volver a la lista
    // como si nada hubiera pasado.
    if (deleted && context.mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => AscendButton.destructive(
    label: 'Eliminar objetivo',
    icon: Icons.delete_outline_rounded,
    onPressed: isBusy ? null : () => _confirmAndDelete(context, ref),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AscendSpacing.md),
    child: Row(
      children: <Widget>[
        Icon(icon, size: 20, color: context.ascend.textSecondary),
        const SizedBox(width: AscendSpacing.md),
        Text(
          label,
          style: context.texts.bodyMedium?.copyWith(
            color: context.ascend.textSecondary,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: context.texts.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlight ? context.colors.error : null,
            ),
          ),
        ),
      ],
    ),
  );
}
