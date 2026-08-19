/// Casos de uso de objetivos.
///
/// La validación vive acá y no en el widget: la misma regla tiene que aplicar
/// venga de la pantalla de alta, del asistente con IA o de un test. Y se repite
/// en las reglas de Firestore, porque validar solo en el cliente no es validar.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/category.dart';
import 'package:ascend_domain/src/entities/goal.dart';
import 'package:ascend_domain/src/enums/enums.dart';
import 'package:ascend_domain/src/repositories/repositories.dart';

/// Longitud máxima de la descripción de un objetivo.
const int kMaxGoalDescriptionLength = 500;

/// Cantidad máxima de hitos embebidos en un objetivo.
///
/// Van dentro del documento, así que crecer sin límite haría cara cada lectura
/// de la lista. Ocho es el techo que fija el diseño para que sigan siendo
/// "pocos y siempre leídos con el objetivo".
const int kMaxMilestones = 8;

/// Observa los objetivos de una persona.
class WatchGoalsUseCase {
  /// Crea el caso de uso.
  const WatchGoalsUseCase(this._goals);

  final GoalRepository _goals;

  /// Emite la lista cada vez que cambia.
  Stream<Result<List<Goal>>> call({
    required String uid,
    GoalStatus? status,
    String? categoryId,
  }) => _goals.watchGoals(uid: uid, status: status, categoryId: categoryId);
}

/// Observa un objetivo concreto.
class WatchGoalUseCase {
  /// Crea el caso de uso.
  const WatchGoalUseCase(this._goals);

  final GoalRepository _goals;

  /// Emite el objetivo cada vez que cambia.
  Stream<Result<Goal>> call({required String uid, required String goalId}) =>
      _goals.watchGoal(uid: uid, goalId: goalId);
}

/// Crea un objetivo.
class CreateGoalUseCase {
  /// Crea el caso de uso.
  const CreateGoalUseCase(this._goals);

  final GoalRepository _goals;

  /// Valida y da de alta el objetivo.
  ///
  /// El id se genera en el cliente para que la escritura sea idempotente: si se
  /// corta la red y se reintenta, se sobrescribe el mismo documento en lugar de
  /// crear dos objetivos iguales.
  Future<Result<Goal>> call({
    required String uid,
    required String title,
    required String categoryId,
    String? description,
    GoalStatus status = GoalStatus.active,
    MissionDifficulty difficulty = MissionDifficulty.medium,
    List<Milestone> milestones = const <Milestone>[],
    String? icon,
    String? colorHex,
    DateTime? startDate,
    DateTime? targetDate,
    DateTime? now,
  }) async {
    final validation = _validateGoalInput(
      title: title,
      categoryId: categoryId,
      description: description,
      milestones: milestones,
      startDate: startDate,
      targetDate: targetDate,
    );
    if (validation case Failed<_GoalInput>(:final failure)) {
      return Failed<Goal>(failure);
    }
    final input = validation.valueOrNull!;

    final goal = Goal(
      id: IdGenerator.generate(),
      ownerId: uid,
      title: input.title,
      categoryId: input.categoryId,
      createdAt: (now ?? DateTime.now()).toUtc(),
      description: input.description,
      status: status,
      difficulty: difficulty,
      milestones: input.milestones,
      icon: icon,
      colorHex: colorHex,
      startDate: startDate,
      targetDate: targetDate,
    );

    return _goals.createGoal(goal);
  }
}

/// Edita un objetivo existente.
class UpdateGoalUseCase {
  /// Crea el caso de uso.
  const UpdateGoalUseCase(this._goals);

  final GoalRepository _goals;

  /// Valida y guarda los cambios.
  ///
  /// Recibe el objetivo completo y no campos sueltos porque la pantalla de
  /// edición ya trabaja sobre una copia: así la validación ve el estado final
  /// —por ejemplo, que la fecha objetivo siga siendo posterior a la de inicio—
  /// y no solo el campo que se tocó.
  Future<Result<void>> call(Goal goal) async {
    if (!goal.status.isEditable) {
      // Un objetivo terminado o archivado no se edita: cambiarle el título
      // después de completarlo reescribe la historia que ya vio la comunidad.
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.goal.notEditable',
          field: 'status',
        ),
      );
    }

    final validation = _validateGoalInput(
      title: goal.title,
      categoryId: goal.categoryId,
      description: goal.description,
      milestones: goal.milestones,
      startDate: goal.startDate,
      targetDate: goal.targetDate,
    );
    if (validation case Failed<_GoalInput>(:final failure)) {
      return Failed<void>(failure);
    }
    final input = validation.valueOrNull!;

    return _goals.updateGoal(
      goal.copyWith(
        title: input.title,
        description: input.description,
        categoryId: input.categoryId,
        milestones: input.milestones,
      ),
    );
  }
}

/// Cambia el estado de un objetivo.
class ChangeGoalStatusUseCase {
  /// Crea el caso de uso.
  const ChangeGoalStatusUseCase(this._goals);

  final GoalRepository _goals;

  /// Aplica la transición si es válida.
  ///
  /// No toda transición tiene sentido: reactivar algo archivado sí, "completar"
  /// algo ya completado no. Modelarlo acá evita que cada pantalla invente sus
  /// propias reglas.
  Future<Result<void>> call({
    required String uid,
    required String goalId,
    required GoalStatus from,
    required GoalStatus to,
  }) async {
    if (from == to) {
      // No es un error: la pantalla pidió algo que ya está hecho. Se evita la
      // escritura en lugar de fallar.
      return const Success<void>(null);
    }
    if (!_isAllowedTransition(from, to)) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.goal.invalidTransition',
          field: 'status',
        ),
      );
    }
    return _goals.updateStatus(uid: uid, goalId: goalId, status: to);
  }

  static bool _isAllowedTransition(GoalStatus from, GoalStatus to) =>
      switch ((from, to)) {
        // Desde borrador solo se arranca o se descarta.
        (GoalStatus.draft, GoalStatus.active) => true,
        (GoalStatus.draft, GoalStatus.archived) => true,
        // Un objetivo en curso se pausa, se termina o se archiva.
        (GoalStatus.active, GoalStatus.paused) => true,
        (GoalStatus.active, GoalStatus.completed) => true,
        (GoalStatus.active, GoalStatus.archived) => true,
        // Uno pausado se retoma o se archiva, pero no se completa de un salto:
        // completar sin volver a activarlo saltearía el trabajo real.
        (GoalStatus.paused, GoalStatus.active) => true,
        (GoalStatus.paused, GoalStatus.archived) => true,
        // Lo terminado se archiva; no se "descompleta", porque el Aura ya se
        // otorgó y revertirla es una operación de servidor, no de pantalla.
        (GoalStatus.completed, GoalStatus.archived) => true,
        // Lo archivado se puede recuperar.
        (GoalStatus.archived, GoalStatus.active) => true,
        _ => false,
      };
}

/// Elimina un objetivo.
class DeleteGoalUseCase {
  /// Crea el caso de uso.
  const DeleteGoalUseCase(this._goals);

  final GoalRepository _goals;

  /// Borra el objetivo. Sus misiones las borra en cascada el servidor.
  Future<Result<void>> call({required String uid, required String goalId}) =>
      _goals.deleteGoal(uid: uid, goalId: goalId);
}

/// Marca o desmarca un hito.
class ToggleMilestoneUseCase {
  /// Crea el caso de uso.
  const ToggleMilestoneUseCase(this._goals);

  final GoalRepository _goals;

  /// Cambia el estado de un hito del objetivo.
  Future<Result<void>> call({
    required String uid,
    required String goalId,
    required String milestoneId,
    required bool done,
  }) => _goals.toggleMilestone(
    uid: uid,
    goalId: goalId,
    milestoneId: milestoneId,
    done: done,
  );
}

/// Observa el catálogo de categorías.
class WatchCategoriesUseCase {
  /// Crea el caso de uso.
  const WatchCategoriesUseCase(this._categories);

  final CategoryRepository _categories;

  /// Emite las categorías, por defecto solo las activas.
  Stream<Result<List<Category>>> call({bool onlyActive = true}) =>
      _categories.watchCategories(onlyActive: onlyActive);
}

/// Entrada ya validada y normalizada de un objetivo.
class _GoalInput {
  const _GoalInput({
    required this.title,
    required this.categoryId,
    required this.milestones,
    this.description,
  });

  final String title;
  final String categoryId;
  final List<Milestone> milestones;
  final String? description;
}

/// Validación compartida por el alta y la edición.
///
/// Está factorizada a propósito: si la edición validara distinto que el alta,
/// se podría guardar por edición un objetivo que el alta habría rechazado.
Result<_GoalInput> _validateGoalInput({
  required String title,
  required String categoryId,
  required List<Milestone> milestones,
  String? description,
  DateTime? startDate,
  DateTime? targetDate,
}) {
  final validTitle = Validators.requiredText(
    title,
    field: 'title',
    maxLength: Validators.maxTitleLength,
  );
  if (validTitle case Failed<String>(:final failure)) {
    return Failed<_GoalInput>(failure);
  }

  if (categoryId.trim().isEmpty) {
    return const Failed<_GoalInput>(
      ValidationFailure(
        messageKey: 'validation.category.required',
        field: 'categoryId',
      ),
    );
  }

  String? cleanDescription;
  if (description != null) {
    final trimmed = description.trim();
    if (trimmed.length > kMaxGoalDescriptionLength) {
      return const Failed<_GoalInput>(
        ValidationFailure(
          messageKey: 'validation.description.tooLong',
          field: 'description',
        ),
      );
    }
    cleanDescription = trimmed.isEmpty ? null : trimmed;
  }

  if (milestones.length > kMaxMilestones) {
    return const Failed<_GoalInput>(
      ValidationFailure(
        messageKey: 'validation.milestones.tooMany',
        field: 'milestones',
      ),
    );
  }

  // Una fecha objetivo anterior al inicio deja el objetivo vencido desde el
  // primer día y rompe cualquier cálculo de días restantes.
  if (startDate != null &&
      targetDate != null &&
      targetDate.isBefore(startDate)) {
    return const Failed<_GoalInput>(
      ValidationFailure(
        messageKey: 'validation.targetDate.beforeStart',
        field: 'targetDate',
      ),
    );
  }

  return Success<_GoalInput>(
    _GoalInput(
      title: validTitle.valueOrNull!,
      categoryId: categoryId.trim(),
      milestones: List<Milestone>.unmodifiable(milestones),
      description: cleanDescription,
    ),
  );
}
