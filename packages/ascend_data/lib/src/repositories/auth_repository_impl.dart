import 'dart:async';

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/remote/firebase_auth_datasource.dart';
import 'package:ascend_data/src/datasources/remote/firestore_user_datasource.dart';
import 'package:ascend_data/src/dtos/user_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Implementación de [AuthRepository] sobre Firebase.
///
/// Es la frontera: acá entran excepciones de Firebase y salen `Result`. Ni un
/// solo `throw` cruza hacia el dominio.
class AuthRepositoryImpl implements AuthRepository {
  /// Crea el repositorio.
  AuthRepositoryImpl({
    required FirebaseAuthDataSource authDataSource,
    required FirestoreUserDataSource userDataSource,
  }) : _auth = authDataSource,
       _users = userDataSource;

  static const AscendLogger _logger = AscendLogger('AuthRepository');

  final FirebaseAuthDataSource _auth;
  final FirestoreUserDataSource _users;

  AppUser? _cachedUser;

  @override
  AppUser? get currentUser => _cachedUser;

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().asyncMap((fbUser) async {
        if (fbUser == null) {
          _cachedUser = null;
          return null;
        }
        final user = await _composeUser(fbUser);
        _cachedUser = user;
        return user;
      });

  /// Arma el [AppUser] combinando las tres fuentes de verdad.
  ///
  /// Firebase Auth aporta identidad y verificación de email; el claim aporta el
  /// rol; Firestore aporta el perfil. Si el perfil todavía no existe se devuelve
  /// un usuario con `handle` vacío en lugar de `null`: hay sesión válida, y
  /// tratarla como "sin sesión" mandaría a esa persona al login, donde no puede
  /// hacer nada porque su email ya está tomado por su propia cuenta.
  Future<AppUser> _composeUser(fb.User fbUser) async {
    final role = UserRole.fromWire(await _auth.roleClaim());

    try {
      final snapshot = await _users.getUser(fbUser.uid);
      if (snapshot.exists) {
        return UserDto.fromFirestore(
          snapshot,
          emailVerified: fbUser.emailVerified,
          roleFromClaims: role,
        );
      }
    } on Object catch (error, stackTrace) {
      // Sin conexión o sin permisos todavía: se degrada al perfil mínimo en vez
      // de dejar a la app sin sesión.
      _logger.warning(
        'No se pudo leer el perfil; se usa el mínimo de Auth',
        error: error,
        stackTrace: stackTrace,
      );
    }

    return AppUser(
      uid: fbUser.uid,
      email: fbUser.email ?? '',
      displayName: fbUser.displayName ?? '',
      handle: '',
      createdAt: fbUser.metadata.creationTime ?? DateTime.now().toUtc(),
      role: role,
      emailVerified: fbUser.emailVerified,
    );
  }

  @override
  Future<Result<AppUser>> signInWithEmail({
    required String email,
    required String password,
  }) => runGuarded(() async {
    final credential = await _auth.signIn(email: email, password: password);
    final fbUser = credential.user;
    if (fbUser == null) {
      throw fb.FirebaseAuthException(
        code: 'user-not-found',
        message: 'Firebase no devolvió usuario.',
      );
    }
    final user = await _composeUser(fbUser);
    _cachedUser = user;

    // Una cuenta suspendida no debe quedar con sesión abierta: se cierra acá
    // mismo para que no pueda operar ni un segundo.
    if (user.status == UserStatus.suspended) {
      await _auth.signOut();
      _cachedUser = null;
      throw fb.FirebaseAuthException(code: 'user-disabled');
    }

    return user;
  });

  @override
  Future<Result<AppUser>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String handle,
  }) => runGuarded(() async {
    final credential = await _auth.createUser(email: email, password: password);
    final fbUser = credential.user;
    if (fbUser == null) {
      throw fb.FirebaseAuthException(
        code: 'user-not-found',
        message: 'Firebase no devolvió usuario.',
      );
    }

    // El perfil lo crea el servidor en una transacción: es lo único que
    // garantiza que el handle sea único.
    await _auth.registerProfile(displayName: displayName, handle: handle);

    // El claim de rol recién existe después de la Function: sin refrescar, el
    // token que usan las reglas de Firestore todavía no lo tiene.
    await _auth.refreshToken();

    // El correo de verificación no bloquea el registro: si el envío falla, la
    // cuenta ya existe y la pantalla de verificación ofrece reenviarlo.
    try {
      await _auth.sendEmailVerification();
    } on Object catch (error) {
      _logger.warning('No se pudo enviar la verificación', error: error);
    }

    final user = await _composeUser(fbUser);
    _cachedUser = user;
    return user;
  });

  @override
  Future<Result<AppUser>> signInWithGoogle() async =>
      const Failed<AppUser>(_socialSignInPending);

  @override
  Future<Result<AppUser>> signInWithApple() async =>
      const Failed<AppUser>(_socialSignInPending);

  /// Google y Apple quedaron fuera del alcance de la Fase 1 por decisión
  /// explícita: requieren SHA-1, URL schemes y cuenta de Apple Developer, nada
  /// de lo cual es configurable sin los proyectos Firebase creados. El contrato
  /// ya está y devuelve un fallo tipado, así que la UI lo comunica bien en vez
  /// de romperse.
  static const AuthFailure _socialSignInPending = AuthFailure(
    messageKey: 'failure.auth.socialUnavailable',
    code: 'social-sign-in-not-configured',
  );

  @override
  Future<Result<void>> signOut() => runGuarded(() async {
    await _auth.signOut();
    _cachedUser = null;
  });

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    final result = await runGuarded(() => _auth.sendPasswordResetEmail(email));

    // Enmascaramiento deliberado: si respondiéramos "esa cuenta no existe", el
    // formulario se convertiría en un detector de emails registrados. Se
    // devuelve éxito igual y solo se registra internamente.
    if (result case Failed<void>(:final failure)) {
      if (failure is AuthFailure || failure is NotFoundFailure) {
        _logger.info('Recuperación pedida para un email sin cuenta');
        return const Success<void>(null);
      }
    }
    return result;
  }

  @override
  Future<Result<void>> sendEmailVerification() =>
      runGuarded(_auth.sendEmailVerification);

  @override
  Future<Result<AppUser>> reloadUser() => runGuarded(() async {
    final fbUser = await _auth.reload();
    if (fbUser == null) {
      throw fb.FirebaseAuthException(
        code: 'user-not-found',
        message: 'No hay sesión activa.',
      );
    }
    final user = await _composeUser(fbUser);
    _cachedUser = user;
    return user;
  });

  @override
  Future<Result<void>> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) => runGuarded(() async {
    await _auth.reauthenticate(currentPassword);
    await _auth.updatePassword(newPassword);
  });

  @override
  Future<Result<void>> deleteAccount({required String password}) =>
      runGuarded(() async {
        // Reautenticar antes de borrar: un teléfono desbloqueado no debería
        // alcanzar para destruir la cuenta de alguien.
        await _auth.reauthenticate(password);
        await _auth.deleteAccount();
        _cachedUser = null;
      });

  @override
  Future<Result<void>> refreshToken() => runGuarded(_auth.refreshToken);
}
