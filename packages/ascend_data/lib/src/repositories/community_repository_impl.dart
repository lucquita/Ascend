import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/remote/firestore_community_datasource.dart';
import 'package:ascend_data/src/dtos/post_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Implementación de [PostRepository] sobre Firestore.
class PostRepositoryImpl implements PostRepository {
  /// Crea el repositorio.
  const PostRepositoryImpl({
    required FirestoreCommunityDataSource communityDataSource,
  }) : _community = communityDataSource;

  final FirestoreCommunityDataSource _community;

  @override
  Future<Result<Paginated<Post>>> getFeed({
    Object? cursor,
    int limit = 20,
    String? categoryId,
  }) => runGuarded(() async {
    final snapshot = await _community.getFeed(
      cursor: _asCursor(cursor),
      limit: limit,
      categoryId: categoryId,
    );
    return _toPage(snapshot, limit);
  });

  @override
  Future<Result<Paginated<Post>>> getByAuthor({
    required String authorId,
    Object? cursor,
    int limit = 20,
  }) => runGuarded(() async {
    final snapshot = await _community.getByAuthor(
      authorId: authorId,
      cursor: _asCursor(cursor),
      limit: limit,
    );
    return _toPage(snapshot, limit);
  });

  @override
  Stream<Result<Post>> watchPost(String postId) {
    return guardStream(_community.watchPost(postId)).map(
      (result) => result.flatMap((snapshot) {
        if (!snapshot.exists) {
          return const Failed<Post>(NotFoundFailure(code: 'post-missing'));
        }
        return Success<Post>(PostDto.fromFirestore(snapshot));
      }),
    );
  }

  @override
  Future<Result<Post>> createPost(Post post) => runGuarded(() async {
    await _community.createPost(post.id, PostDto.toCreate(post));
    // Se devuelve lo que se mandó: `author`, `counters` y `moderation` los
    // completa un trigger, así que releer ahora traería el documento a medio
    // enriquecer.
    return post;
  });

  @override
  Future<Result<void>> updateText({
    required String postId,
    required String text,
  }) =>
      runGuarded(() => _community.updatePost(postId, PostDto.textUpdate(text)));

  @override
  Future<Result<void>> deletePost(String postId) =>
      runGuarded(() => _community.deletePost(postId));

  @override
  Future<Result<void>> setLike({
    required String postId,
    required String uid,
    required bool liked,
  }) => runGuarded(
    () => _community.setLike(postId: postId, uid: uid, liked: liked),
  );

  @override
  Future<Result<bool>> hasLiked({
    required String postId,
    required String uid,
  }) => runGuarded(() async {
    final snapshot = await _community.getLike(postId: postId, uid: uid);
    return snapshot.exists;
  });

  static DocumentSnapshot<Map<String, dynamic>>? _asCursor(Object? cursor) =>
      cursor is DocumentSnapshot<Map<String, dynamic>> ? cursor : null;

  static Paginated<Post> _toPage(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    int limit,
  ) => Paginated<Post>(
    items: snapshot.docs.map(PostDto.fromFirestore).toList(growable: false),
    cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
    hasMore: snapshot.docs.length == limit,
  );
}

/// Implementación de [CommentRepository].
class CommentRepositoryImpl implements CommentRepository {
  /// Crea el repositorio.
  const CommentRepositoryImpl({
    required FirestoreCommunityDataSource communityDataSource,
  }) : _community = communityDataSource;

  final FirestoreCommunityDataSource _community;

  @override
  Stream<Result<List<Comment>>> watchComments(String postId) {
    return guardStream(_community.watchComments(postId)).map(
      (result) => result.map(
        (snapshot) => snapshot.docs
            .map((doc) => CommentDto.fromFirestore(doc, postId: postId))
            .toList(growable: false),
      ),
    );
  }

  @override
  Future<Result<Comment>> addComment(Comment comment) => runGuarded(() async {
    await _community.addComment(
      postId: comment.postId,
      commentId: comment.id,
      data: CommentDto.toCreate(comment),
    );
    return comment;
  });

  @override
  Future<Result<void>> deleteComment({
    required String postId,
    required String commentId,
  }) => runGuarded(
    () => _community.deleteComment(postId: postId, commentId: commentId),
  );
}

/// Implementación de [ReportRepository].
class ReportRepositoryImpl implements ReportRepository {
  /// Crea el repositorio.
  const ReportRepositoryImpl({
    required FirestoreCommunityDataSource communityDataSource,
  }) : _community = communityDataSource;

  final FirestoreCommunityDataSource _community;

  @override
  Future<Result<void>> report(Report report) => runGuarded(
    () => _community.createReport(report.id, ReportDto.toCreate(report)),
  );

  @override
  Future<Result<bool>> hasReported({
    required String targetId,
    required String reporterId,
  }) async {
    final id = Report.buildId(targetId: targetId, reporterId: reporterId);
    final result = await runGuarded(() async {
      final snapshot = await _community.getReport(id);
      return snapshot.exists;
    });

    // Un usuario común NO puede leer `reports`: solo el admin. El
    // `permission-denied` acá no es un error a mostrar, es la respuesta
    // esperada, y significa "no puedo saberlo". Se responde `false` para que la
    // pantalla ofrezca reportar; si ya lo había hecho, la escritura sobrescribe
    // el mismo documento y no infla nada.
    if (result case Failed<bool>(:final failure)) {
      if (failure is PermissionFailure) {
        return const Success<bool>(false);
      }
    }
    return result;
  }
}

/// Implementación de [PublicProfileRepository].
class PublicProfileRepositoryImpl implements PublicProfileRepository {
  /// Crea el repositorio.
  const PublicProfileRepositoryImpl({
    required FirestoreCommunityDataSource communityDataSource,
  }) : _community = communityDataSource;

  final FirestoreCommunityDataSource _community;

  @override
  Future<Result<PostAuthor>> getByUid(String uid) => runGuarded(() async {
    final snapshot = await _community.getPublicProfile(uid);
    if (!snapshot.exists) {
      throw const NotFoundFailure(code: 'public-profile-missing');
    }
    return PublicProfileDto.fromFirestore(snapshot);
  });

  @override
  Stream<Result<PostAuthor>> watchByUid(String uid) {
    return guardStream(_community.watchPublicProfile(uid)).map(
      (result) => result.flatMap((snapshot) {
        if (!snapshot.exists) {
          return const Failed<PostAuthor>(
            NotFoundFailure(code: 'public-profile-missing'),
          );
        }
        return Success<PostAuthor>(PublicProfileDto.fromFirestore(snapshot));
      }),
    );
  }
}
