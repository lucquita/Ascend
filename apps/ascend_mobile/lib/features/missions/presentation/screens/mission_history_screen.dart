import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Página del historial ya traída.
class MissionHistoryState {
  /// Crea el estado.
  const MissionHistoryState({
    this.missions = const <Mission>[],
    this.cursor,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.failure,
  });

  /// Misiones traídas hasta ahora.
  final List<Mission> missions;

  /// Cursor de la última página.
  final Object? cursor;

  /// `true` si quedan más.
  final bool hasMore;

  /// `true` mientras se trae la página siguiente.
  final bool isLoadingMore;

  /// Fallo de la última operación.
  final Failure? failure;

  /// Copia cambiando lo indicado.
  MissionHistoryState copyWith({
    List<Mission>? missions,
    Object? cursor,
    bool? hasMore,
    bool? isLoadingMore,
    Failure? failure,
    bool clearFailure = false,
  }) => MissionHistoryState(
    missions: missions ?? this.missions,
    cursor: cursor ?? this.cursor,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

/// Historial paginado de misiones terminadas.
class MissionHistoryController extends AsyncNotifier<MissionHistoryState> {
  @override
  Future<MissionHistoryState> build() async {
    final uid = ref.watch(authStateProvider).value?.uid;
    if (uid == null) {
      return const MissionHistoryState(
        failure: AuthFailure(
          messageKey: 'failure.auth.sessionExpired',
          code: 'no-session',
        ),
      );
    }

    final result = await ref
        .read(missionRepositoryProvider)
        .getHistory(uid: uid);

    // Nunca lanza: una excepción dentro de `build()` deja el provider en
    // `AsyncLoading` para siempre y la pantalla cargando sin fin.
    return result.fold(
      onSuccess: (Paginated<Mission> page) => MissionHistoryState(
        missions: page.items,
        cursor: page.cursor,
        hasMore: page.hasMore,
      ),
      onFailure: (Failure failure) => MissionHistoryState(failure: failure),
    );
  }

  /// Trae la página siguiente y la suma a la lista.
  Future<void> loadMore() async {
    final current = state.value;
    final uid = ref.read(authStateProvider).value?.uid;
    if (current == null || uid == null || !current.hasMore) {
      return;
    }
    if (current.isLoadingMore) {
      return;
    }

    state = AsyncData<MissionHistoryState>(
      current.copyWith(isLoadingMore: true, clearFailure: true),
    );

    final result = await ref
        .read(missionRepositoryProvider)
        .getHistory(uid: uid, cursor: current.cursor);

    state = AsyncData<MissionHistoryState>(
      result.fold(
        onSuccess: (Paginated<Mission> page) => current.copyWith(
          missions: <Mission>[...current.missions, ...page.items],
          cursor: page.cursor,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
        // El fallo no borra lo ya traído: perder la página que se estaba
        // leyendo por no poder traer la siguiente sería peor que el error.
        onFailure: (Failure failure) =>
            current.copyWith(isLoadingMore: false, failure: failure),
      ),
    );
  }
}

/// Controlador del historial.
final AsyncNotifierProvider<MissionHistoryController, MissionHistoryState>
missionHistoryControllerProvider =
    AsyncNotifierProvider<MissionHistoryController, MissionHistoryState>(
      MissionHistoryController.new,
      name: 'missionHistory',
    );

/// Historial de misiones terminadas.
///
/// Se pagina con cursor y no con `offset`: Firestore no tiene `offset` real
/// —lo simula leyendo y descartando, y cobra igual las lecturas descartadas—,
/// así que la página diez costaría diez páginas.
class MissionHistoryScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const MissionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(missionHistoryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: AsyncStateBuilder<MissionHistoryState>(
        value: state,
        onRetry: () => ref.invalidate(missionHistoryControllerProvider),
        data: (MissionHistoryState value) {
          if (value.missions.isEmpty) {
            return value.failure != null
                ? ErrorStateView(
                    failure: value.failure!,
                    onRetry: () =>
                        ref.invalidate(missionHistoryControllerProvider),
                  )
                : const EmptyStateView(
                    title: 'Todavía no terminaste ninguna',
                    message:
                        'Acá va a quedar registro de cada misión que completes.',
                    icon: Icons.history_rounded,
                  );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AscendSpacing.lg),
            // Un elemento extra al final para el botón o el error.
            itemCount: value.missions.length + 1,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AscendSpacing.sm),
            itemBuilder: (BuildContext context, int index) {
              if (index < value.missions.length) {
                return _HistoryTile(mission: value.missions[index]);
              }
              return _Footer(state: value);
            },
          );
        },
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state});

  final MissionHistoryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(top: AscendSpacing.md),
    child: Column(
      children: <Widget>[
        if (state.failure != null) ...<Widget>[
          ErrorStateView(failure: state.failure!, compact: true),
          const SizedBox(height: AscendSpacing.md),
        ],
        if (state.hasMore)
          AscendButton.secondary(
            label: 'Cargar más',
            isLoading: state.isLoadingMore,
            onPressed: state.isLoadingMore
                ? null
                : () => ref
                      .read(missionHistoryControllerProvider.notifier)
                      .loadMore(),
          )
        else
          Text(
            'Eso es todo.',
            style: context.texts.bodySmall?.copyWith(
              color: context.ascend.textSecondary,
            ),
          ),
      ],
    ),
  );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final completed = mission.status == MissionStatus.completed;

    return Container(
      padding: const EdgeInsets.all(AscendSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AscendRadius.md),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            completed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: completed
                ? context.ascend.success
                : context.ascend.textSecondary,
          ),
          const SizedBox(width: AscendSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(mission.title, style: context.texts.bodyMedium),
                if (mission.goalTitle != null)
                  Text(
                    mission.goalTitle!,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.ascend.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              // El Aura solo aparece si se otorgó: mostrar "+0" en una misión
              // salteada parecería un castigo.
              if (completed && mission.auraReward > 0)
                Text(
                  '+${mission.auraReward}',
                  style: context.texts.labelMedium?.copyWith(
                    color: context.ascend.auraOnSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (mission.completedAt != null)
                Text(
                  AscendDateUtils.relativeLabel(mission.completedAt!),
                  style: context.texts.labelSmall?.copyWith(
                    color: context.ascend.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
