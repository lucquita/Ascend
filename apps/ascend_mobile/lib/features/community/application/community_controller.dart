import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado del feed con paginación acumulada.
///
/// Se guarda la lista completa y no solo la última página porque el scroll
/// infinito necesita todo lo cargado a la vez, y volver a pedir las páginas
/// anteriores al bajar costaría lecturas por cada tramo.
@immutable
class FeedState {
  /// Crea el estado del feed.
  const FeedState({
    this.posts = const <Post>[],
    this.cursor,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  /// Publicaciones cargadas hasta ahora.
  final List<Post> posts;

  /// Cursor de la última página.
  final Object? cursor;

  /// Si quedan más páginas.
  final bool hasMore;

  /// Si hay una página en vuelo.
  final bool isLoadingMore;

  /// Copia con cambios.
  FeedState copyWith({
    List<Post>? posts,
    Object? cursor,
    bool? hasMore,
    bool? isLoadingMore,
  }) => FeedState(
    posts: posts ?? this.posts,
    cursor: cursor ?? this.cursor,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );
}

/// Carga y pagina el feed global.
///
/// Emite `Result<FeedState>` y **nunca lanza**, igual que el resto de los
/// providers del proyecto. Relanzar el `Failure` dentro de un `build()`
/// asincrónico dejaba el provider colgado en carga: la pantalla se quedaba con
/// los skeletons girando en vez de mostrar el error. Devolverlo como dato lo
/// vuelve un caso más que la pantalla pinta con `fold`.
class FeedController extends AsyncNotifier<Result<FeedState>> {
  @override
  Future<Result<FeedState>> build() async {
    final result = await guardResult(
      () => ref.read(postRepositoryProvider).getFeed(),
    );

    return result.map(
      (page) => FeedState(
        posts: page.items,
        cursor: page.cursor,
        hasMore: page.hasMore,
      ),
    );
  }

  /// Carga la página siguiente.
  ///
  /// Es idempotente frente a llamadas repetidas: el scroll dispara este método
  /// muchas veces por segundo al llegar al final, y sin el guard de
  /// `isLoadingMore` se pedirían cinco páginas iguales.
  Future<void> loadMore() async {
    final current = state.value?.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) {
      return;
    }

    state = AsyncData<Result<FeedState>>(
      Success<FeedState>(current.copyWith(isLoadingMore: true)),
    );

    final result = await guardResult(
      () => ref.read(postRepositoryProvider).getFeed(cursor: current.cursor),
    );

    state = AsyncData<Result<FeedState>>(
      result.fold(
        onSuccess: (page) => Success<FeedState>(
          current.copyWith(
            posts: <Post>[...current.posts, ...page.items],
            cursor: page.cursor,
            hasMore: page.hasMore,
            isLoadingMore: false,
          ),
        ),
        // Un fallo al paginar no borra lo ya cargado: se apaga el indicador y
        // la persona puede reintentar bajando de nuevo.
        onFailure: (_) =>
            Success<FeedState>(current.copyWith(isLoadingMore: false)),
      ),
    );
  }

  /// Recarga el feed desde el principio.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Feed global paginado.
final AsyncNotifierProvider<FeedController, Result<FeedState>> feedProvider =
    AsyncNotifierProvider<FeedController, Result<FeedState>>(
      FeedController.new,
      name: 'feed',
    );

/// Comentarios de una publicación, en vivo.
// Sin anotación explícita: `StreamProviderFamily` no está exportado.
final commentsProvider = StreamProvider.family<Result<List<Comment>>, String>(
  (ref, postId) => ref.watch(commentRepositoryProvider).watchComments(postId),
  name: 'comments',
);

/// Orquesta las escrituras de la comunidad.
class CommunityController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  String? get _uid => ref.read(currentUserProvider)?.uid;

  /// Publica el logro de una misión completada.
  Future<String?> publishMission({
    required Mission mission,
    required String text,
  }) async {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return null;
    }

    // Publicar algo que no se completó es el "logro falso" que el sistema de
    // reportes existe para perseguir: se frena antes de escribir.
    final publishable = canPublishMission(mission);
    if (publishable case Failed<void>(:final failure)) {
      _report(failure);
      return null;
    }

    final source = sourceFromMission(mission);
    final validation = validatePost(
      type: PostType.missionCompleted,
      text: text,
      source: source,
    );
    if (validation case Failed<String>(:final failure)) {
      _report(failure);
      return null;
    }

    final post = Post(
      id: IdGenerator.generate(),
      authorId: uid,
      type: PostType.missionCompleted,
      text: validation.valueOrNull!,
      createdAt: DateTime.now().toUtc(),
      source: source,
      categoryId: mission.categoryId,
    );

    return _write(() async {
      final result = await guardResult(
        () => ref.read(postRepositoryProvider).createPost(post),
      );
      return result.map((p) => p.id);
    });
  }

  /// Publica una reflexión libre.
  Future<String?> publishReflection(String text) async {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return null;
    }

    final validation = validatePost(type: PostType.reflection, text: text);
    if (validation case Failed<String>(:final failure)) {
      _report(failure);
      return null;
    }

    final post = Post(
      id: IdGenerator.generate(),
      authorId: uid,
      type: PostType.reflection,
      text: validation.valueOrNull!,
      createdAt: DateTime.now().toUtc(),
    );

    return _write(() async {
      final result = await guardResult(
        () => ref.read(postRepositoryProvider).createPost(post),
      );
      return result.map((p) => p.id);
    });
  }

  /// Da o quita "me gusta".
  Future<bool> toggleLike({required String postId, required bool liked}) async {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return false;
    }

    final result = await guardResult(
      () => ref
          .read(postRepositoryProvider)
          .setLike(postId: postId, uid: uid, liked: liked),
    );

    return result.fold(
      onSuccess: (_) => true,
      onFailure: (failure) {
        _report(failure);
        return false;
      },
    );
  }

  /// Comenta una publicación.
  Future<bool> comment({required String postId, required String text}) async {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return false;
    }

    final validation = validateComment(text);
    if (validation case Failed<String>(:final failure)) {
      _report(failure);
      return false;
    }

    final result = await guardResult(
      () => ref
          .read(commentRepositoryProvider)
          .addComment(
            Comment(
              id: IdGenerator.generate(),
              postId: postId,
              authorId: uid,
              text: validation.valueOrNull!,
              createdAt: DateTime.now().toUtc(),
            ),
          ),
    );

    return result.fold(
      onSuccess: (_) => true,
      onFailure: (failure) {
        _report(failure);
        return false;
      },
    );
  }

  /// Reporta un contenido.
  Future<bool> report({
    required String targetId,
    required String targetOwnerId,
    required ReportReason reason,
    String? details,
  }) async {
    final uid = _uid;
    if (uid == null) {
      _reportNoSession();
      return false;
    }

    final validation = validateReport(
      reporterId: uid,
      targetOwnerId: targetOwnerId,
      details: details,
    );
    if (validation case Failed<String?>(:final failure)) {
      _report(failure);
      return false;
    }

    final result = await guardResult(
      () => ref
          .read(reportRepositoryProvider)
          .report(
            Report(
              // Id determinístico: la misma persona no puede inflar el
              // contador reportando cien veces.
              id: Report.buildId(targetId: targetId, reporterId: uid),
              reporterId: uid,
              targetType: 'post',
              targetId: targetId,
              targetOwnerId: targetOwnerId,
              reason: reason,
              details: validation.valueOrNull,
              createdAt: DateTime.now().toUtc(),
            ),
          ),
    );

    return result.fold(
      onSuccess: (_) => true,
      onFailure: (failure) {
        _report(failure);
        return false;
      },
    );
  }

  /// Borra una publicación propia.
  Future<bool> deletePost(String postId) async {
    final result = await guardResult(
      () => ref.read(postRepositoryProvider).deletePost(postId),
    );
    return result.fold(
      onSuccess: (_) => true,
      onFailure: (failure) {
        _report(failure);
        return false;
      },
    );
  }

  /// Descarta el error mostrado.
  void clearError() {
    if (state.hasError) {
      state = const AsyncData<void>(null);
    }
  }

  Future<String?> _write(Future<Result<String>> Function() action) async {
    state = const AsyncLoading<void>();
    final result = await guardResult(action);
    return result.fold(
      onSuccess: (id) {
        state = const AsyncData<void>(null);
        return id;
      },
      onFailure: (failure) {
        _report(failure);
        return null;
      },
    );
  }

  void _report(Failure failure) {
    state = AsyncError<void>(failure, failure.stackTrace ?? StackTrace.empty);
  }

  void _reportNoSession() => _report(
    const AuthFailure(
      messageKey: 'failure.auth.sessionExpired',
      code: 'no-session',
    ),
  );
}

/// Controlador de las escrituras de la comunidad.
final NotifierProvider<CommunityController, AsyncValue<void>>
communityControllerProvider =
    NotifierProvider<CommunityController, AsyncValue<void>>(
      CommunityController.new,
      name: 'communityController',
    );
