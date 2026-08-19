import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/features/missions/presentation/screens/mission_history_screen.dart';
import 'package:ascend_mobile/features/missions/presentation/screens/pick_goal_screen.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Repositorio de misiones que solo sabe paginar el historial.
class _HistoryRepository implements MissionRepository {
  final List<List<Mission>> pages = <List<Mission>>[];
  Failure? failure;
  int calls = 0;
  Object? lastCursor;

  @override
  Future<Result<Paginated<Mission>>> getHistory({
    required String uid,
    Object? cursor,
    int limit = 20,
  }) async {
    lastCursor = cursor;
    final index = calls;
    calls++;

    if (failure != null && index > 0) {
      return Failed<Paginated<Mission>>(failure!);
    }
    if (index >= pages.length) {
      return const Success<Paginated<Mission>>(Paginated<Mission>.empty());
    }
    return Success<Paginated<Mission>>(
      Paginated<Mission>(
        items: pages[index],
        cursor: 'cursor-$index',
        hasMore: index + 1 < pages.length,
      ),
    );
  }

  Never _unused() => throw StateError('El historial no debería llamar a esto');

  @override
  Stream<Result<List<Mission>>> watchByGoal({
    required String uid,
    required String goalId,
  }) => _unused();

  @override
  Stream<Result<List<Mission>>> watchToday({
    required String uid,
    DateTime? day,
  }) => _unused();

  @override
  Stream<Result<List<Mission>>> watchMissions({
    required String uid,
    MissionStatus? status,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    String? categoryId,
    String? goalId,
  }) => _unused();

  @override
  Future<Result<Mission>> createMission(Mission mission) async => _unused();

  @override
  Future<Result<void>> updateMission(Mission mission) async => _unused();

  @override
  Future<Result<void>> completeMission({
    required String uid,
    required String missionId,
    Evidence? evidence,
  }) async => _unused();

  @override
  Future<Result<void>> skipMission({
    required String uid,
    required String missionId,
    String? reason,
  }) async => _unused();

  @override
  Future<Result<void>> reorderMissions({
    required String uid,
    required List<String> orderedIds,
  }) async => _unused();

  @override
  Future<Result<void>> deleteMission({
    required String uid,
    required String missionId,
  }) async => _unused();

  @override
  Future<Result<Mission>> getMission({
    required String uid,
    required String missionId,
  }) async => _unused();
}

class _GoalsRepository implements GoalRepository {
  List<Goal> goals = const <Goal>[];
  Failure? failure;

  @override
  Stream<Result<List<Goal>>> watchGoals({
    required String uid,
    GoalStatus? status,
    String? categoryId,
  }) => Stream<Result<List<Goal>>>.value(
    failure != null ? Failed<List<Goal>>(failure!) : Success<List<Goal>>(goals),
  );

  Never _unused() => throw StateError('La elección no debería llamar a esto');

  @override
  Stream<Result<Goal>> watchGoal({
    required String uid,
    required String goalId,
  }) => _unused();

  @override
  Future<Result<Goal>> createGoal(Goal goal) async => _unused();

  @override
  Future<Result<Goal>> createGoalWithMissions({
    required Goal goal,
    required List<Mission> missions,
  }) async => _unused();

  @override
  Future<Result<void>> updateGoal(Goal goal) async => _unused();

  @override
  Future<Result<void>> updateStatus({
    required String uid,
    required String goalId,
    required GoalStatus status,
  }) async => _unused();

  @override
  Future<Result<void>> deleteGoal({
    required String uid,
    required String goalId,
  }) async => _unused();

  @override
  Future<Result<void>> toggleMilestone({
    required String uid,
    required String goalId,
    required String milestoneId,
    required bool done,
  }) async => _unused();
}

final AppUser _user = AppUser(
  uid: 'u1',
  email: 'ana@ascend.app',
  displayName: 'Ana',
  handle: 'ana',
  createdAt: DateTime.utc(2026),
  emailVerified: true,
);

Mission _mission({
  required String id,
  String title = 'Correr 5 km',
  MissionStatus status = MissionStatus.completed,
  int aura = 30,
}) => Mission(
  id: id,
  ownerId: 'u1',
  goalId: 'g1',
  title: title,
  goalTitle: 'Ponerme en forma',
  createdAt: DateTime.utc(2026, 8),
  status: status,
  auraReward: aura,
  completedAt: DateTime.now().subtract(const Duration(days: 1)),
);

Goal _goal({String id = 'g1', String title = 'Ponerme en forma'}) => Goal(
  id: id,
  ownerId: 'u1',
  title: title,
  categoryId: 'fitness',
  createdAt: DateTime.utc(2026),
);

Widget _host(
  Widget child, {
  MissionRepository? missions,
  GoalRepository? goals,
}) => ProviderScope(
  overrides: [
    if (missions != null) missionRepositoryProvider.overrideWithValue(missions),
    if (goals != null) goalRepositoryProvider.overrideWithValue(goals),
    authStateProvider.overrideWith((ref) => Stream<AppUser?>.value(_user)),
    currentUserProvider.overrideWithValue(_user),
  ],
  child: MaterialApp.router(
    theme: AscendTheme.light,
    routerConfig: GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => child),
        GoRoute(
          path: '/goals/:goalId/missions/new',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('formulario'))),
        ),
        GoRoute(
          path: '/goals/new',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('nuevo objetivo'))),
        ),
      ],
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('Historial de misiones', () {
    late _HistoryRepository missions;

    setUp(() => missions = _HistoryRepository());

    testWidgets('lista lo ya terminado', (tester) async {
      _useTallScreen(tester);
      missions.pages.add(<Mission>[_mission(id: 'm1')]);

      await tester.pumpWidget(
        _host(const MissionHistoryScreen(), missions: missions),
      );
      await _settle(tester);

      expect(find.text('Correr 5 km'), findsOneWidget);
      expect(find.text('+30'), findsOneWidget);
    });

    testWidgets('una misión salteada no muestra Aura', (tester) async {
      // Mostrar "+0" en una salteada parecería un castigo.
      _useTallScreen(tester);
      missions.pages.add(<Mission>[
        _mission(id: 'm1', status: MissionStatus.skipped, aura: 0),
      ]);

      await tester.pumpWidget(
        _host(const MissionHistoryScreen(), missions: missions),
      );
      await _settle(tester);

      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('sin historial explica qué va a aparecer', (tester) async {
      _useTallScreen(tester);

      await tester.pumpWidget(
        _host(const MissionHistoryScreen(), missions: missions),
      );
      await _settle(tester);

      expect(find.text('Todavía no terminaste ninguna'), findsOneWidget);
    });

    testWidgets('cargar más suma la página siguiente sin releer', (
      tester,
    ) async {
      _useTallScreen(tester);
      missions.pages
        ..add(<Mission>[_mission(id: 'm1', title: 'Primera')])
        ..add(<Mission>[_mission(id: 'm2', title: 'Segunda')]);

      await tester.pumpWidget(
        _host(const MissionHistoryScreen(), missions: missions),
      );
      await _settle(tester);

      expect(find.text('Segunda'), findsNothing);

      await tester.tap(find.text('Cargar más'));
      await _settle(tester);

      // Las dos a la vista: la página nueva se suma, no reemplaza.
      expect(find.text('Primera'), findsOneWidget);
      expect(find.text('Segunda'), findsOneWidget);
      // Y se pidió con cursor, no desde el principio.
      expect(missions.lastCursor, 'cursor-0');
    });

    testWidgets('sin más páginas lo dice en vez de dejar el botón', (
      tester,
    ) async {
      _useTallScreen(tester);
      missions.pages.add(<Mission>[_mission(id: 'm1')]);

      await tester.pumpWidget(
        _host(const MissionHistoryScreen(), missions: missions),
      );
      await _settle(tester);

      expect(find.text('Eso es todo.'), findsOneWidget);
      expect(find.text('Cargar más'), findsNothing);
    });

    testWidgets('un fallo al paginar NO borra lo ya traído', (tester) async {
      // Perder la página que se estaba leyendo por no poder traer la siguiente
      // sería peor que el error.
      _useTallScreen(tester);
      missions
        ..pages.add(<Mission>[_mission(id: 'm1', title: 'Primera')])
        ..pages.add(<Mission>[_mission(id: 'm2')])
        ..failure = const NetworkFailure();

      await tester.pumpWidget(
        _host(const MissionHistoryScreen(), missions: missions),
      );
      await _settle(tester);

      await tester.tap(find.text('Cargar más'));
      await _settle(tester);

      expect(find.text('Primera'), findsOneWidget);
      expect(find.byType(ErrorStateView), findsOneWidget);
    });
  });

  group('Elegir objetivo para una misión nueva', () {
    late _GoalsRepository goals;

    setUp(() => goals = _GoalsRepository());

    testWidgets('lista los objetivos y lleva al formulario', (tester) async {
      _useTallScreen(tester);
      goals.goals = <Goal>[_goal()];

      await tester.pumpWidget(_host(const PickGoalScreen(), goals: goals));
      await _settle(tester);

      await tester.tap(find.text('Ponerme en forma'));
      await _settle(tester);

      expect(find.text('formulario'), findsOneWidget);
    });

    testWidgets('sin objetivos ofrece crear uno, no deja sin salida', (
      tester,
    ) async {
      // Es el callejón que cerraba esta pantalla: el "+" de la app llevaba a
      // un placeholder.
      _useTallScreen(tester);

      await tester.pumpWidget(_host(const PickGoalScreen(), goals: goals));
      await _settle(tester);

      expect(find.text('Todavía no tenés objetivos'), findsOneWidget);

      await tester.tap(find.text('Crear un objetivo'));
      await _settle(tester);

      expect(find.text('nuevo objetivo'), findsOneWidget);
    });

    testWidgets('un fallo ofrece reintentar', (tester) async {
      _useTallScreen(tester);
      goals.failure = const NetworkFailure();

      await tester.pumpWidget(_host(const PickGoalScreen(), goals: goals));
      await _settle(tester);

      expect(find.byType(ErrorStateView), findsOneWidget);
    });
  });
}
