import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

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
  int calls = 0;

  @override
  Future<Result<List<BookSuggestion>>> search(
    String query, {
    int limit = 10,
  }) async {
    calls++;
    return Success<List<BookSuggestion>>(books);
  }
}

final DateTime _today = DateTime.utc(2026, 8, 14);

WeatherForecast _forecast({int rain = 10}) => WeatherForecast(
  temperatureC: 22,
  precipitationProbability: rain,
  condition: WeatherCondition.clear,
  forDate: _today,
);

void main() {
  group('needsWeatherCheck — solo se consulta si cambia una decisión', () {
    test('una misión de fitness con fecha próxima sí', () {
      expect(
        needsWeatherCheck(
          categoryId: 'fitness',
          dueDate: _today.add(const Duration(days: 2)),
          now: _today,
        ),
        isTrue,
      );
    });

    test('una misión de lectura no: llueva o no, se lee igual', () {
      expect(
        needsWeatherCheck(categoryId: 'reading', dueDate: _today, now: _today),
        isFalse,
      );
    });

    test('sin fecha no se consulta', () {
      // No hay momento sobre el que pronosticar.
      expect(
        needsWeatherCheck(categoryId: 'fitness', dueDate: null, now: _today),
        isFalse,
      );
    });

    test('más allá de siete días no se consulta', () {
      // El pronóstico deja de ser confiable y Open-Meteo tampoco lo ofrece:
      // pedirlo sería gastar una llamada para nada.
      expect(
        needsWeatherCheck(
          categoryId: 'fitness',
          dueDate: _today.add(const Duration(days: 8)),
          now: _today,
        ),
        isFalse,
      );
      expect(
        needsWeatherCheck(
          categoryId: 'fitness',
          dueDate: _today.add(const Duration(days: 7)),
          now: _today,
        ),
        isTrue,
      );
    });

    test('una fecha pasada no se consulta', () {
      expect(
        needsWeatherCheck(
          categoryId: 'fitness',
          dueDate: _today.subtract(const Duration(days: 1)),
          now: _today,
        ),
        isFalse,
      );
    });

    test('una categoría desconocida no se consulta', () {
      expect(
        needsWeatherCheck(
          categoryId: 'categoria_inventada',
          dueDate: _today,
          now: _today,
        ),
        isFalse,
      );
      expect(
        needsWeatherCheck(categoryId: null, dueDate: _today, now: _today),
        isFalse,
      );
    });
  });

  group('CheckMissionWeatherUseCase — el clima nunca bloquea una misión', () {
    late _FakeWeatherRepository weather;

    setUp(() => weather = _FakeWeatherRepository());

    test('devuelve el pronóstico cuando corresponde', () async {
      weather.next = Success<WeatherForecast>(_forecast(rain: 80));

      final result = await CheckMissionWeatherUseCase(weather).call(
        categoryId: 'fitness',
        dueDate: _today,
        latitude: -34.6,
        longitude: -58.4,
        now: _today,
      );

      expect(result?.discouragesOutdoor, isTrue);
    });

    test('si la API falla devuelve null, NO un error', () async {
      // El clima es información de apoyo. Bloquear una misión porque no se pudo
      // consultar el pronóstico sería absurdo.
      weather.next = const Failed<WeatherForecast>(TimeoutFailure());

      final result = await CheckMissionWeatherUseCase(weather).call(
        categoryId: 'fitness',
        dueDate: _today,
        latitude: 0,
        longitude: 0,
        now: _today,
      );

      expect(result, isNull);
    });

    test('no gasta una llamada si la misión no es al aire libre', () async {
      await CheckMissionWeatherUseCase(weather).call(
        categoryId: 'reading',
        dueDate: _today,
        latitude: 0,
        longitude: 0,
        now: _today,
      );

      expect(weather.calls, 0);
    });
  });

  group('SearchBooksUseCase', () {
    late _FakeBookRepository books;

    setUp(() => books = _FakeBookRepository());

    test('busca con tres caracteres o más', () async {
      books.books = const <BookSuggestion>[BookSuggestion(title: 'Dune')];

      final result = await SearchBooksUseCase(books).call('dune');

      expect(result.valueOrNull, hasLength(1));
      expect(books.calls, 1);
    });

    test('una consulta corta NO llega a la API', () async {
      // Una búsqueda de una letra devuelve miles de resultados irrelevantes y
      // hace trabajar de balde a un catálogo gratuito.
      final result = await SearchBooksUseCase(books).call('du');

      expect(result.failureOrNull?.messageKey, 'validation.search.tooShort');
      expect(books.calls, 0);
    });

    test('los espacios no cuentan como caracteres', () async {
      final result = await SearchBooksUseCase(books).call('  a  ');
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(books.calls, 0);
    });
  });

  group('BookSuggestion — de catálogo a misión concreta', () {
    test('el título de misión nombra el libro, no dice "leer más"', () {
      // Es la promesa del producto: una misión se sabe cuándo está cumplida.
      const book = BookSuggestion(title: 'Dune', author: 'Frank Herbert');
      expect(book.missionTitle, 'Leer "Dune", de Frank Herbert');
    });

    test('estima la duración a partir de las páginas', () {
      const book = BookSuggestion(title: 'Corto', pageCount: 120);
      // 120 páginas a 40 por hora = 3 horas = 180 minutos.
      expect(book.estimatedReadingMinutes, 180);
    });

    test('un libro enorme se acota al techo de una misión', () {
      // Un libro entero no es una misión sino un objetivo: proponerlo como una
      // tarea de veinte horas sería absurdo.
      const book = BookSuggestion(title: 'Enorme', pageCount: 5000);
      expect(book.estimatedReadingMinutes, 480);
    });

    test('sin páginas no se inventa una duración', () {
      expect(const BookSuggestion(title: 'X').estimatedReadingMinutes, isNull);
      expect(
        const BookSuggestion(title: 'X', pageCount: 0).estimatedReadingMinutes,
        isNull,
      );
    });

    test('la dificultad sale de la extensión', () {
      // Un libro de 800 páginas no es la misma misión que uno de 90.
      expect(
        difficultyForBook(const BookSuggestion(title: 'X', pageCount: 90)),
        MissionDifficulty.easy,
      );
      expect(
        difficultyForBook(const BookSuggestion(title: 'X', pageCount: 300)),
        MissionDifficulty.medium,
      );
      expect(
        difficultyForBook(const BookSuggestion(title: 'X', pageCount: 800)),
        MissionDifficulty.hard,
      );
      expect(
        difficultyForBook(const BookSuggestion(title: 'X')),
        MissionDifficulty.medium,
      );
    });
  });

  group('suggestsBooks — dónde tiene sentido ofrecer el catálogo', () {
    test('en lectura e idiomas sí', () {
      // Leer en el idioma que se está aprendiendo es de las misiones más
      // habituales de esa categoría.
      expect(suggestsBooks('reading'), isTrue);
      expect(suggestsBooks('languages'), isTrue);
    });

    test('en el resto no: sería un botón que nadie va a tocar', () {
      expect(suggestsBooks('fitness'), isFalse);
      expect(suggestsBooks('finance'), isFalse);
      expect(suggestsBooks(null), isFalse);
    });
  });

  group('WeatherCondition.fromWmoCode', () {
    test('traduce los códigos conocidos', () {
      expect(WeatherCondition.fromWmoCode(0), WeatherCondition.clear);
      expect(WeatherCondition.fromWmoCode(3), WeatherCondition.cloudy);
      expect(WeatherCondition.fromWmoCode(61), WeatherCondition.rain);
      expect(WeatherCondition.fromWmoCode(75), WeatherCondition.snow);
      expect(WeatherCondition.fromWmoCode(95), WeatherCondition.storm);
    });

    test('un código desconocido queda como desconocido, no inventa', () {
      // Un pronóstico equivocado es peor que uno ausente.
      expect(WeatherCondition.fromWmoCode(999), WeatherCondition.unknown);
    });
  });
}
