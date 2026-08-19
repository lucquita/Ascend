import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/remote/firestore_goal_datasource.dart';
import 'package:ascend_data/src/datasources/remote/firestore_mission_datasource.dart';
import 'package:ascend_data/src/dtos/goal_dto.dart';
import 'package:ascend_data/src/dtos/mission_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';

/// Implementación de [GoalRepository] sobre Firestore.
///
/// Es la frontera: acá entran excepciones de Firebase y salen `Result`. Ni un
/// solo `throw` cruza hacia el dominio.
class GoalRepositoryImpl implements GoalRepository {
  /// Crea el repositorio.
  const GoalRepositoryImpl({
    required FirestoreGoalDataSource goalDataSource,
    required FirestoreMissionDataSource missionDataSource,
  }) : _goals = goalDataSource,
       _missions = missionDataSource;

  final FirestoreGoalDataSource _goals;
  final FirestoreMissionDataSource _missions;

  @override
  Stream<Result<List<Goal>>> watchGoals({
    required String uid,
    GoalStatus? status,
    String? categoryId,
  }) {
    // `guardStream` emite el fallo sin cerrar la suscripción: si se corta la
    // red, la pantalla muestra el aviso y se recupera sola al volver, en vez de
    // quedarse congelada para siempre.
    return guardStream(
      _goals.watchGoals(uid: uid, status: status, categoryId: categoryId),
    ).map(
      (result) => result.map(
        (snapshot) =>
            snapshot.docs.map(GoalDto.fromFirestore).toList(growable: false),
      ),
    );
  }

  @override
  Stream<Result<Goal>> watchGoal({
    required String uid,
    required String goalId,
  }) {
    return guardStream(_goals.watchGoal(uid: uid, goalId: goalId)).map(
      (result) => result.flatMap((snapshot) {
        if (!snapshot.exists) {
          // Pasa de verdad: alguien tiene el detalle abierto y borra el
          // objetivo desde otro dispositivo. Un fallo tipado deja que la
          // pantalla lo explique en vez de pintar un objetivo vacío.
          return const Failed<Goal>(NotFoundFailure(code: 'goal-missing'));
        }
        return Success<Goal>(GoalDto.fromFirestore(snapshot));
      }),
    );
  }

  @override
  Future<Result<Goal>> createGoal(Goal goal) => runGuarded(() async {
    await _goals.createGoal(
      uid: goal.ownerId,
      goalId: goal.id,
      data: GoalDto.toCreate(goal),
    );
    // Se devuelve la entidad que se mandó, no una relectura: `createdAt` y
    // `updatedAt` son centinelas que el servidor todavía no resolvió, así que
    // releer costaría una lectura para obtener los mismos datos con dos fechas
    // nulas. El stream de la lista ya trae la versión confirmada.
    return goal;
  });

  @override
  Future<Result<Goal>> createGoalWithMissions({
    required Goal goal,
    required List<Mission> missions,
  }) async {
    if (missions.isEmpty) {
      return createGoal(goal);
    }

    return runGuarded(() async {
      // Objetivo y misiones en un único `WriteBatch`: si se guardara el
      // objetivo y fallara el alta de misiones, quedaría un objetivo huérfano y
      // vacío. Es el cierre del asistente con IA (Fase 6), donde perder el plan
      // generado y dejar el objetivo pelado sería el peor resultado posible.
      //
      // Las misiones heredan el título y la categoría del objetivo: la lista
      // "Hoy" los muestra desnormalizados para no pagar una lectura por misión.
      await _missions.createMissionsBatch(
        uid: goal.ownerId,
        goalId: goal.id,
        goalData: GoalDto.toCreate(goal),
        missionsById: <String, Map<String, Object?>>{
          for (final mission in missions)
            mission.id: MissionDto.toCreate(
              mission.copyWith(
                goalId: goal.id,
                goalTitle: goal.title,
                categoryId: goal.categoryId,
              ),
            ),
        },
      );
      return goal;
    });
  }

  @override
  Future<Result<void>> updateGoal(Goal goal) => runGuarded(
    () => _goals.updateGoal(
      uid: goal.ownerId,
      goalId: goal.id,
      data: GoalDto.toUpdate(goal),
    ),
  );

  @override
  Future<Result<void>> updateStatus({
    required String uid,
    required String goalId,
    required GoalStatus status,
  }) => runGuarded(
    () => _goals.updateGoal(
      uid: uid,
      goalId: goalId,
      data: GoalDto.statusUpdate(status),
    ),
  );

  @override
  Future<Result<void>> deleteGoal({
    required String uid,
    required String goalId,
  }) => runGuarded(() => _goals.deleteGoal(uid: uid, goalId: goalId));

  @override
  Future<Result<void>> toggleMilestone({
    required String uid,
    required String goalId,
    required String milestoneId,
    required bool done,
  }) => runGuarded(() async {
    // Los hitos van embebidos en el objetivo, así que marcar uno exige leer la
    // lista, modificarla y reescribirla entera. Se relee justo antes de
    // escribir para no pisar un hito que se marcó en otro dispositivo entre
    // que se pintó la pantalla y se tocó el check.
    final snapshot = await _goals.getGoal(uid: uid, goalId: goalId);
    if (!snapshot.exists) {
      throw const NotFoundFailure(code: 'goal-missing');
    }

    final goal = GoalDto.fromFirestore(snapshot);
    final index = goal.milestones.indexWhere((m) => m.id == milestoneId);
    if (index == -1) {
      throw const NotFoundFailure(code: 'milestone-missing');
    }

    final target = goal.milestones[index];
    final updated = List<Milestone>.of(goal.milestones);
    // Se construye el hito en lugar de usar `copyWith`: ese método resuelve
    // `completedAt ?? this.completedAt`, así que pasarle `null` conserva la
    // fecha vieja. Al desmarcar hay que borrarla de verdad — un hito no
    // alcanzado con fecha de cumplimiento es un dato contradictorio.
    updated[index] = Milestone(
      id: target.id,
      title: target.title,
      order: target.order,
      done: done,
      completedAt: done ? DateTime.now().toUtc() : null,
    );

    await _goals.updateGoal(
      uid: uid,
      goalId: goalId,
      data: GoalDto.milestonesUpdate(updated),
    );
  });
}
