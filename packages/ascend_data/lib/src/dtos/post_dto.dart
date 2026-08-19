import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Traducción entre `posts/{postId}` y [Post].
///
/// ## Tres campos que el cliente nunca manda
///
/// ```
/// allow create: ... && absent('counters')
///                   && absent('moderation')
///                   && absent('author');
/// ```
///
/// - `counters` los mantienen triggers: si el cliente pudiera fijarlos, se
///   pondría mil likes.
/// - `moderation` la decide el servidor: autoaprobarse contenido dejaría la
///   moderación en decorado.
/// - `author` lo copia un trigger desde `publicProfiles`: si el cliente lo
///   escribiera, podría publicar con el nombre y el nivel de otra persona.
abstract final class PostDto {
  /// Convierte un documento en la entidad.
  static Post fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) =>
      fromMap(snapshot.data() ?? const <String, dynamic>{}, id: snapshot.id);

  /// Convierte un mapa plano en la entidad.
  static Post fromMap(Map<String, dynamic> data, {required String id}) {
    final author = _mapOf(data['author']);
    final source = _mapOf(data['source']);
    final counters = _mapOf(data['counters']);
    final moderation = _mapOf(data['moderation']);

    return Post(
      id: id,
      authorId: _stringOf(data['authorId']),
      type: PostType.fromWire(_nullableStringOf(data['type'])),
      text: _stringOf(data['text']),
      createdAt: _dateOf(data['createdAt']) ?? DateTime.now().toUtc(),
      author: author.isEmpty
          ? null
          : PostAuthor(
              displayName: _stringOf(author['displayName']),
              handle: _stringOf(author['handle']),
              photoUrl: _nullableStringOf(author['photoUrl']),
              level: _intOf(author['level'], fallback: 1),
            ),
      source: source.isEmpty
          ? null
          : PostSource(
              goalId: _nullableStringOf(source['goalId']),
              goalTitle: _nullableStringOf(source['goalTitle']),
              missionId: _nullableStringOf(source['missionId']),
              missionTitle: _nullableStringOf(source['missionTitle']),
              auraEarned: _intOf(source['auraEarned']),
            ),
      categoryId: _nullableStringOf(data['categoryId']),
      mediaUrl: _nullableStringOf(data['mediaUrl']),
      thumbUrl: _nullableStringOf(data['thumbUrl']),
      visibility: Visibility.fromWire(_nullableStringOf(data['visibility'])),
      counters: PostCounters(
        likes: _intOf(counters['likes']),
        comments: _intOf(counters['comments']),
        reports: _intOf(counters['reports']),
      ),
      moderation: ModerationStatus.fromWire(
        _nullableStringOf(moderation['status']),
      ),
      updatedAt: _dateOf(data['updatedAt']),
    );
  }

  /// Documento de alta. **No incluye `counters`, `moderation` ni `author`.**
  static Map<String, Object?> toCreate(Post post) => <String, Object?>{
    'authorId': post.authorId,
    'type': post.type.wireValue,
    'text': post.text,
    'categoryId': post.categoryId,
    'mediaUrl': post.mediaUrl,
    'thumbUrl': post.thumbUrl,
    'visibility': post.visibility.wireValue,
    if (post.source != null) 'source': _sourceToMap(post.source!),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'deletedAt': null,
  };

  /// Corrección del texto. Es lo único editable tras publicar.
  ///
  /// Cambiar el logro asociado después de publicar sería reescribir la
  /// historia, así que las reglas solo admiten `text` y `updatedAt`.
  static Map<String, Object?> textUpdate(String text) => <String, Object?>{
    'text': text,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static Map<String, Object?> _sourceToMap(PostSource source) =>
      <String, Object?>{
        'goalId': source.goalId,
        'goalTitle': source.goalTitle,
        'missionId': source.missionId,
        'missionTitle': source.missionTitle,
        'auraEarned': source.auraEarned,
      };

  static Map<String, dynamic> _mapOf(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  static String _stringOf(Object? value, {String fallback = ''}) =>
      value is String && value.isNotEmpty ? value : fallback;

  static String? _nullableStringOf(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static int _intOf(Object? value, {int fallback = 0}) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => fallback,
  };

  static DateTime? _dateOf(Object? value) => switch (value) {
    final Timestamp v => v.toDate().toUtc(),
    final DateTime v => v.toUtc(),
    _ => null,
  };
}

/// Traducción entre `posts/{postId}/comments/{commentId}` y [Comment].
abstract final class CommentDto {
  /// Convierte un documento en la entidad.
  static Comment fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String postId,
  }) => fromMap(
    snapshot.data() ?? const <String, dynamic>{},
    id: snapshot.id,
    postId: postId,
  );

  /// Convierte un mapa plano en la entidad.
  static Comment fromMap(
    Map<String, dynamic> data, {
    required String id,
    required String postId,
  }) {
    final author = PostDto._mapOf(data['author']);
    final counters = PostDto._mapOf(data['counters']);
    final moderation = PostDto._mapOf(data['moderation']);

    return Comment(
      id: id,
      postId: postId,
      authorId: PostDto._stringOf(data['authorId']),
      text: PostDto._stringOf(data['text']),
      createdAt: PostDto._dateOf(data['createdAt']) ?? DateTime.now().toUtc(),
      author: author.isEmpty
          ? null
          : PostAuthor(
              displayName: PostDto._stringOf(author['displayName']),
              handle: PostDto._stringOf(author['handle']),
              photoUrl: PostDto._nullableStringOf(author['photoUrl']),
              level: PostDto._intOf(author['level'], fallback: 1),
            ),
      parentId: PostDto._nullableStringOf(data['parentId']),
      likes: PostDto._intOf(counters['likes']),
      moderation: ModerationStatus.fromWire(
        PostDto._nullableStringOf(moderation['status']),
      ),
    );
  }

  /// Documento de alta. **No incluye `counters`, `moderation` ni `author`.**
  static Map<String, Object?> toCreate(Comment comment) => <String, Object?>{
    'postId': comment.postId,
    'authorId': comment.authorId,
    'text': comment.text,
    'parentId': comment.parentId,
    'createdAt': FieldValue.serverTimestamp(),
    'deletedAt': null,
  };
}

/// Traducción entre `reports/{reportId}` y [Report].
abstract final class ReportDto {
  /// Convierte un documento en el reporte del dominio.
  ///
  /// Solo lo usa el panel: las reglas le prohíben leer `reports` a quien no es
  /// administrador, incluido quien lo creó. Ver la cola de moderación revelaría
  /// qué se reportó y qué no, que es información de moderación.
  static Report fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final target = data['target'] is Map
        ? Map<String, dynamic>.from(data['target'] as Map)
        : const <String, dynamic>{};

    return Report(
      id: snapshot.id,
      reporterId: _text(data['reporterId']),
      targetType: _text(target['type']),
      targetId: _text(target['id']),
      targetOwnerId: _optionalText(target['ownerId']),
      reason: ReportReason.fromWire(_optionalText(data['reason'])),
      details: _optionalText(data['details']),
      status: ReportStatus.fromWire(_optionalText(data['status'])),
      createdAt: switch (data['createdAt']) {
        final Timestamp v => v.toDate(),
        _ => DateTime.now().toUtc(),
      },
    );
  }

  static String _text(Object? value) => value is String ? value : '';

  static String? _optionalText(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  /// Documento de alta.
  ///
  /// `status` viaja en `'open'` porque la regla lo exige explícitamente: nadie
  /// puede crear un reporte ya resuelto para que nunca se revise.
  static Map<String, Object?> toCreate(Report report) => <String, Object?>{
    'reporterId': report.reporterId,
    'target': <String, Object?>{
      'type': report.targetType,
      'id': report.targetId,
      'ownerId': report.targetOwnerId,
    },
    'reason': report.reason.wireValue,
    'details': report.details,
    'status': ReportStatus.open.wireValue,
    'resolution': null,
    'handledBy': null,
    'handledAt': null,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

/// Traducción de `publicProfiles/{uid}` al autor desnormalizado.
abstract final class PublicProfileDto {
  /// Convierte un documento en el autor.
  static PostAuthor fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return PostAuthor(
      displayName: PostDto._stringOf(data['displayName']),
      handle: PostDto._stringOf(data['handle']),
      photoUrl: PostDto._nullableStringOf(data['photoUrl']),
      level: PostDto._intOf(data['level'], fallback: 1),
    );
  }
}
