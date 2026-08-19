import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Misiones del día, en vivo. Alimenta la pantalla "Hoy".
final StreamProvider<Result<List<Mission>>> todayMissionsProvider =
    StreamProvider<Result<List<Mission>>>((ref) {
      final uid = ref.watch(currentUserProvider)?.uid;
      if (uid == null) {
        // Un fallo tipado y no un stream vacío: un stream que se cierra sin
        // emitir dejaría la pantalla cargando para siempre.
        return Stream<Result<List<Mission>>>.value(_noSession<List<Mission>>());
      }
      return ref.watch(watchTodayMissionsUseCaseProvider).call(uid: uid);
    }, name: 'todayMissions');

/// Misiones de un objetivo concreto, en vivo.
// Sin anotación de tipo explícita: `StreamProviderFamily` no está exportado por
// `flutter_riverpod`, así que el tipo solo se puede inferir.
final missionsByGoalProvider =
    StreamProvider.family<Result<List<Mission>>, String>((ref, goalId) {
      final uid = ref.watch(currentUserProvider)?.uid;
      if (uid == null) {
        return Stream<Result<List<Mission>>>.value(_noSession<List<Mission>>());
      }
      return ref
          .watch(watchMissionsByGoalUseCaseProvider)
          .call(uid: uid, goalId: goalId);
    }, name: 'missionsByGoal');

/// Resumen del avance del día, derivado de las misiones.
///
/// Va aparte para que la cabecera de "Hoy" no tenga que recalcularlo en cada
/// rebuild ni duplicar la lógica que ya vive en el dominio.
final Provider<DailyProgress> dailyProgressProvider = Provider<DailyProgress>((
  ref,
) {
  final missions = ref.watch(todayMissionsProvider).value?.valueOrNull;
  return DailyProgress.from(missions ?? const <Mission>[]);
}, name: 'dailyProgress');

/// Orquesta las escrituras sobre misiones.
class MissionController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  String? get _uid => ref.read(currentUserProvider)?.uid;

  /// Crea una misión dentro de un objetivo.
  Future<String?> create({
    required Goal goal,
    required String title,
    String? description,
    MissionDifficulty difficulty = MissionDifficulty.medium,
    MissionBudget budget = MissionBudget.free,
    int? estimatedMinutes,
    DateTime? dueDate,
    bool requiresEvidence = false,
    int order = 0,
  }) async {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return null;
    }

    state = const AsyncLoading<void>();
    final result = await guardResult(
      () => ref
          .read(createMissionUseCaseProvider)
          .call(
            uid: uid,
            goal: goal,
            title: title,
            description: description,
            difficulty: difficulty,
            budget: budget,
            estimatedMinutes: estimatedMinutes,
            dueDate: dueDate,
            requiresEvidence: requiresEvidence,
            order: order,
          ),
    );

    return result.fold(
      onSuccess: (mission) {
        state = const AsyncData<void>(null);
        return mission.id;
      },
      onFailure: (failure) {
        _reportFailure(failure);
        return null;
      },
    );
  }

  /// Guarda los cambios de una misión.
  Future<bool> update(Mission mission) =>
      _run(() => ref.read(updateMissionUseCaseProvider).call(mission));

  /// Marca una misión como completada.
  ///
  /// El cliente solo cambia el estado: el Aura la otorga el servidor (ADR-003).
  Future<bool> complete(Mission mission, {Evidence? evidence}) {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return Future<bool>.value(false);
    }
    return _run(
      () => ref
          .read(completeMissionUseCaseProvider)
          .call(uid: uid, mission: mission, evidence: evidence),
    );
  }

  /// Saltea una misión.
  Future<bool> skip(Mission mission) {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return Future<bool>.value(false);
    }
    return _run(
      () =>
          ref.read(skipMissionUseCaseProvider).call(uid: uid, mission: mission),
    );
  }

  /// Reordena las misiones de una lista.
  Future<bool> reorder(List<String> orderedIds) {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return Future<bool>.value(false);
    }
    return _run(
      () => ref
          .read(reorderMissionsUseCaseProvider)
          .call(uid: uid, orderedIds: orderedIds),
    );
  }

  /// Elimina una misión.
  Future<bool> delete(String missionId) {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return Future<bool>.value(false);
    }
    return _run(
      () => ref
          .read(deleteMissionUseCaseProvider)
          .call(uid: uid, missionId: missionId),
    );
  }

  /// Descarta el error mostrado.
  void clearError() {
    if (state.hasError) {
      state = const AsyncData<void>(null);
    }
  }

  Future<bool> _run(Future<Result<void>> Function() action) async {
    state = const AsyncLoading<void>();
    final result = await guardResult(action);
    return result.fold(
      onSuccess: (_) {
        state = const AsyncData<void>(null);
        return true;
      },
      onFailure: (failure) {
        _reportFailure(failure);
        return false;
      },
    );
  }

  void _reportFailure(Failure failure) {
    state = AsyncError<void>(failure, failure.stackTrace ?? StackTrace.empty);
  }

  void _reportNoSession() => _reportFailure(_sessionExpired);
}

/// Controlador de las escrituras sobre misiones.
final NotifierProvider<MissionController, AsyncValue<void>>
missionControllerProvider =
    NotifierProvider<MissionController, AsyncValue<void>>(
      MissionController.new,
      name: 'missionController',
    );

// Sin `const`: Dart no admite un parámetro de tipo como argumento de tipo en
// una expresión constante.
Result<T> _noSession<T>() => Failed<T>(_sessionExpired);

const AuthFailure _sessionExpired = AuthFailure(
  messageKey: 'failure.auth.sessionExpired',
  code: 'no-session',
);
