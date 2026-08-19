import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/remote/firestore_mission_datasource.dart';
import 'package:ascend_data/src/dtos/mission_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Implementación de [MissionRepository] sobre Firestore.
class MissionRepositoryImpl implements MissionRepository {
  /// Crea el repositorio.
  const MissionRepositoryImpl({
    required FirestoreMissionDataSource missionDataSource,
  }) : _missions = missionDataSource;

  final FirestoreMissionDataSource _missions;

  @override
  Stream<Result<List<Mission>>> watchToday({
    required String uid,
    DateTime? day,
  }) => guardStream(
    _missions.watchToday(uid: uid, day: day),
  ).map((result) => result.map(_toMissions));

  @override
  Stream<Result<List<Mission>>> watchByGoal({
    required String uid,
    required String goalId,
  }) => guardStream(
    _missions.watchByGoal(uid: uid, goalId: goalId),
  ).map((result) => result.map(_toMissions));

  @override
  Stream<Result<List<Mission>>> watchMissions({
    required String uid,
    MissionStatus? status,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    String? categoryId,
    String? goalId,
  }) => guardStream(
    _missions.watchMissions(
      uid: uid,
      status: status,
      difficulty: difficulty,
      budget: budget,
      categoryId: categoryId,
      goalId: goalId,
    ),
  ).map((result) => result.map(_toMissions));

  @override
  Future<Result<Mission>> getMission({
    required String uid,
    required String missionId,
  }) => runGuarded(() async {
    final snapshot = await _missions.getMission(uid: uid, missionId: missionId);
    if (!snapshot.exists) {
      throw const NotFoundFailure(code: 'mission-missing');
    }
    return MissionDto.fromFirestore(snapshot);
  });

  @override
  Future<Result<Mission>> createMission(Mission mission) =>
      runGuarded(() async {
        await _missions.createMission(
          uid: mission.ownerId,
          missionId: mission.id,
          data: MissionDto.toCreate(mission),
        );
        return mission;
      });

  @override
  Future<Result<void>> updateMission(Mission mission) => runGuarded(
    () => _missions.updateMission(
      uid: mission.ownerId,
      missionId: mission.id,
      data: MissionDto.toUpdate(mission),
    ),
  );

  @override
  Future<Result<void>> completeMission({
    required String uid,
    required String missionId,
    Evidence? evidence,
  }) => runGuarded(() async {
    // Se relee antes de escribir para evaluar `canComplete` sobre el estado
    // real y no sobre lo que la pantalla tenía cacheado. Sin esto, dos toques
    // rápidos o dos dispositivos podrían completar la misma misión dos veces y
    // disparar el trigger de Aura por duplicado.
    final snapshot = await _missions.getMission(uid: uid, missionId: missionId);
    if (!snapshot.exists) {
      throw const NotFoundFailure(code: 'mission-missing');
    }

    final current = MissionDto.fromFirestore(snapshot);
    final candidate = evidence == null
        ? current
        : current.copyWith(evidence: evidence);

    if (!candidate.canComplete) {
      throw ValidationFailure(
        messageKey: current.status.isCompleted
            ? 'validation.mission.alreadyCompleted'
            : 'validation.mission.evidenceRequired',
        field: 'status',
      );
    }

    await _missions.updateMission(
      uid: uid,
      missionId: missionId,
      // El cliente solo cambia el estado. El Aura la otorga el trigger del
      // servidor al ver la transición (ADR-003).
      data: MissionDto.completionUpdate(evidence: evidence),
    );
  });

  @override
  Future<Result<void>> skipMission({
    required String uid,
    required String missionId,
    String? reason,
  }) => runGuarded(
    () => _missions.updateMission(
      uid: uid,
      missionId: missionId,
      data: MissionDto.statusUpdate(MissionStatus.skipped),
    ),
  );

  @override
  Future<Result<void>> reorderMissions({
    required String uid,
    required List<String> orderedIds,
  }) => runGuarded(
    () => _missions.reorderMissions(uid: uid, orderedIds: orderedIds),
  );

  @override
  Future<Result<void>> deleteMission({
    required String uid,
    required String missionId,
  }) =>
      runGuarded(() => _missions.deleteMission(uid: uid, missionId: missionId));

  @override
  Future<Result<Paginated<Mission>>> getHistory({
    required String uid,
    Object? cursor,
    int limit = 20,
  }) => runGuarded(() async {
    // El cursor es opaco para el dominio: entra como `Object?` y solo acá se
    // reconoce como `DocumentSnapshot`. Si mañana cambiamos de backend, el
    // contrato no se mueve.
    final snapshot = await _missions.getHistory(
      uid: uid,
      cursor: cursor is DocumentSnapshot<Map<String, dynamic>> ? cursor : null,
      limit: limit,
    );

    final items = snapshot.docs
        .map(MissionDto.fromFirestore)
        .toList(growable: false);

    return Paginated<Mission>(
      items: items,
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      // Una página incompleta significa que no hay más. Preguntar por la
      // siguiente solo para descubrir que está vacía cuesta una lectura.
      hasMore: snapshot.docs.length == limit,
    );
  });

  static List<Mission> _toMissions(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(MissionDto.fromFirestore).toList(growable: false);
}
