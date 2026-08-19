import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Acceso a la subcolección plana de misiones (ADR-005).
class FirestoreMissionDataSource {
  /// Crea el datasource.
  const FirestoreMissionDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _missions(String uid) =>
      _firestore.collection('users').doc(uid).collection('missions');

  DocumentReference<Map<String, dynamic>> _missionRef(
    String uid,
    String missionId,
  ) => _missions(uid).doc(missionId);

  /// Observa las misiones abiertas cuyo vencimiento cae hasta el final del día.
  ///
  /// Es la consulta más usada de la app y resuelve la pantalla "Hoy" en **una
  /// sola lectura de índice**. Se apoya en `missions(status, dueDate, order)`.
  ///
  /// Filtra por `pending` y no por "abiertas" porque Firestore no admite
  /// `whereIn` combinado con desigualdad sobre otro campo sin un índice por
  /// cada combinación. Las misiones ya empezadas se muestran igual: el
  /// repositorio las suma desde la consulta por objetivo cuando hace falta.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchToday({
    required String uid,
    DateTime? day,
  }) {
    final endOfDay = AscendDateUtils.endOfDay(day ?? DateTime.now());
    return _missions(uid)
        .where('status', isEqualTo: MissionStatus.pending.wireValue)
        .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('dueDate')
        .orderBy('order')
        .snapshots();
  }

  /// Observa las misiones de un objetivo, en su orden manual.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchByGoal({
    required String uid,
    required String goalId,
  }) => _missions(
    uid,
  ).where('goalId', isEqualTo: goalId).orderBy('order').snapshots();

  /// Observa misiones con filtros combinados.
  ///
  /// El orden es siempre `order` para no exigir un índice por cada combinación
  /// posible de filtros.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMissions({
    required String uid,
    MissionStatus? status,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    String? categoryId,
    String? goalId,
  }) {
    Query<Map<String, dynamic>> query = _missions(uid);

    if (goalId != null) {
      query = query.where('goalId', isEqualTo: goalId);
    }
    if (categoryId != null) {
      query = query.where('categoryId', isEqualTo: categoryId);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status.wireValue);
    }
    if (difficulty != null) {
      query = query.where('difficulty', isEqualTo: difficulty.wireValue);
    }
    if (budget != null) {
      query = query.where('budget', isEqualTo: budget.wireValue);
    }

    return query.orderBy('order').snapshots();
  }

  /// Lee una misión una sola vez.
  Future<DocumentSnapshot<Map<String, dynamic>>> getMission({
    required String uid,
    required String missionId,
  }) => _missionRef(uid, missionId).get();

  /// Historial paginado de misiones completadas, de la más reciente a la más
  /// vieja.
  Future<QuerySnapshot<Map<String, dynamic>>> getHistory({
    required String uid,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 20,
  }) {
    Query<Map<String, dynamic>> query = _missions(uid)
        .where('status', isEqualTo: MissionStatus.completed.wireValue)
        .orderBy('completedAt', descending: true);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }

    return query.limit(limit).get();
  }

  /// Crea el documento con un id generado en el cliente.
  Future<void> createMission({
    required String uid,
    required String missionId,
    required Map<String, Object?> data,
  }) => _missionRef(uid, missionId).set(data);

  /// Crea varias misiones en una sola escritura atómica.
  ///
  /// Lo usa el alta de objetivo con plan: si se guardara el objetivo y fallara
  /// el alta de misiones, quedaría un objetivo huérfano y vacío.
  Future<void> createMissionsBatch({
    required String uid,
    required Map<String, Map<String, Object?>> missionsById,
    String? goalId,
    Map<String, Object?>? goalData,
  }) {
    final batch = _firestore.batch();

    if (goalId != null && goalData != null) {
      batch.set(
        _firestore.collection('users').doc(uid).collection('goals').doc(goalId),
        goalData,
      );
    }
    missionsById.forEach((missionId, data) {
      batch.set(_missionRef(uid, missionId), data);
    });

    return batch.commit();
  }

  /// Actualiza campos sueltos.
  Future<void> updateMission({
    required String uid,
    required String missionId,
    required Map<String, Object?> data,
  }) => _missionRef(uid, missionId).update(data);

  /// Reordena varias misiones en una sola escritura.
  ///
  /// En lote y no una por una: reordenar por arrastre genera N escrituras, y
  /// mandarlas sueltas deja la lista a medio ordenar si se corta la red.
  Future<void> reorderMissions({
    required String uid,
    required List<String> orderedIds,
  }) {
    final batch = _firestore.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_missionRef(uid, orderedIds[i]), <String, Object?>{
        'order': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  }

  /// Borra una misión.
  Future<void> deleteMission({
    required String uid,
    required String missionId,
  }) => _missionRef(uid, missionId).delete();
}
