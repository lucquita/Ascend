import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Situación de la persona respecto de la app. La consumen los guards.
///
/// No es un booleano "logueado o no" porque el estado real no es binario: entre
/// "no hay sesión" y "puede usar la app" hay tres situaciones intermedias que
/// requieren pantallas distintas, y confundirlas deja a alguien encerrado.
enum SessionState {
  /// Todavía no se sabe: se está restaurando la sesión guardada.
  unknown,

  /// No hay sesión iniciada.
  signedOut,

  /// Hay cuenta en Auth pero no hay perfil en Firestore.
  ///
  /// Pasa de verdad: la cuenta se crea, la Function que escribe el perfil no
  /// llega a terminar y la app se cierra. Sin este estado esa persona quedaría
  /// en un limbo, porque su email ya figura como registrado y no puede volver a
  /// darse de alta.
  needsProfile,

  /// La cuenta existe pero falta verificar el email.
  needsEmailVerification,

  /// Hay sesión pero falta completar el onboarding.
  needsOnboarding,

  /// La cuenta está suspendida por moderación.
  blocked,

  /// Sesión completa y operativa.
  ready,
}

/// Deriva el estado de sesión a partir del usuario autenticado.
///
/// Es una función pura para poder testear la tabla de decisión completa sin
/// levantar Firebase ni montar un widget.
SessionState resolveSessionState(AsyncValue<AppUser?> auth) {
  // Un error leyendo la sesión no puede dejar a nadie adentro: ante la duda,
  // afuera. Es el mismo criterio que aplica `UserRole.fromWire`.
  if (auth.hasError) {
    return SessionState.signedOut;
  }
  if (auth.isLoading && !auth.hasValue) {
    return SessionState.unknown;
  }

  final user = auth.value;
  if (user == null) {
    return SessionState.signedOut;
  }
  if (user.status == UserStatus.suspended) {
    return SessionState.blocked;
  }
  if (!user.hasProfile) {
    return SessionState.needsProfile;
  }
  if (!user.emailVerified) {
    return SessionState.needsEmailVerification;
  }

  // El onboarding de 4 pasos no forma parte del alcance acordado para esta
  // fase, así que no se bloquea a nadie por él. El estado y su guard quedan
  // implementados para que enchufarlo sea cambiar esta única condición.
  return SessionState.ready;
}

/// Estado de sesión actual.
///
/// Sigue siendo un `Provider<SessionState>` con el mismo nombre que en la Fase
/// 0: los tests que lo sustituyen con `overrideWithValue` siguen funcionando
/// sin cambios, que es exactamente lo que se prometió al diseñarlo.
final Provider<SessionState> sessionStateProvider = Provider<SessionState>(
  (ref) => resolveSessionState(ref.watch(authStateProvider)),
  name: 'sessionState',
);

/// Usuario autenticado ya resuelto, o `null`.
final Provider<AppUser?> currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authStateProvider).value,
  name: 'currentUser',
);

/// `true` si la persona autenticada es administradora.
///
/// Lee el rol del claim, nunca del documento de Firestore (ADR-004). Acá solo
/// decide qué se muestra: quien manipule el cliente igual choca con las reglas.
final Provider<bool> isAdminProvider = Provider<bool>(
  (ref) => ref.watch(currentUserProvider)?.isAdmin ?? false,
  name: 'isAdmin',
);
