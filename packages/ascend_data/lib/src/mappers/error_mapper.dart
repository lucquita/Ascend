import 'dart:async';
import 'dart:io';

import 'package:ascend_core/ascend_core.dart';
// Imports acotados con `show`: los plugins de Firebase se reexportan entre sí
// y sin esto el analizador no distingue de dónde viene cada tipo.
// `cloud_functions`, además, exporta su propio `Result`, que chocaría con el
// nuestro.
import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

/// Convierte cualquier excepción de la infraestructura en un [Failure].
///
/// Es la frontera del sistema: **ninguna excepción de Firebase, de red o de
/// disco cruza esta clase**. Todo lo que sale de acá es un `Failure` tipado que
/// la UI ya sabe mostrar.
///
/// El `default` final es intencional y no es pereza: si Firebase agrega un
/// código nuevo mañana, la app lo degrada a [UnknownFailure] y lo reporta a
/// Crashlytics, en lugar de reventar en las manos de alguien.
abstract final class ErrorMapper {
  static const AscendLogger _logger = AscendLogger('ErrorMapper');

  /// Punto de entrada único. Enruta según el tipo de excepción.
  static Failure map(Object error, StackTrace stackTrace) {
    final failure = _classify(error, stackTrace);

    // Los fallos de permisos casi siempre son un bug nuestro o un intento de
    // manipulación: se registran con prioridad alta aunque el usuario vea un
    // mensaje suave.
    if (failure is PermissionFailure || failure is UnknownFailure) {
      _logger.error(
        'Fallo sin clasificar o de permisos',
        error: error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'failureType': failure.runtimeType.toString(),
        },
      );
    }

    return failure;
  }

  static Failure _classify(
    Object error,
    StackTrace stackTrace,
  ) => switch (error) {
    // Ya viene mapeado: no lo envolvemos dos veces.
    final Failure failure => failure,
    final FirebaseAuthException e => _mapAuth(e, stackTrace),
    final FirebaseFunctionsException e => _mapFunctions(e, stackTrace),
    final FirebaseException e => _mapFirebase(e, stackTrace),
    final SocketException e => NetworkFailure(cause: e, stackTrace: stackTrace),
    final HttpException e => NetworkFailure(cause: e, stackTrace: stackTrace),
    final TimeoutException e => TimeoutFailure(
      cause: e,
      stackTrace: stackTrace,
    ),
    final FormatException e => ServerFailure(
      cause: e,
      stackTrace: stackTrace,
      code: 'malformed-response',
    ),
    _ => UnknownFailure(cause: error, stackTrace: stackTrace),
  };

  /// Mapea los códigos de Firebase Authentication.
  static Failure _mapAuth(
    FirebaseAuthException e,
    StackTrace stackTrace,
  ) => switch (e.code) {
    // Firebase unifica usuario inexistente y contraseña incorrecta en
    // `invalid-credential` justamente para no filtrar qué emails existen.
    // Mantenemos ese comportamiento en el mensaje al usuario.
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' ||
    'invalid-email' => AuthFailure.invalidCredentials(cause: e, code: e.code),
    'email-already-in-use' || 'account-exists-with-different-credential' =>
      AuthFailure.emailAlreadyInUse(cause: e, code: e.code),
    'weak-password' => AuthFailure.weakPassword(cause: e, code: e.code),
    'user-disabled' => AuthFailure.accountDisabled(cause: e, code: e.code),
    'requires-recent-login' => AuthFailure.sessionExpired(
      cause: e,
      code: e.code,
    ),
    'too-many-requests' => AuthFailure.tooManyRequests(cause: e, code: e.code),
    'web-context-canceled' ||
    'canceled' ||
    'sign_in_canceled' => AuthFailure.cancelled(cause: e, code: e.code),
    'network-request-failed' => NetworkFailure(
      cause: e,
      stackTrace: stackTrace,
      code: e.code,
    ),
    'operation-not-allowed' => PermissionFailure(
      cause: e,
      stackTrace: stackTrace,
      code: e.code,
    ),
    _ => UnknownFailure(cause: e, stackTrace: stackTrace, code: e.code),
  };

  /// Mapea los códigos de las Cloud Functions llamables.
  static Failure _mapFunctions(
    FirebaseFunctionsException e,
    StackTrace stackTrace,
  ) => switch (e.code) {
    'unauthenticated' => AuthFailure.sessionExpired(cause: e, code: e.code),
    'permission-denied' => PermissionFailure(
      cause: e,
      stackTrace: stackTrace,
      code: e.code,
    ),
    'not-found' => NotFoundFailure(
      cause: e,
      stackTrace: stackTrace,
      code: e.code,
    ),
    'invalid-argument' || 'failed-precondition' => ValidationFailure(
      messageKey: 'validation.request.invalid',
      cause: e,
      stackTrace: stackTrace,
    ),
    // La cuota de IA agotada llega por acá: no es un error, es un límite.
    'resource-exhausted' => QuotaFailure(
      messageKey: 'failure.quota.ai',
      cause: e,
      stackTrace: stackTrace,
      code: e.code,
    ),
    'deadline-exceeded' => TimeoutFailure(
      cause: e,
      stackTrace: stackTrace,
      code: e.code,
    ),
    'unavailable' ||
    'internal' => ServerFailure(cause: e, stackTrace: stackTrace, code: e.code),
    _ => UnknownFailure(cause: e, stackTrace: stackTrace, code: e.code),
  };

  /// Mapea Firestore, Storage y el resto de servicios de Firebase.
  static Failure _mapFirebase(FirebaseException e, StackTrace stackTrace) =>
      switch (e.code) {
        'permission-denied' || 'unauthorized' => PermissionFailure(
          cause: e,
          stackTrace: stackTrace,
          code: e.code,
        ),
        'not-found' || 'object-not-found' => NotFoundFailure(
          cause: e,
          stackTrace: stackTrace,
          code: e.code,
        ),
        'unauthenticated' => AuthFailure.sessionExpired(cause: e, code: e.code),
        // `unavailable` en Firestore normalmente significa "sin red": el SDK ya
        // guardó el cambio en la caché local y lo sincronizará solo.
        'unavailable' || 'network-request-failed' || 'retry-limit-exceeded' =>
          NetworkFailure(cause: e, stackTrace: stackTrace, code: e.code),
        'deadline-exceeded' => TimeoutFailure(
          cause: e,
          stackTrace: stackTrace,
          code: e.code,
        ),
        'resource-exhausted' || 'quota-exceeded' => QuotaFailure(
          messageKey: 'failure.quota.storage',
          cause: e,
          stackTrace: stackTrace,
          code: e.code,
        ),
        'canceled' => NetworkFailure(
          cause: e,
          stackTrace: stackTrace,
          code: e.code,
        ),
        'invalid-argument' ||
        'already-exists' ||
        'failed-precondition' => ValidationFailure(
          messageKey: 'validation.request.invalid',
          cause: e,
          stackTrace: stackTrace,
        ),
        'aborted' || 'internal' || 'data-loss' || 'unknown' => ServerFailure(
          cause: e,
          stackTrace: stackTrace,
          code: e.code,
        ),
        _ => UnknownFailure(cause: e, stackTrace: stackTrace, code: e.code),
      };

  /// Azúcar para usar en los repositorios: `guardAsync(..., onError: ErrorMapper.onError)`.
  static Failure onError(Object error, StackTrace stackTrace) =>
      map(error, stackTrace);
}

/// Ejecuta una operación de infraestructura devolviendo siempre un [Result].
///
/// Es el envoltorio que usan todos los repositorios: garantiza por construcción
/// que ninguna excepción sale de la capa de datos.
Future<Result<T>> runGuarded<T>(Future<T> Function() action) =>
    guardAsync<T>(action, onError: ErrorMapper.onError);

/// Convierte un stream de infraestructura en un stream de [Result].
///
/// Un error en el stream se emite como `Failed` **sin cerrar la suscripción**:
/// si se perdió la conexión un segundo, la pantalla muestra el aviso y se
/// recupera sola cuando vuelven los datos, en vez de quedarse muerta.
Stream<Result<T>> guardStream<T>(Stream<T> source) => source.transform(
  StreamTransformer<T, Result<T>>.fromHandlers(
    handleData: (data, sink) => sink.add(Success<T>(data)),
    handleError: (error, stackTrace, sink) =>
        sink.add(Failed<T>(ErrorMapper.map(error, stackTrace))),
  ),
);

/// Ejecuta una acción que **ya devuelve** un [Result] y la blinda igual.
///
/// ## Por qué hace falta si los repositorios nunca lanzan
///
/// Porque entre el controlador y el repositorio hay un tramo que no está
/// cubierto: **construir el repositorio**. Un `ref.read(algoProvider)` levanta
/// toda la cadena de dependencias, y si en el fondo hay un
/// `FirebaseAuth.instance` sin Firebase inicializado, eso lanza *antes* de que
/// exista un `runGuarded` que lo atrape.
///
/// El síntoma de esa grieta es el peor posible: el controlador ya se puso en
/// `AsyncLoading`, la excepción escapa del `await`, y el estado **nunca sale de
/// cargando**. El botón gira para siempre y la persona no se entera de nada.
///
/// Envolver la acción entera —lectura de providers incluida— cierra la grieta.
Future<Result<T>> guardResult<T>(Future<Result<T>> Function() action) async {
  try {
    return await action();
  } on Object catch (error, stackTrace) {
    return Failed<T>(ErrorMapper.map(error, stackTrace));
  }
}
