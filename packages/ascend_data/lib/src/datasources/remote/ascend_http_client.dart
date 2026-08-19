import 'dart:async';
import 'dart:convert';

import 'package:ascend_core/ascend_core.dart';
import 'package:http/http.dart' as http;

/// Cliente HTTP compartido por las integraciones externas.
///
/// Es la frontera de las APIs de terceros, igual que `ErrorMapper` lo es de
/// Firebase: **ninguna excepción de red cruza esta clase**. Todo sale como
/// `Result<T>`.
///
/// ## Qué resuelve, más allá de hacer un GET
///
/// - **Timeout explícito.** Sin él, una API lenta deja la pantalla colgada
///   hasta el timeout por defecto del sistema, que puede ser de minutos.
/// - **Reintento con backoff**, reutilizando `RetryPolicy` del core. Solo para
///   fallos recuperables: reintentar un 404 gasta batería y datos.
/// - **Validación del cuerpo.** Un 200 con HTML —típico de un portal cautivo de
///   wifi— no es una respuesta válida aunque el código lo diga.
/// - **Logging seguro.** Se registran host, ruta y código; **nunca la URL
///   completa ni el cuerpo**, porque los parámetros pueden llevar ubicación o
///   términos de búsqueda de la persona.
class AscendHttpClient {
  /// Crea el cliente.
  const AscendHttpClient({
    required http.Client client,
    this.timeout = const Duration(seconds: 10),
    this.retryPolicy = RetryPolicy.read,
  }) : _client = client;

  static const AscendLogger _logger = AscendLogger('http');

  final http.Client _client;

  /// Cuánto se espera cada intento.
  final Duration timeout;

  /// Política de reintentos.
  final RetryPolicy retryPolicy;

  /// Hace un GET y decodifica el JSON con [parse].
  ///
  /// [parse] recibe el JSON ya decodificado y devuelve la entidad del dominio.
  /// Si lanza, se traduce a `ServerFailure`: una API que cambió su forma es un
  /// problema del servidor, no del dispositivo.
  Future<Result<T>> getJson<T>(
    Uri uri, {
    required T Function(Object? json) parse,
    Map<String, String>? headers,
  }) =>
      retryPolicy.execute(() => _getOnce(uri, parse: parse, headers: headers));

  Future<Result<T>> _getOnce<T>(
    Uri uri, {
    required T Function(Object? json) parse,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              ...?headers,
            },
          )
          .timeout(timeout);

      final failure = _failureForStatus(response.statusCode, uri);
      if (failure != null) {
        return Failed<T>(failure);
      }

      // Un 200 con HTML es lo que devuelve el portal cautivo de un wifi de
      // aeropuerto. Sin esta comprobación el parseo fallaría con un error
      // críptico en vez de decir "no hay conexión real".
      final body = response.body.trimLeft();
      if (body.isEmpty || body.startsWith('<')) {
        _log(uri, response.statusCode, 'cuerpo no-JSON');
        return Failed<T>(const ServerFailure(code: 'non-json-response'));
      }

      return Success<T>(parse(jsonDecode(body)));
    } on TimeoutException {
      _log(uri, null, 'timeout');
      return Failed<T>(const TimeoutFailure());
    } on http.ClientException {
      _log(uri, null, 'sin conexión');
      return Failed<T>(const NetworkFailure());
    } on FormatException {
      _log(uri, null, 'JSON malformado');
      return Failed<T>(const ServerFailure(code: 'malformed-json'));
    } on Object catch (error, stackTrace) {
      // Incluye los errores que lance `parse`: si la API cambió su contrato, se
      // degrada con un fallo tipado en vez de romper la pantalla.
      _logger.warning(
        'Fallo al procesar una respuesta externa',
        error: error,
        stackTrace: stackTrace,
        context: <String, Object?>{'host': uri.host, 'path': uri.path},
      );
      return Failed<T>(const ServerFailure(code: 'unexpected-response'));
    }
  }

  /// Traduce el código HTTP a un fallo del dominio.
  ///
  /// Distingue **recuperable** de **definitivo**: `RetryPolicy` solo reintenta
  /// los primeros. Reintentar un 404 no lo va a convertir en un 200.
  static Failure? _failureForStatus(int status, Uri uri) {
    if (status >= 200 && status < 300) {
      return null;
    }
    return switch (status) {
      404 => NotFoundFailure(code: 'http-$status'),
      // 429 es recuperable, pero con espera: `RetryPolicy` ya aplica backoff.
      429 => QuotaFailure(
        messageKey: 'failure.quota.externalApi',
        code: 'http-$status',
      ),
      >= 500 => ServerFailure(code: 'http-$status'),
      _ => ServerFailure(code: 'http-$status'),
    };
  }

  static void _log(Uri uri, int? status, String detail) {
    // Host y ruta, nunca la query: los parámetros llevan la ubicación de la
    // persona o lo que estuvo buscando.
    _logger.warning(
      'Integración externa: $detail',
      context: <String, Object?>{
        'host': uri.host,
        'path': uri.path,
        if (status != null) 'status': status,
      },
    );
  }
}
