import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/features/integrations/presentation/widgets/book_picker.dart';
import 'package:ascend_mobile/features/missions/presentation/screens/mission_detail_screen.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWeatherRepository implements WeatherRepository {
  Result<WeatherForecast>? next;
  int calls = 0;

  @override
  Future<Result<WeatherForecast>> forecastFor({
    required double latitude,
    required double longitude,
    DateTime? day,
  }) async {
    calls++;
    return next ?? const Failed<WeatherForecast>(NetworkFailure());
  }
}

class _FakeBookRepository implements BookRepository {
  List<BookSuggestion> books = const <BookSuggestion>[];
  Failure? failure;
  final List<String> queries = <String>[];

  @override
  Future<Result<List<BookSuggestion>>> search(
    String query, {
    int limit = 10,
  }) async {
    queries.add(query);
    return failure == null
        ? Success<List<BookSuggestion>>(books)
        : Failed<List<BookSuggestion>>(failure!);
  }
}

/// Solo devuelve la misión que se le pide; el detalle no usa nada más.
class _SingleMissionRepository extends _UnusedMissionRepository {
  _SingleMissionRepository(this.mission);

  final Mission mission;

  @override
  Future<Result<Mission>> getMission({
    required String uid,
    required String missionId,
  }) async => Success<Mission>(mission);
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
  String categoryId = 'fitness',
  Duration dueIn = const Duration(days: 2),
}) => Mission(
  id: 'm1',
  ownerId: 'u1',
  goalId: 'g1',
  title: 'Salir a correr 5 km',
  categoryId: categoryId,
  createdAt: DateTime.utc(2026, 8),
  dueDate: DateTime.now().add(dueIn),
);

WeatherForecast _forecast({int rain = 80}) => WeatherForecast(
  temperatureC: 14.2,
  precipitationProbability: rain,
  condition: WeatherCondition.rain,
  forDate: DateTime.now(),
);

/// Monta un widget con los dobles enchufados.
///
/// El tipo `Override` no lo exporta `flutter_riverpod`, así que la lista se
/// arma acá dentro en vez de devolverse desde una función aparte.
Widget _host(
  Widget child, {
  MissionRepository? missions,
  WeatherRepository? weather,
  BookRepository? books,
}) => ProviderScope(
  overrides: [
    missionRepositoryProvider.overrideWithValue(
      missions ?? _UnusedMissionRepository(),
    ),
    weatherRepositoryProvider.overrideWithValue(
      weather ?? _FakeWeatherRepository(),
    ),
    bookRepositoryProvider.overrideWithValue(books ?? _FakeBookRepository()),
    // El perfil aporta el huso horario del que sale la ubicación: sin él no se
    // consulta el clima y el aviso nunca aparecería.
    profileProvider.overrideWith(
      (ref) => Stream<Result<AppUser>>.value(Success<AppUser>(_user)),
    ),
    pendingUploadsProvider.overrideWith((ref) => Stream<int>.value(0)),
    authStateProvider.overrideWith((ref) => Stream<AppUser?>.value(_user)),
    currentUserProvider.overrideWithValue(_user),
  ],
  child: MaterialApp(theme: AscendTheme.light, home: child),
);

/// Deja que los futures y streams emitan sin esperar a que todo se asiente.
///
/// No se usa `pumpAndSettle`: los skeletons tienen un shimmer infinito, así que
/// "asentar" nunca ocurre y el test se colgaría hasta el timeout.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('Aviso de clima en el detalle de una misión', () {
    late _FakeWeatherRepository weather;

    setUp(() => weather = _FakeWeatherRepository());

    testWidgets('avisa cuando el pronóstico desalienta salir', (tester) async {
      _useTallScreen(tester);
      weather.next = Success<WeatherForecast>(_forecast(rain: 90));

      await tester.pumpWidget(
        _host(
          const MissionDetailScreen(missionId: 'm1'),
          missions: _SingleMissionRepository(_mission()),
          weather: weather,
        ),
      );
      await _settle(tester);

      expect(find.textContaining('90%'), findsOneWidget);
      expect(find.textContaining('14°'), findsOneWidget);
    });

    testWidgets('con buen clima no molesta con un aviso', (tester) async {
      _useTallScreen(tester);
      weather.next = Success<WeatherForecast>(_forecast(rain: 10));

      await tester.pumpWidget(
        _host(
          const MissionDetailScreen(missionId: 'm1'),
          missions: _SingleMissionRepository(_mission()),
          weather: weather,
        ),
      );
      await _settle(tester);

      expect(find.textContaining('probabilidad de lluvia'), findsNothing);
      // La misión sí se ve: el aviso ausente no se llevó puesta la pantalla.
      expect(find.text('Salir a correr 5 km'), findsOneWidget);
    });

    testWidgets('si la API falla la misión se muestra igual', (tester) async {
      // El clima es información de apoyo: que no responda no puede dejar la
      // pantalla cargando ni mostrar un error.
      _useTallScreen(tester);
      weather.next = const Failed<WeatherForecast>(TimeoutFailure());

      await tester.pumpWidget(
        _host(
          const MissionDetailScreen(missionId: 'm1'),
          missions: _SingleMissionRepository(_mission()),
          weather: weather,
        ),
      );
      await _settle(tester);

      expect(find.text('Salir a correr 5 km'), findsOneWidget);
      expect(find.text('Completar misión'), findsOneWidget);
      expect(find.textContaining('probabilidad de lluvia'), findsNothing);
    });

    testWidgets('una misión de lectura no gasta una llamada', (tester) async {
      _useTallScreen(tester);
      weather.next = Success<WeatherForecast>(_forecast());

      await tester.pumpWidget(
        _host(
          const MissionDetailScreen(missionId: 'm1'),
          missions: _SingleMissionRepository(_mission(categoryId: 'reading')),
          weather: weather,
        ),
      );
      await _settle(tester);

      expect(weather.calls, 0);
      expect(find.textContaining('probabilidad de lluvia'), findsNothing);
    });
  });

  group('Buscador de libros', () {
    late _FakeBookRepository books;

    setUp(() => books = _FakeBookRepository());

    /// Botón que abre la hoja y deja el elegido a la vista.
    Widget _opener() => Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final book = await showBookPicker(context);
              if (book != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('elegido: ${book.missionTitle}')),
                );
              }
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );

    testWidgets('con menos de tres letras no llama a la API', (tester) async {
      await tester.pumpWidget(_host(_opener(), books: books));
      await tester.tap(find.text('abrir'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'du');
      // El debounce por defecto son 350 ms.
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);

      expect(books.queries, isEmpty);
      expect(find.text('Escribí un título'), findsOneWidget);
    });

    testWidgets('busca y muestra los resultados', (tester) async {
      books.books = const <BookSuggestion>[
        BookSuggestion(
          title: 'Dune',
          author: 'Frank Herbert',
          firstPublishYear: 1965,
          pageCount: 600,
        ),
      ];

      await tester.pumpWidget(_host(_opener(), books: books));
      await tester.tap(find.text('abrir'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'dune');
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);

      expect(books.queries, <String>['dune']);
      expect(find.text('Dune'), findsOneWidget);
      expect(find.textContaining('Frank Herbert'), findsOneWidget);
    });

    testWidgets('al elegir un libro lo devuelve al formulario', (tester) async {
      books.books = const <BookSuggestion>[
        BookSuggestion(title: 'Dune', author: 'Frank Herbert'),
      ];

      await tester.pumpWidget(_host(_opener(), books: books));
      await tester.tap(find.text('abrir'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'dune');
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);

      await tester.tap(find.text('Dune'));
      await _settle(tester);

      expect(
        find.text('elegido: Leer "Dune", de Frank Herbert'),
        findsOneWidget,
      );
    });

    testWidgets('sin resultados lo dice, no muestra un error', (tester) async {
      // "No encontré nada" es una respuesta legítima; tratarla como error
      // mostraría una pantalla de fallo por buscar mal un título.
      await tester.pumpWidget(_host(_opener(), books: books));
      await tester.tap(find.text('abrir'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'kjhgfdsa');
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);

      expect(find.text('Sin resultados'), findsOneWidget);
    });

    testWidgets('si la API falla ofrece reintentar', (tester) async {
      books.failure = const NetworkFailure();

      await tester.pumpWidget(_host(_opener(), books: books));
      await tester.tap(find.text('abrir'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'dune');
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);

      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}

/// Base que falla si el detalle llama a algo que no debería.
///
/// Es deliberado que lance: un `Success` vacío escondería que la pantalla está
/// pidiendo datos de más.
class _UnusedMissionRepository implements MissionRepository {
  Never _unused() => throw StateError('El detalle no debería llamar a esto');

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

  @override
  Future<Result<Paginated<Mission>>> getHistory({
    required String uid,
    Object? cursor,
    int limit = 20,
  }) async => _unused();
}
