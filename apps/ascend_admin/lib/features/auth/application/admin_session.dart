import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Situación de quien intenta usar el panel.
///
/// No es un booleano. Entre "no hay sesión" y "puede administrar" hay tres
/// situaciones que necesitan pantallas distintas, y confundirlas deja a alguien
/// mirando un panel vacío sin saber por qué.
enum AdminSessionState {
  /// Todavía no se sabe: se está restaurando la sesión guardada.
  unknown,

  /// No hay sesión iniciada.
  signedOut,

  /// Hay sesión, pero la cuenta no tiene rol de administrador.
  notAdmin,

  /// La cuenta está suspendida.
  suspended,

  /// Sesión de administrador operativa.
  ready,
}

/// Deriva el estado del panel a partir del usuario autenticado.
///
/// ## Esto NO es la seguridad del panel
///
/// Es la capa de experiencia: decide qué pantalla mostrar. La autoridad real
/// son las reglas de Firestore, que vuelven a comprobar el claim `role` del
/// token en cada lectura y en cada escritura. Si alguien manipulara el cliente
/// para saltear este guard, entraría a un panel que no puede leer ni un
/// documento —hay tests de reglas que lo fijan—.
///
/// Se escribe como función pura para poder probar la tabla de decisión entera
/// sin levantar Firebase ni montar un widget.
AdminSessionState resolveAdminSession(AsyncValue<AppUser?> auth) {
  // Un error leyendo la sesión no puede dejar a nadie adentro: ante la duda,
  // afuera. Es el mismo criterio que usa `UserRole.fromWire`.
  if (auth.hasError) {
    return AdminSessionState.signedOut;
  }
  if (auth.isLoading && !auth.hasValue) {
    return AdminSessionState.unknown;
  }

  final user = auth.value;
  if (user == null) {
    return AdminSessionState.signedOut;
  }
  // La suspensión se evalúa antes que el rol: una cuenta de administrador
  // suspendida no debe poder administrar nada.
  if (user.status == UserStatus.suspended) {
    return AdminSessionState.suspended;
  }
  if (!user.isAdmin) {
    return AdminSessionState.notAdmin;
  }
  return AdminSessionState.ready;
}

/// Estado del panel para los guards del router.
final Provider<AdminSessionState> adminSessionProvider =
    Provider<AdminSessionState>(
      (ref) => resolveAdminSession(ref.watch(authStateProvider)),
      name: 'adminSession',
    );

/// Administrador de la sesión actual, o `null`.
final Provider<AppUser?> adminUserProvider = Provider<AppUser?>((ref) {
  final user = ref.watch(authStateProvider).value;
  return user != null && user.isAdmin ? user : null;
}, name: 'adminUser');

/// Acciones de cuenta del panel.
///
/// Solo entrar y salir, deliberadamente. Un panel de administración **no
/// ofrece registro**: si cualquiera pudiera crearse una cuenta acá, la puerta
/// de entrada al backoffice sería un formulario público. Las cuentas de
/// administrador se crean en la app y otro administrador les asigna el rol con
/// `setUserRole`.
class AdminAuthController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Entra con email y contraseña.
  Future<bool> signIn({required String email, required String password}) =>
      _run(
        () => ref
            .read(signInWithEmailUseCaseProvider)
            .call(email: email, password: password),
      );

  /// Cierra la sesión.
  Future<bool> signOut() => _run(ref.read(signOutUseCaseProvider).call);

  /// Descarta el error mostrado al editar un campo.
  void clearError() {
    if (state.hasError) {
      state = const AsyncData<void>(null);
    }
  }

  /// Ejecuta una acción y traduce su `Result` al `AsyncValue` de la pantalla.
  ///
  /// Nunca lanza: un `Failed` se convierte en `AsyncError` con el `Failure`
  /// adentro, que es lo que `ErrorStateView` sabe traducir a un mensaje.
  Future<bool> _run(Future<Result<Object?>> Function() action) async {
    state = const AsyncLoading<void>();
    final result = await guardResult(action);
    return result.fold(
      onSuccess: (_) {
        state = const AsyncData<void>(null);
        return true;
      },
      onFailure: (Failure failure) {
        state = AsyncError<void>(
          failure,
          failure.stackTrace ?? StackTrace.empty,
        );
        return false;
      },
    );
  }
}

/// Controlador de acceso al panel.
final NotifierProvider<AdminAuthController, AsyncValue<void>>
adminAuthControllerProvider =
    NotifierProvider<AdminAuthController, AsyncValue<void>>(
      AdminAuthController.new,
      name: 'adminAuthController',
    );
