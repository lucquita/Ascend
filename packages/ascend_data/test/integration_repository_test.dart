import 'dart:convert';

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Cliente sin reintentos, para que un test de fallo no espere el backoff.
AscendHttpClient _client(MockClient mock) => AscendHttpClient(
  client: mock,
  retryPolicy: const RetryPolicy(maxAttempts: 1),
);

MockClient _respond(String body, {int status = 200}) =>
    MockClient((_) async => http.Response(body, status));

const String _weatherOk = '''
{"daily":{"weather_code":[61],"temperature_2m_max":[18.4],
"precipitation_probability_max":[85]}}
''';

void main() {
  group('AscendHttpClient — la frontera de las APIs de terceros', () {
    test('un 200 con JSON válido devuelve el dato', () async {
      final result = await _client(_respond('{"a":1}')).getJson<int>(
        Uri.https('x.test', '/'),
        parse: (j) => (j! as Map)['a'] as int,
      );

      expect(result.valueOrNull, 1);
    });

    test('un 404 es NotFound y NO se reintenta', () async {
      // Reintentar un 404 no lo va a convertir en un 200: solo gasta batería y
      // datos de la persona.
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        return http.Response('{}', 404);
      });

      final result = await AscendHttpClient(
        client: mock,
      ).getJson<Object?>(Uri.https('x.test', '/'), parse: (j) => j);

      expect(result.failureOrNull, isA<NotFoundFailure>());
      expect(calls, 1);
    });

    test('un 500 se reintenta y termina en ServerFailure', () async {
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        return http.Response('{}', 500);
      });

      final result = await AscendHttpClient(
        client: mock,
        // initialDelay en cero para no esperar el backoff real en el test.
        // maxAttempts queda en su valor por defecto, que son 3.
        retryPolicy: const RetryPolicy(initialDelay: Duration.zero),
      ).getJson<Object?>(Uri.https('x.test', '/'), parse: (j) => j);

      expect(result.failureOrNull, isA<ServerFailure>());
      expect(calls, 3, reason: 'Un 5xx sí es recuperable');
    });

    test(
      'un 200 con HTML se rechaza: es un portal cautivo, no una respuesta',
      () async {
        // Es lo que devuelve el wifi de un aeropuerto o un hotel. Sin esta
        // comprobación el parseo fallaría con un error críptico.
        final result = await _client(
          _respond('<html><body>Iniciá sesión en la red</body></html>'),
        ).getJson<Object?>(Uri.https('x.test', '/'), parse: (j) => j);

        expect(result.failureOrNull, isA<ServerFailure>());
        expect(result.failureOrNull?.code, 'non-json-response');
      },
    );

    test('un cuerpo vacío también se rechaza', () async {
      final result = await _client(
        _respond(''),
      ).getJson<Object?>(Uri.https('x.test', '/'), parse: (j) => j);

      expect(result.failureOrNull, isA<ServerFailure>());
    });

    test('un JSON malformado no rompe: devuelve un fallo tipado', () async {
      final result = await _client(
        _respond('{esto no es json'),
      ).getJson<Object?>(Uri.https('x.test', '/'), parse: (j) => j);

      expect(result.failureOrNull, isA<ServerFailure>());
    });

    test(
      'si el parseo lanza, se degrada en vez de romper la pantalla',
      () async {
        // Pasa cuando la API cambia su contrato sin avisar.
        final result = await _client(_respond('{"a":1}')).getJson<int>(
          Uri.https('x.test', '/'),
          parse: (_) => throw StateError('la API cambió'),
        );

        expect(result.failureOrNull, isA<ServerFailure>());
        expect(result.failureOrNull?.code, 'unexpected-response');
      },
    );

    test('un 429 se mapea a cuota, no a error genérico', () async {
      final result = await _client(
        _respond('{}', status: 429),
      ).getJson<Object?>(Uri.https('x.test', '/'), parse: (j) => j);

      expect(result.failureOrNull, isA<QuotaFailure>());
    });

    test('sin conexión devuelve NetworkFailure', () async {
      final mock = MockClient(
        (_) async => throw http.ClientException('sin red'),
      );

      final result = await AscendHttpClient(
        client: mock,
        retryPolicy: const RetryPolicy(maxAttempts: 1),
      ).getJson<Object?>(Uri.https('x.test', '/'), parse: (j) => j);

      expect(result.failureOrNull, isA<NetworkFailure>());
    });
  });

  group('WeatherRepositoryImpl — Open-Meteo', () {
    test('mapea el pronóstico y desalienta salir con 85% de lluvia', () async {
      final repo = WeatherRepositoryImpl(client: _client(_respond(_weatherOk)));

      final result = await repo.forecastFor(latitude: -34.6, longitude: -58.4);
      final forecast = result.valueOrNull!;

      expect(forecast.roundedTemperature, 18);
      expect(forecast.precipitationProbability, 85);
      expect(forecast.condition, WeatherCondition.rain);
      expect(forecast.discouragesOutdoor, isTrue);
    });

    test('con probabilidad baja no desalienta', () async {
      // Avisar con 20% de lluvia enseña a ignorar el aviso, que es peor que no
      // darlo.
      final repo = WeatherRepositoryImpl(
        client: _client(
          _respond(
            '{"daily":{"weather_code":[1],"temperature_2m_max":[24.0],'
            '"precipitation_probability_max":[20]}}',
          ),
        ),
      );

      final forecast = (await repo.forecastFor(
        latitude: 0,
        longitude: 0,
      )).valueOrNull!;

      expect(forecast.discouragesOutdoor, isFalse);
      expect(forecast.condition, WeatherCondition.clear);
    });

    test('una tormenta desalienta aunque la probabilidad sea baja', () async {
      final repo = WeatherRepositoryImpl(
        client: _client(
          _respond(
            '{"daily":{"weather_code":[95],"temperature_2m_max":[28.0],'
            '"precipitation_probability_max":[30]}}',
          ),
        ),
      );

      expect(
        (await repo.forecastFor(
          latitude: 0,
          longitude: 0,
        )).valueOrNull!.discouragesOutdoor,
        isTrue,
      );
    });

    test('sin probabilidad de lluvia asume cero, no desalienta', () async {
      // Algunos modelos no devuelven el campo. Sin dato, no se desalienta.
      final repo = WeatherRepositoryImpl(
        client: _client(
          _respond(
            '{"daily":{"weather_code":[1],"temperature_2m_max":[22.0]}}',
          ),
        ),
      );

      final forecast = (await repo.forecastFor(
        latitude: 0,
        longitude: 0,
      )).valueOrNull!;

      expect(forecast.precipitationProbability, 0);
      expect(forecast.discouragesOutdoor, isFalse);
    });

    test(
      'un día sin datos devuelve fallo, no un pronóstico inventado',
      () async {
        final repo = WeatherRepositoryImpl(
          client: _client(
            _respond('{"daily":{"weather_code":[],"temperature_2m_max":[]}}'),
          ),
        );

        expect(
          (await repo.forecastFor(latitude: 0, longitude: 0)).failureOrNull,
          isA<ServerFailure>(),
        );
      },
    );
  });

  group('BookRepositoryImpl — Open Library', () {
    String booksJson(List<Map<String, Object?>> docs) =>
        jsonEncode(<String, Object?>{'docs': docs});

    test('convierte un resultado en una sugerencia usable', () async {
      final repo = BookRepositoryImpl(
        client: _client(
          _respond(
            booksJson(<Map<String, Object?>>[
              <String, Object?>{
                'title': 'El nombre del viento',
                'author_name': <String>['Patrick Rothfuss'],
                'first_publish_year': 2007,
                'number_of_pages_median': 662,
                'cover_i': 123,
              },
            ]),
          ),
        ),
      );

      final book = (await repo.search('nombre del viento')).valueOrNull!.single;

      expect(book.title, 'El nombre del viento');
      expect(book.author, 'Patrick Rothfuss');
      expect(book.pageCount, 662);
      expect(book.coverUrl, contains('123'));
      // La misión queda concreta: se sabe cuándo está cumplida.
      expect(book.missionTitle, contains('El nombre del viento'));
      expect(book.missionTitle, contains('Patrick Rothfuss'));
    });

    test(
      'descarta resultados sin título en vez de pintar filas vacías',
      () async {
        final repo = BookRepositoryImpl(
          client: _client(
            _respond(
              booksJson(<Map<String, Object?>>[
                <String, Object?>{'title': 'Válido'},
                <String, Object?>{'first_publish_year': 1999},
                <String, Object?>{'title': ''},
              ]),
            ),
          ),
        );

        expect((await repo.search('algo')).valueOrNull, hasLength(1));
      },
    );

    test(
      'una búsqueda sin resultados devuelve lista vacía, no un fallo',
      () async {
        // "No encontré nada" es una respuesta legítima; tratarla como error
        // mostraría una pantalla roja por buscar mal un título.
        final repo = BookRepositoryImpl(
          client: _client(_respond('{"docs":[]}')),
        );

        final result = await repo.search('kjhgfdsa');
        expect(result.isSuccess, isTrue);
        expect(result.valueOrNull, isEmpty);
      },
    );

    test('un libro sin autor igual arma un título de misión legible', () async {
      final repo = BookRepositoryImpl(
        client: _client(
          _respond(
            booksJson(<Map<String, Object?>>[
              <String, Object?>{'title': 'Anónimo'},
            ]),
          ),
        ),
      );

      final book = (await repo.search('anonimo')).valueOrNull!.single;
      expect(book.missionTitle, 'Leer "Anónimo"');
      expect(book.estimatedReadingMinutes, isNull);
    });
  });
}
