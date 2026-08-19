import 'package:cloud_firestore/cloud_firestore.dart';

/// Acceso al feed, comentarios, likes y reportes.
class FirestoreCommunityDataSource {
  /// Crea el datasource.
  const FirestoreCommunityDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('posts');

  DocumentReference<Map<String, dynamic>> _postRef(String postId) =>
      _posts.doc(postId);

  /// Feed global paginado con cursores (ADR-006).
  ///
  /// Filtra por `moderation.status == visible` **en la consulta** y no al
  /// pintar: si se filtrara en el cliente, una página de 20 posts con 5 ocultos
  /// mostraría 15, y peor, esos 5 igual habrían viajado por la red.
  Future<QuerySnapshot<Map<String, dynamic>>> getFeed({
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 20,
    String? categoryId,
  }) {
    Query<Map<String, dynamic>> query = _posts.where(
      'moderation.status',
      isEqualTo: 'visible',
    );

    if (categoryId != null) {
      query = query.where('categoryId', isEqualTo: categoryId);
    }
    query = query.orderBy('createdAt', descending: true);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    return query.limit(limit).get();
  }

  /// Publicaciones de una persona, de la más reciente a la más vieja.
  Future<QuerySnapshot<Map<String, dynamic>>> getByAuthor({
    required String authorId,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 20,
  }) {
    Query<Map<String, dynamic>> query = _posts
        .where('authorId', isEqualTo: authorId)
        .orderBy('createdAt', descending: true);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    return query.limit(limit).get();
  }

  /// Observa una publicación.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPost(String postId) =>
      _postRef(postId).snapshots();

  /// Crea la publicación con id de cliente.
  Future<void> createPost(String postId, Map<String, Object?> data) =>
      _postRef(postId).set(data);

  /// Actualiza campos de una publicación.
  Future<void> updatePost(String postId, Map<String, Object?> data) =>
      _postRef(postId).update(data);

  /// Borra una publicación.
  Future<void> deletePost(String postId) => _postRef(postId).delete();

  /// Da o quita "me gusta".
  ///
  /// El id del documento **es** el uid: la idempotencia sale gratis y saber si
  /// ya diste like cuesta una lectura por id en vez de una consulta.
  Future<void> setLike({
    required String postId,
    required String uid,
    required bool liked,
  }) {
    final ref = _postRef(postId).collection('likes').doc(uid);
    return liked
        ? ref.set(<String, Object?>{
            'uid': uid,
            'createdAt': FieldValue.serverTimestamp(),
          })
        : ref.delete();
  }

  /// Lee si [uid] ya dio "me gusta".
  Future<DocumentSnapshot<Map<String, dynamic>>> getLike({
    required String postId,
    required String uid,
  }) => _postRef(postId).collection('likes').doc(uid).get();

  /// Observa los comentarios visibles de una publicación.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchComments(String postId) =>
      _postRef(postId)
          .collection('comments')
          .where('moderation.status', isEqualTo: 'visible')
          .orderBy('createdAt')
          .snapshots();

  /// Publica un comentario.
  Future<void> addComment({
    required String postId,
    required String commentId,
    required Map<String, Object?> data,
  }) => _postRef(postId).collection('comments').doc(commentId).set(data);

  /// Borra un comentario.
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) => _postRef(postId).collection('comments').doc(commentId).delete();

  /// Crea un reporte con id determinístico.
  Future<void> createReport(String reportId, Map<String, Object?> data) =>
      _firestore.collection('reports').doc(reportId).set(data);

  /// Lee si un reporte ya existe.
  ///
  /// El cliente **no puede leer** `reports` —solo el admin—, así que esta
  /// consulta va a fallar con `permission-denied` para un usuario común. Se
  /// mantiene porque el panel de administración sí la usa; el móvil deduce el
  /// estado del reporte por el resultado de la escritura.
  Future<DocumentSnapshot<Map<String, dynamic>>> getReport(String reportId) =>
      _firestore.collection('reports').doc(reportId).get();

  /// Lee el perfil público de una persona.
  Future<DocumentSnapshot<Map<String, dynamic>>> getPublicProfile(String uid) =>
      _firestore.collection('publicProfiles').doc(uid).get();

  /// Observa el perfil público de una persona.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPublicProfile(
    String uid,
  ) => _firestore.collection('publicProfiles').doc(uid).snapshots();
}
