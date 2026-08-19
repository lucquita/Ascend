import 'package:cloud_firestore/cloud_firestore.dart';

/// Acceso de **solo lectura** al Aura.
///
/// No expone ningún método de escritura: el saldo y el ledger los escribe el
/// Admin SDK desde el trigger `onMissionWrite` (ADR-003).
class FirestoreAuraDataSource {
  /// Crea el datasource.
  const FirestoreAuraDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _ledger(String uid) =>
      _userRef(uid).collection('auraLedger');

  /// Observa el documento de perfil, del que cuelga el saldo.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUser(String uid) =>
      _userRef(uid).snapshots();

  /// Página del ledger, del asiento más reciente al más viejo.
  Future<QuerySnapshot<Map<String, dynamic>>> getLedger({
    required String uid,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 30,
  }) {
    Query<Map<String, dynamic>> query = _ledger(
      uid,
    ).orderBy('createdAt', descending: true);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    return query.limit(limit).get();
  }

  /// Asientos de los últimos [days] días, para el gráfico de evolución.
  ///
  /// Se acota por fecha y no se traen todos: el ledger crece sin techo y leerlo
  /// entero para pintar un gráfico de 30 días sería carísimo a los seis meses
  /// de uso.
  Future<QuerySnapshot<Map<String, dynamic>>> getRecentEntries({
    required String uid,
    required int days,
    DateTime? now,
  }) {
    final from = (now ?? DateTime.now()).toUtc().subtract(Duration(days: days));
    return _ledger(uid)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .orderBy('createdAt')
        .get();
  }

  /// Tabla de niveles configurada en el servidor.
  Future<DocumentSnapshot<Map<String, dynamic>>> getAuraRules() =>
      _firestore.collection('config').doc('auraRules').get();
}
