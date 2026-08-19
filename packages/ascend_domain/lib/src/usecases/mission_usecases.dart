/// Casos de uso de misiones.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/category.dart';
import 'package:ascend_domain/src/entities/goal.dart';
import 'package:ascend_domain/src/entities/mission.dart';
import 'package:ascend_domain/src/enums/enums.dart';
import 'package:ascend_domain/src/repositories/repositories.dart';

/// Longitud máxima de la descripción de una misión.
const int kMaxMissionDescriptionLength = 300;

/// Duración máxima admitida, en minutos (8 horas).
///
/// Una "misión" de más de una jornada no es una acción concreta: es otro
/// objetivo disfrazado, y conviene decirlo en vez de dejar que alguien cree una
/// tarea que nunca va a completar.
const int kMaxEstimatedMinutes = 480;

/// Observa las misiones del día. Es la consulta más usada de la app.
class WatchTodayMissionsUseCase {
  /// Crea el caso de uso.
  const WatchTodayMissionsUseCase(this._missions);

  final MissionRepository _missions;

  /// Emite las misiones pendientes que vencen hoy o antes.
  Stream<Result<List<Mission>>> call({required String uid, DateTime? day}) =>
      _missions.watchToday(uid: uid, day: day);
}

/// Observa las misiones de un objetivo.
class WatchMissionsByGoalUseCase {
  /// Crea el caso de uso.
  const WatchMissionsByGoalUseCase(this._missions);

  final MissionRepository _missions;

  /// Emite las misiones del objetivo en su orden manual.
  Stream<Result<List<Mission>>> call({
    required String uid,
    required String goalId,
  }) => _missions.watchByGoal(uid: uid, goalId: goalId);
}

/// Observa misiones con filtros combinados.
class WatchMissionsUseCase {
  /// Crea el caso de uso.
  const WatchMissionsUseCase(this._missions);

  final MissionRepository _missions;

  /// Emite las misiones que cumplen todos los filtros.
  Stream<Result<List<Mission>>> call({
    required String uid,
    MissionStatus? status,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    String? categoryId,
    String? goalId,
  }) => _missions.watchMissions(
    uid: uid,
    status: status,
    difficulty: difficulty,
    budget: budget,
    categoryId: categoryId,
    goalId: goalId,
  );
}

/// Crea una misión dentro de un objetivo.
class CreateMissionUseCase {
  /// Crea el caso de uso.
  const CreateMissionUseCase(this._missions);

  final MissionRepository _missions;

  /// Valida y da de alta la misión.
  ///
  /// Recibe el [goal] completo y no solo su id porque la misión guarda
  /// `goalTitle` y `categoryId` desnormalizados: la pantalla "Hoy" los muestra
  /// y sin ellos costaría una lectura extra por misión.
  Future<Result<Mission>> call({
    required String uid,
    required Goal goal,
    required String title,
    String? description,
    MissionDifficulty difficulty = MissionDifficulty.medium,
    MissionBudget budget = MissionBudget.free,
    int? estimatedMinutes,
    DateTime? dueDate,
    Recurrence? recurrence,
    bool requiresEvidence = false,
    int order = 0,
    DateTime? now,
  }) async {
    if (!goal.status.isEditable) {
      // Agregar trabajo a un objetivo terminado o archivado no tiene sentido:
      // o se reactiva, o la misión pertenece a otro objetivo.
      return const Failed<Mission>(
        ValidationFailure(
          messageKey: 'validation.mission.goalNotEditable',
          field: 'goalId',
        ),
      );
    }

    final validation = _validateMissionInput(
      title: title,
      description: description,
      estimatedMinutes: estimatedMinutes,
    );
    if (validation case Failed<_MissionInput>(:final failure)) {
      return Failed<Mission>(failure);
    }
    final input = validation.valueOrNull!;

    final mission = Mission(
      // Id de cliente: la escritura es idempotente y un reintento offline
      // sobrescribe en vez de duplicar.
      id: IdGenerator.generate(),
      ownerId: uid,
      goalId: goal.id,
      title: input.title,
      createdAt: (now ?? DateTime.now()).toUtc(),
      goalTitle: goal.title,
      categoryId: goal.categoryId,
      description: input.description,
      difficulty: difficulty,
      budget: budget,
      estimatedMinutes: estimatedMinutes,
      dueDate: dueDate,
      scheduledFor: dueDate == null ? null : AscendDateUtils.toDayKey(dueDate),
      recurrence: recurrence,
      order: order,
      requiresEvidence: requiresEvidence,
    );

    return _missions.createMission(mission);
  }
}

/// Edita una misión existente.
class UpdateMissionUseCase {
  /// Crea el caso de uso.
  const UpdateMissionUseCase(this._missions);

  final MissionRepository _missions;

  /// Valida y guarda los cambios.
  Future<Result<void>> call(Mission mission) async {
    if (mission.status.isCompleted) {
      // Editar una misión ya completada reescribiría el logro por el que ya se
      // otorgó Aura y que puede estar publicado en la comunidad.
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.mission.completedNotEditable',
          field: 'status',
        ),
      );
    }

    final validation = _validateMissionInput(
      title: mission.title,
      description: mission.description,
      estimatedMinutes: mission.estimatedMinutes,
    );
    if (validation case Failed<_MissionInput>(:final failure)) {
      return Failed<void>(failure);
    }
    final input = validation.valueOrNull!;

    return _missions.updateMission(
      mission.copyWith(title: input.title, description: input.description),
    );
  }
}

/// Marca una misión como completada.
class CompleteMissionUseCase {
  /// Crea el caso de uso.
  const CompleteMissionUseCase(this._missions);

  final MissionRepository _missions;

  /// Completa la misión, adjuntando evidencia si corresponde.
  ///
  /// El cliente **solo** cambia el estado: el Aura la otorga un trigger del
  /// servidor (ADR-003). La comprobación de `canComplete` la repite el
  /// repositorio contra el documento real, porque lo que la pantalla tiene en
  /// memoria puede estar desactualizado.
  Future<Result<void>> call({
    required String uid,
    required Mission mission,
    Evidence? evidence,
  }) async {
    final candidate = evidence == null
        ? mission
        : mission.copyWith(evidence: evidence);

    if (!candidate.canComplete) {
      return Failed<void>(
        ValidationFailure(
          messageKey: mission.status.isCompleted
              ? 'validation.mission.alreadyCompleted'
              : 'validation.mission.evidenceRequired',
          field: 'status',
        ),
      );
    }

    return _missions.completeMission(
      uid: uid,
      missionId: mission.id,
      evidence: evidence,
    );
  }
}

/// Saltea una misión.
class SkipMissionUseCase {
  /// Crea el caso de uso.
  const SkipMissionUseCase(this._missions);

  final MissionRepository _missions;

  /// Marca la misión como salteada.
  Future<Result<void>> call({
    required String uid,
    required Mission mission,
    String? reason,
  }) async {
    if (!mission.status.isOpen) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.mission.notOpen',
          field: 'status',
        ),
      );
    }
    return _missions.skipMission(
      uid: uid,
      missionId: mission.id,
      reason: reason,
    );
  }
}

/// Reordena las misiones de una lista.
class ReorderMissionsUseCase {
  /// Crea el caso de uso.
  const ReorderMissionsUseCase(this._missions);

  final MissionRepository _missions;

  /// Guarda el orden nuevo.
  Future<Result<void>> call({
    required String uid,
    required List<String> orderedIds,
  }) async {
    if (orderedIds.isEmpty) {
      return const Success<void>(null);
    }
    // Un id repetido dejaría dos misiones con la misma posición y un orden no
    // determinista en la lista.
    if (orderedIds.toSet().length != orderedIds.length) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.mission.duplicateOrder',
          field: 'order',
        ),
      );
    }
    return _missions.reorderMissions(uid: uid, orderedIds: orderedIds);
  }
}

/// Elimina una misión.
class DeleteMissionUseCase {
  /// Crea el caso de uso.
  const DeleteMissionUseCase(this._missions);

  final MissionRepository _missions;

  /// Borra la misión.
  Future<Result<void>> call({required String uid, required String missionId}) =>
      _missions.deleteMission(uid: uid, missionId: missionId);
}

/// Historial paginado de misiones completadas.
class GetMissionHistoryUseCase {
  /// Crea el caso de uso.
  const GetMissionHistoryUseCase(this._missions);

  final MissionRepository _missions;

  /// Devuelve una página del historial.
  Future<Result<Paginated<Mission>>> call({
    required String uid,
    Object? cursor,
    int limit = 20,
  }) => _missions.getHistory(uid: uid, cursor: cursor, limit: limit);
}

/// Entrada ya validada y normalizada de una misión.
class _MissionInput {
  const _MissionInput({required this.title, this.description});

  final String title;
  final String? description;
}

/// Validación compartida por el alta y la edición.
///
/// Factorizada a propósito: si la edición validara distinto que el alta, se
/// podría guardar por edición una misión que el alta habría rechazado.
Result<_MissionInput> _validateMissionInput({
  required String title,
  String? description,
  int? estimatedMinutes,
}) {
  final validTitle = Validators.requiredText(
    title,
    field: 'title',
    maxLength: Validators.maxTitleLength,
  );
  if (validTitle case Failed<String>(:final failure)) {
    return Failed<_MissionInput>(failure);
  }

  String? cleanDescription;
  if (description != null) {
    final trimmed = description.trim();
    if (trimmed.length > kMaxMissionDescriptionLength) {
      return const Failed<_MissionInput>(
        ValidationFailure(
          messageKey: 'validation.description.tooLong',
          field: 'description',
        ),
      );
    }
    cleanDescription = trimmed.isEmpty ? null : trimmed;
  }

  if (estimatedMinutes != null &&
      (estimatedMinutes <= 0 || estimatedMinutes > kMaxEstimatedMinutes)) {
    return const Failed<_MissionInput>(
      ValidationFailure(
        messageKey: 'validation.mission.invalidDuration',
        field: 'estimatedMinutes',
      ),
    );
  }

  return Success<_MissionInput>(
    _MissionInput(
      title: validTitle.valueOrNull!,
      description: cleanDescription,
    ),
  );
}

/// Agrupa misiones por objetivo, conservando el orden de entrada.
///
/// Lo usa la pantalla "Hoy": ver "3 de Aprender inglés, 2 de Correr 5k" hace
/// legible una lista larga que si no parece una pila de tareas sueltas.
Map<String, List<Mission>> groupMissionsByGoal(List<Mission> missions) {
  final grouped = <String, List<Mission>>{};
  for (final mission in missions) {
    grouped.putIfAbsent(mission.goalId, () => <Mission>[]).add(mission);
  }
  return Map<String, List<Mission>>.unmodifiable(grouped);
}

/// Resume el avance del día.
///
/// Se calcula en el dominio y no en el widget para poder testearlo sin montar
/// una pantalla.
class DailyProgress {
  /// Crea el resumen.
  const DailyProgress({required this.total, required this.completed});

  /// Calcula el resumen a partir de las misiones del día.
  factory DailyProgress.from(List<Mission> missions) => DailyProgress(
    total: missions.length,
    completed: missions.where((m) => m.status.isCompleted).length,
  );

  /// Misiones del día.
  final int total;

  /// Misiones ya completadas.
  final int completed;

  /// Fracción entre 0.0 y 1.0.
  double get fraction => total <= 0 ? 0 : (completed / total).clamp(0.0, 1.0);

  /// `true` si no queda nada pendiente.
  bool get isDone => total > 0 && completed >= total;

  /// Cuántas faltan.
  int get remaining => (total - completed).clamp(0, total);
}

/// Categoría de una misión resuelta contra el catálogo.
///
/// Devuelve `null` si la categoría ya no existe: un objetivo viejo puede
/// apuntar a una categoría dada de baja, y eso no debe romper la pantalla.
Category? resolveCategory(List<Category> catalog, String? categoryId) {
  if (categoryId == null) {
    return null;
  }
  for (final category in catalog) {
    if (category.id == categoryId) {
      return category;
    }
  }
  return null;
}
