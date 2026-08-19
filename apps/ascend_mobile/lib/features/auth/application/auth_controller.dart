import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resultado de la última acción de autenticación.
///
/// `AsyncValue<void>` modela los tres estados que necesita el formulario
/// —quieto, en curso, terminado con o sin fallo— sin inventar un enum propio.
typedef AuthActionState = AsyncValue<void>;

/// Orquesta las acciones de cuenta y expone su estado a las pantallas.
///
/// Las pantallas no llaman a repositorios ni a Firebase: llaman acá. Toda la
/// secuencia —validar, ejecutar, traducir el fallo— vive en esta capa, así el
/// widget se limita a pintar `loading`, `error` o `data`.
class AuthController extends Notifier<AuthActionState> {
  @override
  AuthActionState build() => const AsyncData<void>(null);

  /// Entra con email y contraseña.
  Future<bool> signIn({required String email, required String password}) =>
      _run(
        () => ref
            .read(signInWithEmailUseCaseProvider)
            .call(email: email, password: password),
      );

  /// Registra una cuenta nueva.
  Future<bool> signUp({
    required String email,
    required String password,
    required String passwordConfirmation,
    required String displayName,
    required String handle,
    required bool acceptedTerms,
  }) => _run(
    () => ref
        .read(signUpWithEmailUseCaseProvider)
        .call(
          email: email,
          password: password,
          passwordConfirmation: passwordConfirmation,
          displayName: displayName,
          handle: handle,
          acceptedTerms: acceptedTerms,
        ),
  );

  /// Cierra la sesión.
  Future<bool> signOut() => _run(ref.read(signOutUseCaseProvider).call);

  /// Envía el correo de recuperación.
  Future<bool> sendPasswordReset(String email) =>
      _run(() => ref.read(sendPasswordResetUseCaseProvider).call(email));

  /// Reenvía el correo de verificación.
  Future<bool> sendEmailVerification() =>
      _run(ref.read(sendEmailVerificationUseCaseProvider).call);

  /// Relee el usuario para detectar si ya verificó el email.
  Future<bool> reload() => _run(ref.read(reloadUserUseCaseProvider).call);

  /// Cambia la contraseña.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmation,
  }) => _run(
    () => ref
        .read(changePasswordUseCaseProvider)
        .call(
          currentPassword: currentPassword,
          newPassword: newPassword,
          confirmation: confirmation,
        ),
  );

  /// Elimina la cuenta.
  Future<bool> deleteAccount({
    required String password,
    required bool confirmed,
  }) => _run(
    () => ref
        .read(deleteAccountUseCaseProvider)
        .call(password: password, confirmed: confirmed),
  );

  /// Descarta el error mostrado.
  ///
  /// Lo llama el formulario al editar un campo: dejar el error de la operación
  /// anterior colgado mientras alguien corrige los datos es confuso.
  void clearError() {
    if (state.hasError) {
      state = const AsyncData<void>(null);
    }
  }

  /// Ejecuta una acción y traduce su `Result` al `AsyncValue` de la pantalla.
  ///
  /// Devuelve `true` si salió bien, para que la pantalla decida si navegar.
  /// Nunca lanza: un `Failed` se convierte en `AsyncError` con el `Failure`
  /// dentro, que es lo que `ErrorStateView` sabe traducir.
  Future<bool> _run(Future<Result<Object?>> Function() action) async {
    state = const AsyncLoading<void>();
    final result = await guardResult(action);
    return result.fold(
      onSuccess: (_) {
        state = const AsyncData<void>(null);
        return true;
      },
      onFailure: (failure) {
        state = AsyncError<void>(
          failure,
          failure.stackTrace ?? StackTrace.empty,
        );
        return false;
      },
    );
  }
}

/// Controlador de las acciones de cuenta.
final NotifierProvider<AuthController, AuthActionState> authControllerProvider =
    NotifierProvider<AuthController, AuthActionState>(
      AuthController.new,
      name: 'authController',
    );

/// Disponibilidad de un handle mientras se escribe.
///
/// `family` con el handle como argumento y `autoDispose` para no acumular una
/// consulta por cada tecla apretada.
// Sin anotación de tipo explícita a propósito: `FutureProviderFamily` no está
// exportado por `flutter_riverpod`, así que el tipo solo se puede inferir.
final handleAvailabilityProvider = FutureProvider.family<bool, String>((
  ref,
  handle,
) async {
  if (handle.length < 3) {
    return false;
  }
  final result = await guardResult(
    () => ref.read(checkHandleAvailabilityUseCaseProvider).call(handle),
  );
  // Ante un fallo de red no se afirma que esté libre: se deja que el
  // servidor decida en el alta. Prometer disponibilidad y fallar después es
  // peor que no prometer nada.
  return result.getOrElse((_) => false);
}, name: 'handleAvailability');
