import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Filtro activo en la lista de objetivos.
@immutable
class GoalsFilter {
  /// Crea un filtro.
  const GoalsFilter({this.status, this.categoryId});

  /// Sin filtrar.
  static const GoalsFilter none = GoalsFilter();

  /// Estado por el que se filtra, o `null` para todos.
  final GoalStatus? status;

  /// Categoría por la que se filtra, o `null` para todas.
  final String? categoryId;

  /// `true` si hay algún filtro puesto.
  bool get isActive => status != null || categoryId != null;

  /// Copia cambiando el estado. Pasar `null` lo quita.
  GoalsFilter withStatus(GoalStatus? value) =>
      GoalsFilter(status: value, categoryId: categoryId);

  /// Copia cambiando la categoría. Pasar `null` la quita.
  GoalsFilter withCategory(String? value) =>
      GoalsFilter(status: status, categoryId: value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalsFilter &&
          other.status == status &&
          other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(status, categoryId);
}

/// Mantiene el filtro de la lista.
///
/// Es un `Notifier` y no un `StateProvider` porque la API de mutación es
/// acotada: quitar y poner filtros, nada más. Exponer un `state` escribible
/// invitaría a que cualquier widget lo pisara entero.
class GoalsFilterController extends Notifier<GoalsFilter> {
  @override
  GoalsFilter build() => GoalsFilter.none;

  /// Filtra por estado. `null` quita el filtro.
  void setStatus(GoalStatus? status) => state = state.withStatus(status);

  /// Filtra por categoría. `null` quita el filtro.
  void setCategory(String? categoryId) =>
      state = state.withCategory(categoryId);

  /// Vuelve a "sin filtros".
  void clear() => state = GoalsFilter.none;
}

/// Filtro activo de la lista de objetivos.
final NotifierProvider<GoalsFilterController, GoalsFilter> goalsFilterProvider =
    NotifierProvider<GoalsFilterController, GoalsFilter>(
      GoalsFilterController.new,
      name: 'goalsFilter',
    );

/// Lista de objetivos en vivo, ya filtrada.
///
/// Depende del filtro además de la sesión: cambiar un filtro reabre la
/// suscripción con la consulta nueva, y Riverpod cierra la anterior sola.
final StreamProvider<Result<List<Goal>>> goalsProvider =
    StreamProvider<Result<List<Goal>>>((ref) {
      final uid = ref.watch(currentUserProvider)?.uid;
      if (uid == null) {
        // Sin sesión se emite un fallo tipado, NO un stream vacío. Un
        // `Stream.empty()` se cierra sin emitir y deja el provider en
        // `AsyncLoading` para siempre: la pantalla se quedaría con el skeleton
        // girando sin explicar nada. Quedarse cargando indefinidamente es
        // justamente el modo de fallo que no puede existir en Ascend.
        return Stream<Result<List<Goal>>>.value(_noSession<List<Goal>>());
      }

      final filter = ref.watch(goalsFilterProvider);
      return ref
          .watch(watchGoalsUseCaseProvider)
          .call(uid: uid, status: filter.status, categoryId: filter.categoryId);
    }, name: 'goals');

/// Un objetivo concreto, en vivo.
// Sin anotación de tipo explícita a propósito: `StreamProviderFamily` no está
// exportado por `flutter_riverpod`, así que el tipo solo se puede inferir.
final goalDetailProvider = StreamProvider.family<Result<Goal>, String>((
  ref,
  goalId,
) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) {
    return Stream<Result<Goal>>.value(_noSession<Goal>());
  }
  return ref.watch(watchGoalUseCaseProvider).call(uid: uid, goalId: goalId);
}, name: 'goalDetail');

/// Fallo que se emite cuando se pide un dato sin sesión activa.
///
/// Existe para que ningún provider de esta feature devuelva un stream vacío:
/// un stream que se cierra sin emitir deja la pantalla cargando para siempre.
// Sin `const`: Dart no admite un parámetro de tipo como argumento de tipo en
// una expresión constante.
Result<T> _noSession<T>() => Failed<T>(_sessionExpired);

const AuthFailure _sessionExpired = AuthFailure(
  messageKey: 'failure.auth.sessionExpired',
  code: 'no-session',
);

/// Orquesta las escrituras sobre objetivos y expone su estado a las pantallas.
///
/// Las pantallas no llaman a repositorios: llaman acá. Toda la secuencia
/// —validar, ejecutar, traducir el fallo— vive en esta capa, así el widget se
/// limita a pintar `loading`, `error` o `data`.
class GoalController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  String? get _uid => ref.read(currentUserProvider)?.uid;

  /// Crea un objetivo. Devuelve su id si salió bien.
  Future<String?> create({
    required String title,
    required String categoryId,
    String? description,
    MissionDifficulty difficulty = MissionDifficulty.medium,
    List<Milestone> milestones = const <Milestone>[],
    DateTime? startDate,
    DateTime? targetDate,
  }) async {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return null;
    }

    state = const AsyncLoading<void>();
    final result = await guardResult(
      () => ref
          .read(createGoalUseCaseProvider)
          .call(
            uid: uid,
            title: title,
            categoryId: categoryId,
            description: description,
            difficulty: difficulty,
            milestones: milestones,
            startDate: startDate,
            targetDate: targetDate,
          ),
    );

    return result.fold(
      onSuccess: (goal) {
        state = const AsyncData<void>(null);
        return goal.id;
      },
      onFailure: (failure) {
        _reportFailure(failure);
        return null;
      },
    );
  }

  /// Guarda los cambios de un objetivo.
  Future<bool> update(Goal goal) =>
      _run(() => ref.read(updateGoalUseCaseProvider).call(goal));

  /// Cambia el estado de un objetivo.
  Future<bool> changeStatus({
    required String goalId,
    required GoalStatus from,
    required GoalStatus to,
  }) {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return Future<bool>.value(false);
    }
    return _run(
      () => ref
          .read(changeGoalStatusUseCaseProvider)
          .call(uid: uid, goalId: goalId, from: from, to: to),
    );
  }

  /// Elimina un objetivo.
  Future<bool> delete(String goalId) {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return Future<bool>.value(false);
    }
    return _run(
      () => ref.read(deleteGoalUseCaseProvider).call(uid: uid, goalId: goalId),
    );
  }

  /// Marca o desmarca un hito.
  Future<bool> toggleMilestone({
    required String goalId,
    required String milestoneId,
    required bool done,
  }) {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return Future<bool>.value(false);
    }
    return _run(
      () => ref
          .read(toggleMilestoneUseCaseProvider)
          .call(uid: uid, goalId: goalId, milestoneId: milestoneId, done: done),
    );
  }

  /// Descarta el error mostrado.
  ///
  /// Lo llama el formulario al editar un campo: dejar colgado el error de la
  /// operación anterior mientras alguien corrige los datos es confuso.
  void clearError() {
    if (state.hasError) {
      state = const AsyncData<void>(null);
    }
  }

  /// Ejecuta una acción y traduce su `Result` al `AsyncValue` de la pantalla.
  ///
  /// Nunca lanza: un `Failed` se convierte en `AsyncError` con el `Failure`
  /// dentro, que es lo que `ErrorStateView` sabe traducir.
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

  /// La sesión se cayó entre que se abrió la pantalla y se tocó el botón.
  ///
  /// Se informa como fallo tipado en lugar de quedarse en silencio: sin esto la
  /// pantalla se quedaría en carga para siempre, que es exactamente lo que no
  /// puede pasar.
  void _reportNoSession() => _reportFailure(
    const AuthFailure(
      messageKey: 'failure.auth.sessionExpired',
      code: 'no-session',
    ),
  );
}

/// Controlador de las escrituras sobre objetivos.
final NotifierProvider<GoalController, AsyncValue<void>>
goalControllerProvider = NotifierProvider<GoalController, AsyncValue<void>>(
  GoalController.new,
  name: 'goalController',
);
