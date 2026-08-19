import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/remote/ascend_http_client.dart';
import 'package:ascend_domain/ascend_domain.dart';

/// Pronóstico desde Open-Meteo.
///
/// ## Por qué Open-Meteo y no otra
///
/// No pide API key ni registro, es gratuita para uso no comercial y no exige
/// tarjeta. Eso importa más de lo que parece: una integración que necesita una
/// clave que nadie cargó es una funcionalidad que no se puede demostrar.
///
/// ## Qué aporta al producto
///
/// Una misión de correr agendada para un día de tormenta se va a saltear. Saber
/// que llueve **antes** permite moverla y no romper la racha, que es el
/// mecanismo central de retención del producto.
class WeatherRepositoryImpl implements WeatherRepository {
  /// Crea el repositorio.
  const WeatherRepositoryImpl({required AscendHttpClient client})
    : _client = client;

  /// Host de la API. Sin key: la URL es todo lo que hace falta.
  static const String _host = 'api.open-meteo.com';

  final AscendHttpClient _client;

  @override
  Future<Result<WeatherForecast>> forecastFor({
    required double latitude,
    required double longitude,
    DateTime? day,
  }) {
    final target = (day ?? DateTime.now()).toUtc();
    final dayKey = AscendDateUtils.toDayKey(target);

    final uri = Uri.https(_host, '/v1/forecast', <String, String>{
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      // Se piden solo los tres campos que se usan. Traer el pronóstico completo
      // por hora sería mover cien veces más datos para mostrar una línea.
      'daily': 'weather_code,temperature_2m_max,precipitation_probability_max',
      'start_date': dayKey,
      'end_date': dayKey,
      'timezone': 'UTC',
    });

    return _client.getJson<WeatherForecast>(
      uri,
      parse: (json) => _parseForecast(json, fallbackDate: target),
    );
  }

  /// Lee la respuesta de Open-Meteo.
  ///
  /// Lanza si la forma no es la esperada; `AscendHttpClient` lo traduce a
  /// `ServerFailure`. Es lo correcto: si la API cambió su contrato, es un
  /// problema del servidor y no algo que el dispositivo pueda arreglar.
  static WeatherForecast _parseForecast(
    Object? json, {
    required DateTime fallbackDate,
  }) {
    final root = json! as Map<String, dynamic>;
    final daily = root['daily']! as Map<String, dynamic>;

    final codes = daily['weather_code']! as List<Object?>;
    final temps = daily['temperature_2m_max']! as List<Object?>;
    final rain = daily['precipitation_probability_max'] as List<Object?>?;

    if (codes.isEmpty || temps.isEmpty) {
      throw const FormatException('Open-Meteo devolvió un día sin datos.');
    }

    return WeatherForecast(
      temperatureC: (temps.first! as num).toDouble(),
      // La probabilidad de lluvia puede venir nula en algunos modelos. Cero es
      // el default correcto: sin dato, no se desalienta la actividad.
      precipitationProbability: rain == null || rain.isEmpty
          ? 0
          : ((rain.first as num?) ?? 0).round(),
      condition: WeatherCondition.fromWmoCode((codes.first! as num).toInt()),
      forDate: fallbackDate,
    );
  }
}

/// Búsqueda de libros contra Open Library.
///
/// ## Qué aporta al producto
///
/// "Leer más" no es una misión: no se sabe cuándo está cumplida. *"Leer «El
/// nombre del viento», de Patrick Rothfuss"* sí. La integración convierte un
/// objetivo vago en misiones verificables, que es literalmente la promesa de
/// Ascend.
///
/// Tampoco pide API key.
class BookRepositoryImpl implements BookRepository {
  /// Crea el repositorio.
  const BookRepositoryImpl({required AscendHttpClient client})
    : _client = client;

  static const String _host = 'openlibrary.org';
  static const String _coverHost = 'covers.openlibrary.org';

  final AscendHttpClient _client;

  @override
  Future<Result<List<BookSuggestion>>> search(String query, {int limit = 10}) {
    final uri = Uri.https(_host, '/search.json', <String, String>{
      'q': query,
      // `fields` acota la respuesta: sin esto, Open Library devuelve decenas de
      // campos por resultado y la búsqueda pesa megabytes en una red móvil.
      'fields':
          'title,author_name,first_publish_year,number_of_pages_median,cover_i',
      'limit': '$limit',
    });

    return _client.getJson<List<BookSuggestion>>(uri, parse: _parseBooks);
  }

  static List<BookSuggestion> _parseBooks(Object? json) {
    final root = json! as Map<String, dynamic>;
    final docs = root['docs'] as List<Object?>? ?? const <Object?>[];

    final books = <BookSuggestion>[];
    for (final doc in docs) {
      if (doc is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(doc);
      final title = map['title'];
      // Un resultado sin título no se puede mostrar ni convertir en misión: se
      // descarta en silencio en lugar de pintar una fila vacía.
      if (title is! String || title.isEmpty) {
        continue;
      }

      final authors = map['author_name'];
      final coverId = map['cover_i'];

      books.add(
        BookSuggestion(
          title: title,
          author: authors is List && authors.isNotEmpty
              ? authors.first?.toString()
              : null,
          firstPublishYear: (map['first_publish_year'] as num?)?.toInt(),
          pageCount: (map['number_of_pages_median'] as num?)?.toInt(),
          coverUrl: coverId is num
              ? Uri.https(_coverHost, '/b/id/$coverId-M.jpg').toString()
              : null,
        ),
      );
    }

    return List<BookSuggestion>.unmodifiable(books);
  }
}
