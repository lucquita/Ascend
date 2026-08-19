import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/missions/application/missions_controller.dart';
import 'package:ascend_mobile/features/missions/presentation/widgets/mission_widgets.dart';
import 'package:ascend_mobile/features/notifications/presentation/widgets/notification_bell.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Pantalla "Hoy": las misiones del día, de todos los objetivos.
///
/// Se resuelve en **una sola consulta** (ADR-005): las misiones viven en una
/// colección plana bajo el usuario con `goalId` indexado, precisamente para que
/// esta pantalla no necesite un `collectionGroup` ni N lecturas.
class TodayScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missions = ref.watch(todayMissionsProvider);
    final progress = ref.watch(dailyProgressProvider);
    final action = ref.watch(missionControllerProvider);
    final failure = action.error is Failure ? action.error! as Failure : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoy'),
        actions: <Widget>[
          const NotificationBell(),
          IconButton(
            onPressed: () => context.push(Routes.missionHistory),
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Historial',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          DailyProgressHeader(progress: progress),
          if (failure != null) ErrorStateView(failure: failure, compact: true),
          Expanded(
            child: AsyncStateBuilder<Result<List<Mission>>>(
              value: missions,
              onRetry: () => ref.invalidate(todayMissionsProvider),
              isEmpty: (result) => result.valueOrNull?.isEmpty ?? false,
              emptyState: EmptyStateConfig(
                icon: Icons.wb_sunny_outlined,
                title: 'Nada para hoy',
                message:
                    'No tenés misiones agendadas. Entrá a un objetivo y '
                    'agregá la próxima acción concreta.',
                actionLabel: 'Ver mis objetivos',
                onAction: () => context.go(Routes.goals),
              ),
              data: (Result<List<Mission>> result) => result.fold<Widget>(
                onSuccess: (List<Mission> items) => _TodayList(missions: items),
                onFailure: (Failure f) => ErrorStateView(
                  failure: f,
                  onRetry: () => ref.invalidate(todayMissionsProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista del día agrupada por objetivo.
class _TodayList extends ConsumerWidget {
  const _TodayList({required this.missions});

  final List<Mission> missions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Agrupar hace legible una lista larga: "3 de Aprender inglés, 2 de Correr
    // 5k" se entiende de un vistazo; veinte filas sueltas, no.
    final grouped = groupMissionsByGoal(missions);
    final isBusy = ref.watch(missionControllerProvider).isLoading;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AscendSpacing.lg,
        0,
        AscendSpacing.lg,
        AscendSpacing.xxl,
      ),
      children: <Widget>[
        for (final entry in grouped.entries) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(
              top: AscendSpacing.md,
              bottom: AscendSpacing.sm,
            ),
            child: Text(
              entry.value.first.goalTitle ?? 'Sin objetivo',
              style: context.texts.labelLarge?.copyWith(
                color: context.ascend.textSecondary,
              ),
            ),
          ),
          for (final mission in entry.value)
            MissionTile(
              mission: mission,
              enabled: !isBusy,
              onTap: () => context.push(Routes.missionDetail(mission.id)),
              onToggle: () => ref
                  .read(missionControllerProvider.notifier)
                  .complete(mission),
            ),
        ],
      ],
    );
  }
}
