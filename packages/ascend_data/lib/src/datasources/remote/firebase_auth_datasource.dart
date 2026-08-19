import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctions;
import 'package:firebase_auth/firebase_auth.dart';

/// Acceso directo a Firebase Authentication y a las Functions de cuenta.
///
/// No mapea errores ni devuelve `Result`: eso es trabajo del repositorio. Acá
/// solo vive el "cómo se le habla a Firebase", para poder sustituirlo entero en
/// los tests sin tocar la lógica.
class FirebaseAuthDataSource {
  /// Crea el datasource.
  const FirebaseAuthDataSource({
    required FirebaseAuth auth,
    required FirebaseFunctions functions,
  }) : _auth = auth,
       _functions = functions;

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  /// Usuario de Firebase actualmente autenticado.
  User? get currentUser => _auth.currentUser;

  /// Emite el usuario de Firebase en cada cambio de sesión.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Entra con email y contraseña.
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) => _auth.signInWithEmailAndPassword(email: email, password: password);

  /// Crea la cuenta en Firebase Auth.
  Future<UserCredential> createUser({
    required String email,
    required String password,
  }) => _auth.createUserWithEmailAndPassword(email: email, password: password);

  /// Crea el perfil llamando a la Cloud Function transaccional.
  ///
  /// Es el único camino: el cliente no puede escribir `handles/{handle}` ni
  /// asignarse el claim de rol.
  Future<void> registerProfile({
    required String displayName,
    required String handle,
    String? locale,
    String? timezone,
  }) => _functions
      .httpsCallable('registerProfile')
      .call<Object?>(<String, Object?>{
        'displayName': displayName,
        'handle': handle,
        if (locale != null) 'locale': locale,
        if (timezone != null) 'timezone': timezone,
      });

  /// Pide al servidor la baja completa de la cuenta.
  Future<void> deleteAccount() =>
      _functions.httpsCallable('deleteAccount').call<Object?>();

  /// Cierra la sesión.
  Future<void> signOut() => _auth.signOut();

  /// Manda el correo de recuperación.
  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  /// Manda el correo de verificación al usuario actual.
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No hay sesión activa.',
      );
    }
    await user.sendEmailVerification();
  }

  /// Relee el usuario desde el servidor.
  Future<User?> reload() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    await user.reload();
    return _auth.currentUser;
  }

  /// Revalida la contraseña actual.
  ///
  /// Firebase la exige para operaciones sensibles cuando la sesión lleva rato
  /// abierta; hacerlo siempre evita el `requires-recent-login` intermitente que
  /// aparece solo en algunas cuentas y es imposible de reproducir.
  Future<void> reauthenticate(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No hay sesión activa.',
      );
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  /// Cambia la contraseña del usuario actual.
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No hay sesión activa.',
      );
    }
    await user.updatePassword(newPassword);
  }

  /// Devuelve el rol que viaja en el custom claim.
  ///
  /// [forceRefresh] fuerza a pedir un token nuevo. Sin eso, tras un cambio de
  /// rol la app seguiría usando el claim viejo hasta que el token caduque solo,
  /// que puede ser una hora después.
  Future<String?> roleClaim({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    final token = await user.getIdTokenResult(forceRefresh);
    final role = token.claims?['role'];
    return role is String ? role : null;
  }

  /// Fuerza el refresco del token.
  Future<void> refreshToken() async {
    await _auth.currentUser?.getIdToken(true);
  }
}
