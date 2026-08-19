/// Integraciones externas que aportan valor al producto.
///
/// Las dos elegidas son **gratuitas y sin API key**: funcionan en la demo sin
/// configuración previa, a diferencia de Gemini y Storage. Eso no es casualidad
/// sino un criterio de selección: una integración que exige una clave que nadie
/// cargó es una funcionalidad que no se puede mostrar.
///
/// - **Open-Meteo** — el clima decide si una misión al aire libre se puede
///   hacer. Avisar antes evita que la racha se rompa por lluvia.
/// - **Open Library** — un objetivo de lectura se vuelve concreto cuando la
///   misión dice *qué* libro leer, no "leer más".
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/enums/enums.dart';
import 'package:meta/meta.dart';

/// Condición general del clima.
enum WeatherCondition {
  /// Despejado.
  clear('clear'),

  /// Nublado.
  cloudy('cloudy'),

  /// Lluvia.
  rain('rain'),

  /// Nieve.
  snow('snow'),

  /// Tormenta.
  storm('storm'),

  /// Desconocido.
  unknown('unknown');

  const WeatherCondition(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Traduce el código WMO que devuelve Open-Meteo.
  ///
  /// Ante un código no contemplado devuelve [unknown] en vez de inventar: un
  /// pronóstico equivocado es peor que uno ausente.
  static WeatherCondition fromWmoCode(int code) => switch (code) {
    0 || 1 => WeatherCondition.clear,
    2 || 3 || 45 || 48 => WeatherCondition.cloudy,
    >= 51 && <= 67 => WeatherCondition.rain,
    >= 71 && <= 77 => WeatherCondition.snow,
    >= 80 && <= 82 => WeatherCondition.rain,
    >= 95 && <= 99 => WeatherCondition.storm,
    _ => WeatherCondition.unknown,
  };
}

/// Pronóstico para un momento y lugar.
@immutable
class WeatherForecast {
  /// Crea el pronóstico.
  const WeatherForecast({
    required this.temperatureC,
    required this.precipitationProbability,
    required this.condition,
    required this.forDate,
  });

  /// Temperatura en grados Celsius.
  final double temperatureC;

  /// Probabilidad de precipitación, de 0 a 100.
  final int precipitationProbability;

  /// Condición general.
  final WeatherCondition condition;

  /// Día al que corresponde.
  final DateTime forDate;

  /// `true` si conviene reprogramar una actividad al aire libre.
  ///
  /// El umbral es 60%: por debajo, avisar sería alarmismo y la gente aprende a
  /// ignorar el aviso, que termina siendo peor que no darlo.
  bool get discouragesOutdoor =>
      precipitationProbability >= 60 || condition == WeatherCondition.storm;

  /// Temperatura redondeada, para mostrar.
  int get roundedTemperature => temperatureC.round();
}

/// Libro sugerido por el catálogo abierto.
@immutable
class BookSuggestion {
  /// Crea la sugerencia.
  const BookSuggestion({
    required this.title,
    this.author,
    this.firstPublishYear,
    this.pageCount,
    this.coverUrl,
  });

  /// Título.
  final String title;

  /// Autor principal.
  final String? author;

  /// Año de la primera edición.
  final int? firstPublishYear;

  /// Cantidad de páginas, si el catálogo la conoce.
  final int? pageCount;

  /// Portada.
  final String? coverUrl;

  /// Texto listo para el título de una misión.
  String get missionTitle =>
      author == null ? 'Leer "$title"' : 'Leer "$title", de $author';

  /// Duración estimada de lectura, en minutos.
  ///
  /// A 40 páginas por hora, un ritmo conservador. Se acota a la duración máxima
  /// de una misión: un libro entero no es una misión sino un objetivo, y
  /// proponerlo como una tarea de veinte horas sería absurdo.
  int? get estimatedReadingMinutes {
    final pages = pageCount;
    if (pages == null || pages <= 0) {
      return null;
    }
    return ((pages / 40) * 60).round().clamp(15, 480);
  }
}

/// Clima, para decidir si una misión al aire libre se puede hacer.
abstract interface class WeatherRepository {
  /// Pronóstico de un día para una ubicación.
  Future<Result<WeatherForecast>> forecastFor({
    required double latitude,
    required double longitude,
    DateTime? day,
  });
}

/// Catálogo abierto de libros.
abstract interface class BookRepository {
  /// Busca libros por texto libre.
  Future<Result<List<BookSuggestion>>> search(String query, {int limit = 10});
}

/// Categorías cuyas misiones suelen hacerse al aire libre.
const Set<String> kOutdoorCategories = <String>{'fitness', 'travel'};

/// Categorías donde proponer un libro concreto tiene sentido.
///
/// `languages` entra además de `reading` porque leer en el idioma que se está
/// aprendiendo es una de las misiones más habituales de esa categoría.
const Set<String> kBookCategories = <String>{'reading', 'languages'};

/// `true` si conviene ofrecer el buscador de libros para esa categoría.
///
/// Ofrecerlo en todas las categorías ensuciaría el formulario de quien está
/// creando una misión de gimnasio con un botón que nunca va a tocar.
bool suggestsBooks(String? categoryId) =>
    categoryId != null && kBookCategories.contains(categoryId);

/// Decide si conviene consultar el clima para una misión.
///
/// Se consulta **solo** cuando el resultado puede cambiar una decisión: una
/// misión de lectura no mejora por saber que llueve, y cada consulta es una
/// llamada de red que se paga en batería y en datos.
bool needsWeatherCheck({
  required String? categoryId,
  required DateTime? dueDate,
  DateTime? now,
}) {
  if (categoryId == null || !kOutdoorCategories.contains(categoryId)) {
    return false;
  }
  final due = dueDate;
  if (due == null) {
    return false;
  }
  // Más allá de siete días el pronóstico deja de ser confiable, y Open-Meteo
  // tampoco lo ofrece: pedirlo sería gastar una llamada para nada.
  final days = AscendDateUtils.daysBetween(now ?? DateTime.now(), due);
  return days >= 0 && days <= 7;
}

/// Consulta el clima de una misión al aire libre.
class CheckMissionWeatherUseCase {
  /// Crea el caso de uso.
  const CheckMissionWeatherUseCase(this._weather);

  final WeatherRepository _weather;

  /// Devuelve el pronóstico, o `null` si no corresponde consultarlo.
  ///
  /// **Nunca propaga un fallo a la pantalla.** El clima es información de
  /// apoyo: si la API no responde, la misión se hace igual y simplemente no se
  /// muestra nada. Bloquear una misión porque no se pudo consultar el
  /// pronóstico sería absurdo.
  Future<WeatherForecast?> call({
    required String? categoryId,
    required DateTime? dueDate,
    required double latitude,
    required double longitude,
    DateTime? now,
  }) async {
    if (!needsWeatherCheck(
      categoryId: categoryId,
      dueDate: dueDate,
      now: now,
    )) {
      return null;
    }

    final result = await _weather.forecastFor(
      latitude: latitude,
      longitude: longitude,
      day: dueDate,
    );
    return result.valueOrNull;
  }
}

/// Busca libros para convertirlos en misiones concretas.
class SearchBooksUseCase {
  /// Crea el caso de uso.
  const SearchBooksUseCase(this._books);

  final BookRepository _books;

  /// Busca por texto libre.
  ///
  /// Exige al menos tres caracteres: una búsqueda de una letra devuelve miles
  /// de resultados irrelevantes y hace trabajar de balde al servidor de un
  /// catálogo gratuito.
  Future<Result<List<BookSuggestion>>> call(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      return const Failed<List<BookSuggestion>>(
        ValidationFailure(
          messageKey: 'validation.search.tooShort',
          field: 'query',
        ),
      );
    }
    return _books.search(trimmed);
  }
}

/// Dificultad que le corresponde a un libro según su extensión.
///
/// Un libro de 800 páginas no es la misma misión que uno de 90, y darles la
/// misma recompensa sería injusto con quien eligió el largo.
MissionDifficulty difficultyForBook(BookSuggestion book) {
  final pages = book.pageCount;
  if (pages == null) {
    return MissionDifficulty.medium;
  }
  if (pages <= 150) {
    return MissionDifficulty.easy;
  }
  if (pages <= 400) {
    return MissionDifficulty.medium;
  }
  return MissionDifficulty.hard;
}

/// Coordenadas aproximadas de una ciudad.
@immutable
class Coordinates {
  /// Crea las coordenadas.
  const Coordinates(this.latitude, this.longitude);

  /// Latitud.
  final double latitude;

  /// Longitud.
  final double longitude;
}

/// Ubicación aproximada a partir del huso horario del perfil.
///
/// ## Por qué no se usa el GPS
///
/// Pedir permiso de ubicación para decir si va a llover es desproporcionado: la
/// mitad de la gente lo niega y la funcionalidad muere ahí. El huso horario ya
/// está en el perfil, no requiere permiso, y da precisión de ciudad, que es
/// exactamente la que necesita un pronóstico diario.
///
/// Ante un huso desconocido devuelve `null`: sin ubicación no se consulta el
/// clima, y eso es preferible a mostrar el pronóstico de otro continente.
Coordinates? coordinatesForTimezone(String? timezone) =>
    timezone == null ? null : _timezoneCoordinates[timezone];

const Map<String, Coordinates> _timezoneCoordinates = <String, Coordinates>{
  'America/Argentina/Buenos_Aires': Coordinates(-34.61, -58.38),
  'America/Argentina/Cordoba': Coordinates(-31.42, -64.18),
  'America/Argentina/Mendoza': Coordinates(-32.89, -68.84),
  'America/Argentina/Salta': Coordinates(-24.79, -65.41),
  'America/Montevideo': Coordinates(-34.90, -56.16),
  'America/Santiago': Coordinates(-33.45, -70.67),
  'America/Sao_Paulo': Coordinates(-23.55, -46.63),
  'America/Bogota': Coordinates(4.71, -74.07),
  'America/Lima': Coordinates(-12.05, -77.04),
  'America/Mexico_City': Coordinates(19.43, -99.13),
  'Europe/Madrid': Coordinates(40.42, -3.70),
  'Europe/London': Coordinates(51.51, -0.13),
};
