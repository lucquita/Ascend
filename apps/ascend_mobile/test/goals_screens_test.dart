import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/features/goals/presentation/screens/goal_detail_screen.dart';
import 'package:ascend_mobile/features/goals/presentation/screens/goal_form_screen.dart';
import 'package:ascend_mobile/features/goals/presentation/screens/goals_list_screen.dart';
import 'package:ascend_ui/ascend_ui.dart';
// El tipo Page existe en el dominio (paginación) y en Flutter (navegación).
// Acá se usa el del dominio, así que se oculta el de Flutter.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Repositorio de mentira: devuelve lo que le pidamos y anota lo que recibe.
class _FakeGoalRepository implements GoalRepository {
  List<Goal> goals = <Goal>[];
  Failure? listFailure;
  Failure? writeFailure;

  Goal? created;
  Goal? updated;
  String? deleted;
  ({String milestoneId, bool done})? toggled;

  @override
  Stream<Result<List<Goal>>> watchGoals({
    required String uid,
    GoalStatus? status,
    String? categoryId,
  }) {
    if (listFailure != null) {
      return Stream<Result<List<Goal>>>.value(Failed<List<Goal>>(listFailure!));
    }
    final filtered = status == null
        ? goals
        : goals.where((g) => g.status == status).toList();
    return Stream<Result<List<Goal>>>.value(Success<List<Goal>>(filtered));
  }

  @override
  Stream<Result<Goal>> watchGoal({
    required String uid,
    required String goalId,
  }) {
    final match = goals.where((g) => g.id == goalId).firstOrNull;
    return Stream<Result<Goal>>.value(
      match == null
          ? const Failed<Goal>(NotFoundFailure(code: 'goal-missing'))
          : Success<Goal>(match),
    );
  }

  @override
  Future<Result<Goal>> createGoal(Goal goal) async {
    if (writeFailure != null) {
      return Failed<Goal>(writeFailure!);
    }
    created = goal;
    return Success<Goal>(goal);
  }

  @override
  Future<Result<Goal>> createGoalWithMissions({
    required Goal goal,
    required List<Mission> missions,
  }) async => Success<Goal>(goal);

  @override
  Future<Result<void>> updateGoal(Goal goal) async {
    if (writeFailure != null) {
      return Failed<void>(writeFailure!);
    }
    updated = goal;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> updateStatus({
    required String uid,
    required String goalId,
    required GoalStatus status,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> deleteGoal({
    required String uid,
    required String goalId,
  }) async {
    if (writeFailure != null) {
      return Failed<void>(writeFailure!);
    }
    deleted = goalId;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> toggleMilestone({
    required String uid,
    required String goalId,
    required String milestoneId,
    required bool done,
  }) async {
    toggled = (milestoneId: milestoneId, done: done);
    return const Success<void>(null);
  }
}

/// Repositorio de misiones vacío.
///
/// El detalle del objetivo muestra sus misiones embebidas, así que necesita
/// este doble aunque estos tests no verifiquen misiones: sin él, la sección
/// intentaría hablar con Firestore de verdad.
class _EmptyMissionRepository implements MissionRepository {
  @override
  Stream<Result<List<Mission>>> watchByGoal({
    required String uid,
    required String goalId,
  }) => Stream<Result<List<Mission>>>.value(
    const Success<List<Mission>>(<Mission>[]),
  );

  @override
  Stream<Result<List<Mission>>> watchToday({
    required String uid,
    DateTime? day,
  }) => Stream<Result<List<Mission>>>.value(
    const Success<List<Mission>>(<Mission>[]),
  );

  @override
  Stream<Result<List<Mission>>> watchMissions({
    required String uid,
    MissionStatus? status,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    String? categoryId,
    String? goalId,
  }) => Stream<Result<List<Mission>>>.value(
    const Success<List<Mission>>(<Mission>[]),
  );

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

  @override
  Future<Result<Mission>> getMission({
    required String uid,
    required String missionId,
  }) async => const Failed<Mission>(NotFoundFailure(code: 'mission-missing'));

  @override
  Future<Result<Paginated<Mission>>> getHistory({
    required String uid,
    Object? cursor,
    int limit = 20,
  }) async => const Success<Paginated<Mission>>(Paginated<Mission>.empty());
}

class _FakeCategoryRepository implements CategoryRepository {
  @override
  Stream<Result<List<Category>>> watchCategories({bool onlyActive = true}) =>
      Stream<Result<List<Category>>>.value(
        const Success<List<Category>>(<Category>[
          Category(
            id: 'languages',
            names: <String, String>{'es': 'Idiomas'},
            icon: 'translate',
            colorHex: '#3B82F6',
          ),
          Category(
            id: 'fitness',
            names: <String, String>{'es': 'Fitness'},
            icon: 'fitness_center',
            colorHex: '#22C55E',
          ),
        ]),
      );

  @override
  Future<Result<Category>> getCategory(String id) async =>
      const Failed<Category>(NotFoundFailure(code: 'category-missing'));
}

final AppUser _user = AppUser(
  uid: 'u1',
  email: 'ana@ascend.app',
  displayName: 'Ana',
  handle: 'ana',
  createdAt: DateTime.utc(2026),
  emailVerified: true,
);

Goal _goal({
  String id = 'g1',
  String title = 'Aprender inglés',
  GoalStatus status = GoalStatus.active,
  GoalProgress progress = GoalProgress.empty,
  List<Milestone> milestones = const <Milestone>[],
}) => Goal(
  id: id,
  ownerId: 'u1',
  title: title,
  categoryId: 'languages',
  createdAt: DateTime.utc(2026, 8),
  status: status,
  progress: progress,
  milestones: milestones,
);

Widget _host(
  Widget child,
  _FakeGoalRepository goals,
  _FakeCategoryRepository categories,
) => _scope(
  MaterialApp(theme: AscendTheme.light, home: child),
  goals,
  categories,
);

/// Envuelve la app en un `ProviderScope` con los dobles enchufados.
///
/// El tipo `Override` no lo exporta `flutter_riverpod`, así que la lista se
/// construye acá dentro en lugar de devolverse desde una función aparte.
Widget _scope(
  Widget app,
  _FakeGoalRepository goals,
  _FakeCategoryRepository categories,
) => ProviderScope(
  overrides: [
    goalRepositoryProvider.overrideWithValue(goals),
    categoryRepositoryProvider.overrideWithValue(categories),
    missionRepositoryProvider.overrideWithValue(_EmptyMissionRepository()),
    authStateProvider.overrideWith((ref) => Stream<AppUser?>.value(_user)),
    // Se sustituye también el usuario ya resuelto. El formulario no observa
    // `authStateProvider`, así que sin esto el provider recién se inicializa
    // cuando el controlador lee la sesión al guardar, y en ese instante el
    // stream todavía no emitió: el alta fallaría con "sesión expirada".
    currentUserProvider.overrideWithValue(_user),
  ],
  child: app,
);

/// Host con un GoRouter real, para las pantallas que navegan al terminar.
///
/// El formulario hace `context.pop()` tras guardar. Montarlo suelto haría
/// fallar esa navegación con "No GoRouter found in context", que es ruido del
/// arnés y no un problema de la pantalla. Con una pila de dos rutas se puede
/// además verificar que efectivamente vuelve atrás.
Widget _routedHost(
  Widget child,
  _FakeGoalRepository goals,
  _FakeCategoryRepository categories,
) => _scope(
  MaterialApp.router(
    theme: AscendTheme.light,
    routerConfig: GoRouter(
      initialLocation: '/goals/new',
      routes: <RouteBase>[
        GoRoute(
          path: '/goals',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('volvió a la lista'))),
          routes: <RouteBase>[GoRoute(path: 'new', builder: (_, _) => child)],
        ),
      ],
    ),
  ),
  goals,
  categories,
);

/// Deja que los streams emitan y el árbol se reconstruya.
///
/// No se usa `pumpAndSettle`: los skeletons del design system tienen una
/// animación de shimmer infinita, así que "asentar" nunca ocurre y el test se
/// colgaría hasta el timeout.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 50));
}

/// Agranda la superficie de test para que el formulario entre entero.
///
/// El `ListView` del formulario solo construye los hijos dentro del viewport:
/// con la pantalla por defecto (800×600) el botón de guardar no existe en el
/// árbol de widgets y `find.text` no puede encontrarlo. No es un bug de la
/// pantalla —en un teléfono real se llega scrolleando—, es una limitación del
/// entorno de test.
void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakeGoalRepository goals;
  late _FakeCategoryRepository categories;

  setUp(() {
    goals = _FakeGoalRepository();
    categories = _FakeCategoryRepository();
  });

  group('Lista de objetivos', () {
    testWidgets(
      'sin objetivos muestra el estado vacío con su llamada a la acción',
      (tester) async {
        await tester.pumpWidget(
          _host(const GoalsListScreen(), goals, categories),
        );
        await _settle(tester);

        // Una lista vacía sin explicación es indistinguible de una lista rota.
        expect(find.text('Todavía no tenés objetivos'), findsOneWidget);
        expect(find.text('Crear mi primer objetivo'), findsOneWidget);
      },
    );

    testWidgets('muestra los objetivos con su progreso', (tester) async {
      goals.goals = <Goal>[
        _goal(
          progress: const GoalProgress(missionsTotal: 24, missionsCompleted: 9),
        ),
        _goal(id: 'g2', title: 'Correr 5k'),
      ];

      await tester.pumpWidget(
        _host(const GoalsListScreen(), goals, categories),
      );
      await _settle(tester);

      expect(find.text('Aprender inglés'), findsOneWidget);
      expect(find.text('Correr 5k'), findsOneWidget);
      expect(find.text('9 de 24 misiones'), findsOneWidget);
      // Un objetivo sin misiones dice qué le pasa en vez de mostrar 0 de 0.
      expect(find.text('Todavía sin misiones'), findsOneWidget);
    });

    testWidgets(
      'un fallo del stream se pinta como error, no como lista vacía',
      (tester) async {
        goals.listFailure = const NetworkFailure();

        await tester.pumpWidget(
          _host(const GoalsListScreen(), goals, categories),
        );
        await _settle(tester);

        expect(find.text('Sin conexión'), findsOneWidget);
        expect(find.text('Todavía no tenés objetivos'), findsNothing);
      },
    );

    testWidgets(
      'filtrar por estado cambia el vacío y ofrece quitar el filtro',
      (tester) async {
        goals.goals = <Goal>[_goal()];

        await tester.pumpWidget(
          _host(const GoalsListScreen(), goals, categories),
        );
        await _settle(tester);

        await tester.tap(find.text('Completado'));
        await _settle(tester);

        expect(find.text('Nada con esos filtros'), findsOneWidget);
        expect(find.text('Quitar filtros'), findsOneWidget);
      },
    );
  });

  group('Formulario de objetivo', () {
    testWidgets('crea un objetivo con los datos cargados', (tester) async {
      _useTallScreen(tester);
      await tester.pumpWidget(
        _routedHost(const GoalFormScreen(), goals, categories),
      );
      await _settle(tester);

      await tester.enterText(find.byType(TextField).first, 'Aprender alemán');
      await tester.tap(find.text('Idiomas'));
      await _settle(tester);

      await tester.tap(find.text('Crear objetivo'));
      await _settle(tester);
      await _settle(tester);

      expect(goals.created?.title, 'Aprender alemán');
      expect(goals.created?.categoryId, 'languages');
      // Guardar bien tiene que devolver a la pantalla anterior.
      expect(find.text('volvió a la lista'), findsOneWidget);
    });

    testWidgets('sin título no se escribe nada y se explica por qué', (
      tester,
    ) async {
      _useTallScreen(tester);
      await tester.pumpWidget(_host(const GoalFormScreen(), goals, categories));
      await _settle(tester);

      await tester.tap(find.text('Idiomas'));
      await _settle(tester);
      await tester.tap(find.text('Crear objetivo'));
      await _settle(tester);
      await _settle(tester);

      expect(goals.created, isNull);
      expect(find.text('Poné un título a tu objetivo.'), findsOneWidget);
    });

    testWidgets('sin categoría tampoco se escribe', (tester) async {
      _useTallScreen(tester);
      await tester.pumpWidget(_host(const GoalFormScreen(), goals, categories));
      await _settle(tester);

      await tester.enterText(find.byType(TextField).first, 'Correr 5k');
      await tester.tap(find.text('Crear objetivo'));
      await _settle(tester);
      await _settle(tester);

      expect(goals.created, isNull);
      expect(find.text('Elegí una categoría.'), findsOneWidget);
    });

    testWidgets(
      'un fallo de red al guardar se muestra y no cuelga la pantalla',
      (tester) async {
        goals.writeFailure = const NetworkFailure();
        _useTallScreen(tester);

        await tester.pumpWidget(
          _host(const GoalFormScreen(), goals, categories),
        );
        await _settle(tester);

        await tester.enterText(find.byType(TextField).first, 'Correr 5k');
        await tester.tap(find.text('Idiomas'));
        await _settle(tester);
        await tester.tap(find.text('Crear objetivo'));
        await _settle(tester);
        await _settle(tester);

        // En modo compacto `ErrorStateView` pinta el mensaje, no el título.
        expect(find.textContaining('No pudimos conectarnos'), findsOneWidget);
        // El botón vuelve a estar disponible: quedarse en carga para siempre es
        // el modo de fallo que no puede existir.
        expect(find.text('Crear objetivo'), findsOneWidget);
        expect(goals.created, isNull);
      },
    );
  });

  group('Detalle de objetivo', () {
    testWidgets('muestra los datos y las acciones del estado actual', (
      tester,
    ) async {
      goals.goals = <Goal>[
        _goal(
          progress: const GoalProgress(missionsTotal: 10, missionsCompleted: 5),
        ),
      ];

      _useTallScreen(tester);
      await tester.pumpWidget(
        _host(const GoalDetailScreen(goalId: 'g1'), goals, categories),
      );
      await _settle(tester);

      expect(find.text('Aprender inglés'), findsOneWidget);
      expect(find.text('5 de 10 completadas'), findsOneWidget);
      // Un objetivo activo se completa o se pausa; no se ofrece "retomar".
      expect(find.text('Marcar como completado'), findsOneWidget);
      expect(find.text('Pausar'), findsOneWidget);
    });

    testWidgets(
      'un objetivo que no existe muestra el error, no una pantalla vacía',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const GoalDetailScreen(goalId: 'inexistente'),
            goals,
            categories,
          ),
        );
        await _settle(tester);

        expect(find.text('No lo encontramos'), findsOneWidget);
      },
    );

    testWidgets('marcar un hito delega en el repositorio', (tester) async {
      goals.goals = <Goal>[
        _goal(
          milestones: const <Milestone>[
            Milestone(id: 'm1', title: 'Vocabulario base', order: 0),
          ],
        ),
      ];

      await tester.pumpWidget(
        _host(const GoalDetailScreen(goalId: 'g1'), goals, categories),
      );
      await _settle(tester);

      await tester.tap(find.byType(Checkbox));
      await _settle(tester);

      expect(goals.toggled?.milestoneId, 'm1');
      expect(goals.toggled?.done, isTrue);
    });

    testWidgets('borrar pide confirmación antes de tocar nada', (tester) async {
      goals.goals = <Goal>[_goal()];

      _useTallScreen(tester);
      await tester.pumpWidget(
        _host(const GoalDetailScreen(goalId: 'g1'), goals, categories),
      );
      await _settle(tester);

      await tester.tap(find.text('Eliminar objetivo'));
      await _settle(tester);

      expect(find.text('¿Eliminar este objetivo?'), findsOneWidget);
      // Todavía no se borró nada: solo se abrió el diálogo.
      expect(goals.deleted, isNull);

      await tester.tap(find.text('Cancelar'));
      await _settle(tester);
      expect(goals.deleted, isNull);
    });
  });
}
