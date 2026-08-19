import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Acceso a la subcolección de objetivos de una persona.
///
/// No mapea errores ni devuelve `Result`: eso es trabajo del repositorio. Acá
/// solo vive el "cómo se le habla a Firestore", para poder sustituirlo entero
/// en los tests sin tocar la lógica.
class FirestoreGoalDataSource {
  /// Crea el datasource.
  const FirestoreGoalDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _goals(String uid) =>
      _firestore.collection('users').doc(uid).collection('goals');

  DocumentReference<Map<String, dynamic>> _goalRef(String uid, String goalId) =>
      _goals(uid).doc(goalId);

  /// Observa los objetivos, opcionalmente filtrados.
  ///
  /// El orden es siempre `updatedAt desc` —lo último que tocaste, arriba— y
  /// coincide con los índices declarados en `firestore.indexes.json`. Cambiar
  /// este orden sin agregar el índice correspondiente hace fallar la consulta
  /// en producción con un error que solo aparece con datos reales.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchGoals({
    required String uid,
    GoalStatus? status,
    String? categoryId,
  }) {
    Query<Map<String, dynamic>> query = _goals(uid);

    if (categoryId != null) {
      query = query.where('categoryId', isEqualTo: categoryId);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status.wireValue);
    }

    return query.orderBy('updatedAt', descending: true).snapshots();
  }

  /// Observa un objetivo concreto.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchGoal({
    required String uid,
    required String goalId,
  }) => _goalRef(uid, goalId).snapshots();

  /// Lee un objetivo una sola vez.
  Future<DocumentSnapshot<Map<String, dynamic>>> getGoal({
    required String uid,
    required String goalId,
  }) => _goalRef(uid, goalId).get();

  /// Crea el documento con un id generado en el cliente.
  ///
  /// El id lo trae la entidad y no lo genera Firestore: así el alta es
  /// idempotente y un reintento tras un corte de red no crea dos objetivos.
  Future<void> createGoal({
    required String uid,
    required String goalId,
    required Map<String, Object?> data,
  }) => _goalRef(uid, goalId).set(data);

  /// Actualiza campos sueltos de un objetivo.
  ///
  /// `update` y no `set(merge: true)`: `update` falla si el documento no
  /// existe, que es exactamente lo que queremos —editar algo borrado tiene que
  /// avisar, no resucitarlo con la mitad de los campos.
  Future<void> updateGoal({
    required String uid,
    required String goalId,
    required Map<String, Object?> data,
  }) => _goalRef(uid, goalId).update(data);

  /// Borra el objetivo.
  ///
  /// Las misiones asociadas las borra en cascada el trigger `onGoalDelete`: el
  /// cliente no puede recorrerlas de forma fiable —se le puede cortar la red a
  /// mitad— y dejarlas huérfanas rompería la pantalla "Hoy".
  Future<void> deleteGoal({required String uid, required String goalId}) =>
      _goalRef(uid, goalId).delete();
}
