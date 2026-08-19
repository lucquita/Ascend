import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/features/community/presentation/screens/create_post_screen.dart';
import 'package:ascend_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:ascend_ui/ascend_ui.dart';
// El tipo Page existe en el dominio (paginación) y en Flutter (navegación).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakePostRepository implements PostRepository {
  List<Post> posts = <Post>[];
  Failure? feedFailure;
  Post? created;
  ({String postId, bool liked})? lastLike;

  @override
  Future<Result<Paginated<Post>>> getFeed({
    Object? cursor,
    int limit = 20,
    String? categoryId,
  }) async {
    if (feedFailure != null) {
      return Failed<Paginated<Post>>(feedFailure!);
    }
    return Success<Paginated<Post>>(Paginated<Post>(items: posts));
  }

  @override
  Future<Result<Paginated<Post>>> getByAuthor({
    required String authorId,
    Object? cursor,
    int limit = 20,
  }) async => Success<Paginated<Post>>(Paginated<Post>(items: posts));

  @override
  Stream<Result<Post>> watchPost(String postId) {
    final match = posts.where((p) => p.id == postId).firstOrNull;
    return Stream<Result<Post>>.value(
      match == null
          ? const Failed<Post>(NotFoundFailure(code: 'post-missing'))
          : Success<Post>(match),
    );
  }

  @override
  Future<Result<Post>> createPost(Post post) async {
    created = post;
    return Success<Post>(post);
  }

  @override
  Future<Result<void>> updateText({
    required String postId,
    required String text,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> deletePost(String postId) async =>
      const Success<void>(null);

  @override
  Future<Result<void>> setLike({
    required String postId,
    required String uid,
    required bool liked,
  }) async {
    lastLike = (postId: postId, liked: liked);
    return const Success<void>(null);
  }

  @override
  Future<Result<bool>> hasLiked({
    required String postId,
    required String uid,
  }) async => const Success<bool>(false);
}

class _EmptyMissionRepository implements MissionRepository {
  @override
  Future<Result<Paginated<Mission>>> getHistory({
    required String uid,
    Object? cursor,
    int limit = 20,
  }) async => const Success<Paginated<Mission>>(Paginated<Mission>.empty());

  @override
  Stream<Result<List<Mission>>> watchToday({
    required String uid,
    DateTime? day,
  }) => const Stream<Result<List<Mission>>>.empty();

  @override
  Stream<Result<List<Mission>>> watchByGoal({
    required String uid,
    required String goalId,
  }) => const Stream<Result<List<Mission>>>.empty();

  @override
  Stream<Result<List<Mission>>> watchMissions({
    required String uid,
    MissionStatus? status,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    String? categoryId,
    String? goalId,
  }) => const Stream<Result<List<Mission>>>.empty();

  @override
  Future<Result<Mission>> getMission({
    required String uid,
    required String missionId,
  }) async => const Failed<Mission>(NotFoundFailure(code: 'mission-missing'));

  @override
  Future<Result<Mission>> createMission(Mission mission) async =>
      Success<Mission>(mission);

  @override
  Future<Result<void>> updateMission(Mission mission) async =>
      const Success<void>(null);

  @override
  Future<Result<void>> completeMission({
    required String uid,
    required String missionId,
    Evidence? evidence,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> skipMission({
    required String uid,
    required String missionId,
    String? reason,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> reorderMissions({
    required String uid,
    required List<String> orderedIds,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> deleteMission({
    required String uid,
    required String missionId,
  }) async => const Success<void>(null);
}

final AppUser _user = AppUser(
  uid: 'u1',
  email: 'ana@ascend.app',
  displayName: 'Ana',
  handle: 'ana',
  createdAt: DateTime.utc(2026),
  emailVerified: true,
);

Post _post({
  String id = 'p1',
  String authorId = 'u2',
  String text = 'Primera semana completa',
  PostType type = PostType.reflection,
  PostSource? source,
  int likes = 3,
}) => Post(
  id: id,
  authorId: authorId,
  type: type,
  text: text,
  createdAt: DateTime.utc(2026, 8, 14),
  author: const PostAuthor(displayName: 'Bruno', handle: 'bruno', level: 4),
  source: source,
  counters: PostCounters(likes: likes),
);

Widget _host(Widget child, _FakePostRepository posts) => ProviderScope(
  overrides: [
    postRepositoryProvider.overrideWithValue(posts),
    missionRepositoryProvider.overrideWithValue(_EmptyMissionRepository()),
    authStateProvider.overrideWith((ref) => Stream<AppUser?>.value(_user)),
    currentUserProvider.overrideWithValue(_user),
  ],
  child: MaterialApp(theme: AscendTheme.light, home: child),
);

/// Host con un GoRouter real, para las pantallas que navegan al terminar.
///
/// `CreatePostScreen` hace `context.pop()` tras publicar. Montarla suelta haría
/// fallar esa navegación con "No GoRouter found in context", que es ruido del
/// arnés y no un problema de la pantalla.
Widget _routedHost(Widget child, _FakePostRepository posts) => ProviderScope(
  overrides: [
    postRepositoryProvider.overrideWithValue(posts),
    missionRepositoryProvider.overrideWithValue(_EmptyMissionRepository()),
    authStateProvider.overrideWith((ref) => Stream<AppUser?>.value(_user)),
    currentUserProvider.overrideWithValue(_user),
  ],
  child: MaterialApp.router(
    theme: AscendTheme.light,
    routerConfig: GoRouter(
      initialLocation: '/community/create',
      routes: <RouteBase>[
        GoRoute(
          path: '/community',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('volvió al feed'))),
          routes: <RouteBase>[
            GoRoute(path: 'create', builder: (_, _) => child),
          ],
        ),
      ],
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  // El feed lo carga un `AsyncNotifier`, así que hace falta drenar varias
  // rondas de microtareas antes de que el primer estado llegue al árbol.
  for (var i = 0; i < 12; i++) {
    await tester.pump();
    await tester.pump(Duration.zero);
  }
  await tester.pump(const Duration(milliseconds: 50));
}

void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakePostRepository posts;

  setUp(() => posts = _FakePostRepository());

  group('Feed', () {
    testWidgets('sin publicaciones explica la premisa del producto', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const FeedScreen(), posts));
      await _settle(tester);

      // El vacío no dice "no hay nada": dice para qué sirve el feed.
      expect(find.text('El feed está tranquilo'), findsOneWidget);
      expect(
        find.textContaining('solo aparecen logros reales'),
        findsOneWidget,
      );
    });

    testWidgets('muestra las publicaciones con su autor y contadores', (
      tester,
    ) async {
      posts.posts = <Post>[_post(), _post(id: 'p2', text: 'Segundo día')];

      await tester.pumpWidget(_host(const FeedScreen(), posts));
      await _settle(tester);

      expect(find.text('Primera semana completa'), findsOneWidget);
      expect(find.text('Segundo día'), findsOneWidget);
      expect(find.text('Bruno'), findsNWidgets(2));
      expect(find.text('Nv. 4'), findsNWidgets(2));
    });

    testWidgets('un logro muestra la misión que lo respalda', (tester) async {
      posts.posts = <Post>[
        _post(
          type: PostType.missionCompleted,
          source: const PostSource(
            goalId: 'g1',
            goalTitle: 'Aprender inglés',
            missionId: 'm1',
            missionTitle: 'Ver un capítulo',
            auraEarned: 25,
          ),
        ),
      ];

      await tester.pumpWidget(_host(const FeedScreen(), posts));
      await _settle(tester);

      expect(find.text('completó una misión'), findsOneWidget);
      expect(find.text('Ver un capítulo'), findsOneWidget);
      expect(find.text('Aprender inglés'), findsOneWidget);
    });

    testWidgets('un fallo se pinta como error, no como feed vacío', (
      tester,
    ) async {
      posts.feedFailure = const NetworkFailure();

      await tester.pumpWidget(_host(const FeedScreen(), posts));
      await _settle(tester);

      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(find.text('El feed está tranquilo'), findsNothing);
    });

    testWidgets('el like se aplica de forma optimista', (tester) async {
      // El contador real lo mantiene un trigger y tarda un instante. Sin el
      // ajuste local, tocar el corazón no haría nada visible y la gente lo
      // tocaría dos veces.
      posts.posts = <Post>[_post()];

      await tester.pumpWidget(_host(const FeedScreen(), posts));
      await _settle(tester);

      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await _settle(tester);

      expect(find.text('4'), findsOneWidget);
      expect(posts.lastLike?.liked, isTrue);
      expect(posts.lastLike?.postId, 'p1');
    });
  });

  group('Publicar', () {
    testWidgets('una reflexión vacía no se publica y se explica por qué', (
      tester,
    ) async {
      _useTallScreen(tester);
      await tester.pumpWidget(_host(const CreatePostScreen(), posts));
      await _settle(tester);

      await tester.tap(find.byType(AscendButton));
      await _settle(tester);
      await _settle(tester);

      expect(posts.created, isNull);
      expect(find.textContaining('Escribí algo'), findsOneWidget);
    });

    testWidgets('publica una reflexión válida', (tester) async {
      _useTallScreen(tester);
      await tester.pumpWidget(_routedHost(const CreatePostScreen(), posts));
      await _settle(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'Hoy me costó, pero seguí',
      );
      await tester.tap(find.byType(AscendButton));
      await _settle(tester);
      await _settle(tester);

      expect(posts.created?.text, 'Hoy me costó, pero seguí');
      expect(posts.created?.type, PostType.reflection);
      // Una reflexión no lleva referencia a ningún logro.
      expect(posts.created?.source, isNull);
    });

    testWidgets('sin misiones completadas avisa que solo puede reflexionar', (
      tester,
    ) async {
      _useTallScreen(tester);
      await tester.pumpWidget(_routedHost(const CreatePostScreen(), posts));
      await _settle(tester);

      expect(
        find.textContaining('Todavía no completaste ninguna misión'),
        findsOneWidget,
      );
    });
  });
}
