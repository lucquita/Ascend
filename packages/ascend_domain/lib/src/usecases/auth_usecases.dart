/// Casos de uso del ciclo de vida de la sesión.
///
/// Cada uno encapsula una intención completa de la persona ("entrar",
/// "registrarme", "cambiar mi contraseña") con **toda** su lógica: validar,
/// ordenar los pasos y decidir qué es un error. Los widgets no hacen nada de
/// esto; solo invocan y muestran el resultado.
///
/// Por qué existen si el repositorio ya tiene los métodos: el repositorio dice
/// *cómo se habla con el backend*, el caso de uso dice *qué significa la
/// acción*. Registrarse no es "llamar a signUp": es validar cuatro campos en un
/// orden determinado y recién entonces llamar. Ese orden es negocio, y el
/// negocio no vive en un botón.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/app_user.dart';
import 'package:ascend_domain/src/repositories/repositories.dart';

/// Entra con email y contraseña.
class SignInWithEmailUseCase {
  /// Crea el caso de uso.
  const SignInWithEmailUseCase(this._auth);

  final AuthRepository _auth;

  /// Valida las credenciales y abre la sesión.
  ///
  /// La contraseña solo se comprueba como "no vacía": aplicar acá las reglas de
  /// fortaleza rechazaría a quien se registró antes de que endureciéramos la
  /// política, dejándolo fuera de su propia cuenta.
  Future<Result<AppUser>> call({
    required String email,
    required String password,
  }) async {
    final validEmail = Validators.email(email);
    if (validEmail case Failed<String>(:final failure)) {
      return Failed<AppUser>(failure);
    }

    if (password.isEmpty) {
      return const Failed<AppUser>(
        ValidationFailure(
          messageKey: 'validation.password.required',
          field: 'password',
        ),
      );
    }

    return _auth.signInWithEmail(
      email: validEmail.valueOrNull!,
      password: password,
    );
  }
}

/// Registra una cuenta nueva.
class SignUpWithEmailUseCase {
  /// Crea el caso de uso.
  const SignUpWithEmailUseCase(this._auth);

  final AuthRepository _auth;

  /// Valida los cuatro campos y crea la cuenta.
  ///
  /// El orden importa: se valida todo **antes** de tocar la red. Crear la
  /// cuenta en Auth y descubrir después que el handle tenía un carácter
  /// inválido dejaría una cuenta a medio construir.
  ///
  /// La disponibilidad del handle no se comprueba acá a propósito. Entre la
  /// comprobación y el alta hay una ventana en la que otra persona puede
  /// tomarlo; la única verificación que vale es la transacción del servidor.
  /// El formulario consulta la disponibilidad solo para dar aviso temprano.
  Future<Result<AppUser>> call({
    required String email,
    required String password,
    required String passwordConfirmation,
    required String displayName,
    required String handle,
    required bool acceptedTerms,
  }) async {
    final validEmail = Validators.email(email);
    if (validEmail case Failed<String>(:final failure)) {
      return Failed<AppUser>(failure);
    }

    final validPassword = Validators.password(password);
    if (validPassword case Failed<String>(:final failure)) {
      return Failed<AppUser>(failure);
    }

    final validConfirmation = Validators.passwordConfirmation(
      password,
      passwordConfirmation,
    );
    if (validConfirmation case Failed<String>(:final failure)) {
      return Failed<AppUser>(failure);
    }

    final validName = Validators.displayName(displayName);
    if (validName case Failed<String>(:final failure)) {
      return Failed<AppUser>(failure);
    }

    final validHandle = Validators.handle(handle);
    if (validHandle case Failed<String>(:final failure)) {
      return Failed<AppUser>(failure);
    }

    // Sin aceptación explícita no hay alta: es requisito legal, no un detalle
    // de interfaz, así que se verifica en el dominio y no solo en el botón.
    if (!acceptedTerms) {
      return const Failed<AppUser>(
        ValidationFailure(
          messageKey: 'validation.terms.required',
          field: 'acceptedTerms',
        ),
      );
    }

    return _auth.signUpWithEmail(
      email: validEmail.valueOrNull!,
      password: validPassword.valueOrNull!,
      displayName: validName.valueOrNull!,
      handle: validHandle.valueOrNull!,
    );
  }
}

/// Cierra la sesión.
class SignOutUseCase {
  /// Crea el caso de uso.
  const SignOutUseCase(this._auth);

  final AuthRepository _auth;

  /// Cierra la sesión del dispositivo actual.
  Future<Result<void>> call() => _auth.signOut();
}

/// Envía el correo de recuperación de contraseña.
class SendPasswordResetUseCase {
  /// Crea el caso de uso.
  const SendPasswordResetUseCase(this._auth);

  final AuthRepository _auth;

  /// Manda el correo de recuperación.
  ///
  /// Devuelve éxito aunque el email no esté registrado: responder "esa cuenta
  /// no existe" convierte el formulario en un detector de cuentas. Ese
  /// enmascaramiento lo hace la capa de datos; acá solo se valida el formato.
  Future<Result<void>> call(String email) async {
    final validEmail = Validators.email(email);
    if (validEmail case Failed<String>(:final failure)) {
      return Failed<void>(failure);
    }
    return _auth.sendPasswordResetEmail(validEmail.valueOrNull!);
  }
}

/// Reenvía el correo de verificación.
class SendEmailVerificationUseCase {
  /// Crea el caso de uso.
  const SendEmailVerificationUseCase(this._auth);

  final AuthRepository _auth;

  /// Reenvía el correo de verificación a la cuenta actual.
  Future<Result<void>> call() => _auth.sendEmailVerification();
}

/// Vuelve a leer el estado de la cuenta desde el servidor.
class ReloadUserUseCase {
  /// Crea el caso de uso.
  const ReloadUserUseCase(this._auth);

  final AuthRepository _auth;

  /// Refresca el usuario. Lo usa la pantalla de verificación al volver del
  /// correo, porque `emailVerified` no cambia solo en el cliente.
  Future<Result<AppUser>> call() => _auth.reloadUser();
}

/// Cambia la contraseña revalidando la actual.
class ChangePasswordUseCase {
  /// Crea el caso de uso.
  const ChangePasswordUseCase(this._auth);

  final AuthRepository _auth;

  /// Cambia la contraseña.
  Future<Result<void>> call({
    required String currentPassword,
    required String newPassword,
    required String confirmation,
  }) async {
    if (currentPassword.isEmpty) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.password.required',
          field: 'currentPassword',
        ),
      );
    }

    final validNew = Validators.password(newPassword);
    if (validNew case Failed<String>(:final failure)) {
      return Failed<void>(failure);
    }

    final validConfirmation = Validators.passwordConfirmation(
      newPassword,
      confirmation,
    );
    if (validConfirmation case Failed<String>(:final failure)) {
      return Failed<void>(failure);
    }

    // Cambiar una contraseña por sí misma es casi siempre un error de la
    // persona, y aceptarlo en silencio le hace creer que hizo algo.
    if (currentPassword == newPassword) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.password.sameAsCurrent',
          field: 'newPassword',
        ),
      );
    }

    return _auth.updatePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }
}

/// Elimina la cuenta y todos sus datos.
class DeleteAccountUseCase {
  /// Crea el caso de uso.
  const DeleteAccountUseCase(this._auth);

  final AuthRepository _auth;

  /// Borra la cuenta previa reautenticación.
  ///
  /// Exigir la contraseña no es burocracia: un teléfono desbloqueado y
  /// desatendido alcanzaría para que alguien borre la cuenta de otra persona.
  Future<Result<void>> call({
    required String password,
    required bool confirmed,
  }) async {
    if (password.isEmpty) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.password.required',
          field: 'password',
        ),
      );
    }
    if (!confirmed) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.deleteAccount.notConfirmed',
          field: 'confirmed',
        ),
      );
    }
    return _auth.deleteAccount(password: password);
  }
}

/// Observa la sesión activa.
class WatchAuthStateUseCase {
  /// Crea el caso de uso.
  const WatchAuthStateUseCase(this._auth);

  final AuthRepository _auth;

  /// Emite el usuario autenticado, o `null` si no hay sesión.
  Stream<AppUser?> call() => _auth.authStateChanges();
}
