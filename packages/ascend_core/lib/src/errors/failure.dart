import 'package:meta/meta.dart';

/// Todo fallo que Ascend puede mostrarle a una persona.
///
/// Es una jerarquía `sealed`: el compilador obliga a cubrir todos los casos en
/// cada `switch`. Esa es la garantía de que el mapeo a mensajes amigables es
/// exhaustivo y de que nunca llega a la UI un error sin traducir.
///
/// Un [Failure] **no** contiene texto para el usuario, sino una [messageKey]
/// que la capa de presentación resuelve con las traducciones. Así el dominio
/// no sabe nada de idiomas.
@immutable
sealed class Failure implements Exception {
  /// Crea un fallo con su clave de traducción y la causa técnica original.
  const Failure({
    required this.messageKey,
    this.cause,
    this.stackTrace,
    this.code,
    this.isRetryable = false,
  });

  /// Clave de i18n del mensaje que verá la persona. Nunca texto crudo.
  final String messageKey;

  /// Excepción original que provocó este fallo. Solo para logs y Crashlytics.
  final Object? cause;

  /// Traza de la excepción original.
  final StackTrace? stackTrace;

  /// Código técnico del proveedor (por ejemplo `permission-denied`).
  final String? code;

  /// Si `true`, la UI ofrece un botón de reintentar.
  final bool isRetryable;

  @override
  String toString() =>
      '$runtimeType(messageKey: $messageKey, code: $code, cause: $cause)';
}

/// No hay conexión a internet, o se perdió a mitad de la operación.
final class NetworkFailure extends Failure {
  /// Crea un fallo de red.
  const NetworkFailure({super.cause, super.stackTrace, super.code})
    : super(messageKey: 'failure.network', isRetryable: true);
}

/// La operación tardó más de lo aceptable.
final class TimeoutFailure extends Failure {
  /// Crea un fallo por tiempo de espera agotado.
  const TimeoutFailure({super.cause, super.stackTrace, super.code})
    : super(messageKey: 'failure.timeout', isRetryable: true);
}

/// El backend falló: 5xx, Firestore `unavailable`, Function caída.
final class ServerFailure extends Failure {
  /// Crea un fallo del servidor.
  const ServerFailure({super.cause, super.stackTrace, super.code})
    : super(messageKey: 'failure.server', isRetryable: true);
}

/// Problema de autenticación: credenciales inválidas o sesión expirada.
final class AuthFailure extends Failure {
  /// Crea un fallo de autenticación con una [messageKey] específica.
  const AuthFailure({
    required super.messageKey,
    super.cause,
    super.stackTrace,
    super.code,
  });

  /// Email o contraseña incorrectos.
  const AuthFailure.invalidCredentials({super.cause, super.code})
    : super(messageKey: 'failure.auth.invalidCredentials');

  /// El email ya está registrado.
  const AuthFailure.emailAlreadyInUse({super.cause, super.code})
    : super(messageKey: 'failure.auth.emailInUse');

  /// La contraseña no cumple los requisitos mínimos.
  const AuthFailure.weakPassword({super.cause, super.code})
    : super(messageKey: 'failure.auth.weakPassword');

  /// La sesión caducó y hay que volver a entrar.
  const AuthFailure.sessionExpired({super.cause, super.code})
    : super(messageKey: 'failure.auth.sessionExpired');

  /// La cuenta fue suspendida por moderación.
  const AuthFailure.accountDisabled({super.cause, super.code})
    : super(messageKey: 'failure.auth.accountDisabled');

  /// La persona canceló el flujo de login social.
  const AuthFailure.cancelled({super.cause, super.code})
    : super(messageKey: 'failure.auth.cancelled');

  /// Demasiados intentos seguidos; hay que esperar.
  const AuthFailure.tooManyRequests({super.cause, super.code})
    : super(messageKey: 'failure.auth.tooManyRequests');
}

/// Las reglas de seguridad rechazaron la operación.
///
/// En producción esto casi siempre significa un bug nuestro o un intento de
/// manipulación: se registra en Crashlytics con prioridad alta.
final class PermissionFailure extends Failure {
  /// Crea un fallo de permisos.
  const PermissionFailure({super.cause, super.stackTrace, super.code})
    : super(messageKey: 'failure.permission');
}

/// Los datos que ingresó la persona no son válidos.
final class ValidationFailure extends Failure {
  /// Crea un fallo de validación, opcionalmente asociado a un [field].
  const ValidationFailure({
    required super.messageKey,
    this.field,
    super.cause,
    super.stackTrace,
  });

  /// Nombre del campo del formulario que falló, si aplica.
  final String? field;
}

/// El recurso pedido no existe (o fue borrado).
final class NotFoundFailure extends Failure {
  /// Crea un fallo de recurso inexistente.
  const NotFoundFailure({super.cause, super.stackTrace, super.code})
    : super(messageKey: 'failure.notFound');
}

/// Se agotó una cuota: generaciones de IA del día, tamaño de archivo, etc.
final class QuotaFailure extends Failure {
  /// Crea un fallo de cuota, indicando cuándo se renueva.
  const QuotaFailure({
    required super.messageKey,
    this.resetsAt,
    super.cause,
    super.stackTrace,
    super.code,
  });

  /// Momento en que la cuota vuelve a estar disponible.
  final DateTime? resetsAt;
}

/// La operación quedó encolada porque el dispositivo está sin conexión.
///
/// No es un error para la persona: la UI lo comunica como "se sincronizará
/// cuando vuelva la conexión".
final class QueuedOfflineFailure extends Failure {
  /// Crea un aviso de operación encolada.
  const QueuedOfflineFailure({super.cause, super.stackTrace})
    : super(messageKey: 'failure.queuedOffline');
}

/// La app está por debajo de la versión mínima soportada.
final class UnsupportedVersionFailure extends Failure {
  /// Crea un fallo de versión obsoleta.
  const UnsupportedVersionFailure({this.minimumVersion, super.cause})
    : super(messageKey: 'failure.unsupportedVersion');

  /// Versión mínima exigida por el backend.
  final String? minimumVersion;
}

/// Cualquier cosa que no supimos clasificar. Siempre va a Crashlytics.
final class UnknownFailure extends Failure {
  /// Crea un fallo desconocido.
  const UnknownFailure({super.cause, super.stackTrace, super.code})
    : super(messageKey: 'failure.unknown', isRetryable: true);
}
