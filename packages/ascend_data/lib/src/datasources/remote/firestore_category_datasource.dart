import 'package:cloud_firestore/cloud_firestore.dart';

/// Acceso al catálogo global de categorías.
///
/// El catálogo es pequeño (10 documentos) y cambia muy de vez en cuando, pero
/// se lee en cada alta de objetivo. Se sirve desde la caché de Firestore
/// —`snapshots()` la usa de entrada y solo pide al servidor lo que cambió—, así
/// que no hace falta una caché propia en Hive.
class FirestoreCategoryDataSource {
  /// Crea el datasource.
  const FirestoreCategoryDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _categories =>
      _firestore.collection('categories');

  /// Observa el catálogo ordenado para presentación.
  ///
  /// [onlyActive] filtra las dadas de baja desde el panel: una categoría
  /// desactivada no debe ofrecerse al crear un objetivo, pero los objetivos que
  /// ya la usan tienen que seguir mostrándola.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchCategories({
    bool onlyActive = true,
  }) {
    Query<Map<String, dynamic>> query = _categories;
    if (onlyActive) {
      query = query.where('active', isEqualTo: true);
    }
    return query.orderBy('order').snapshots();
  }

  /// Lee una categoría por id.
  Future<DocumentSnapshot<Map<String, dynamic>>> getCategory(String id) =>
      _categories.doc(id).get();
}
