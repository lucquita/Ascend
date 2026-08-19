import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/app.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio de mentira que devuelve lo que le pidamos.
class _FakeAuthRepository implements AuthRepository {
  Result<AppUser> nextResult = Success<AppUser>(_user);
  int signInCalls = 0;
  int signUpCalls = 0;

  static final AppUser _user = AppUser(
    uid: 'u1',
    email: 'ana@ascend.app',
    displayName: 'Ana',
    handle: 'ana',
    createdAt: DateTime.utc(2026),
    emailVerified: true,
  );

  @override
  Future<Result<AppUser>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    return nextResult;
  }

  @override
  Future<Result<AppUser>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String handle,
  }) async {
    signUpCalls++;
    return nextResult;
  }

  @override
  Stream<AppUser?> authStateChanges() => const Stream<AppUser?>.empty();

  @override
  AppUser? get currentUser => null;

  @override
  Future<Result<void>> deleteAccount({required String password}) async =>
      const Success<void>(null);

  @override
  Future<Result<void>> refreshToken() async => const Success<void>(null);

  @override
  Future<Result<AppUser>> reloadUser() async => nextResult;

  @override
  Future<Result<void>> sendEmailVerification() async =>
      const Success<void>(null);

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async =>
      const Success<void>(null);

  @override
  Future<Result<AppUser>> signInWithApple() async => nextResult;

  @override
  Future<Result<AppUser>> signInWithGoogle() async => nextResult;

  @override
  Future<Result<void>> signOut() async => const Success<void>(null);

  @override
  Future<Result<void>> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async => const Success<void>(null);
}

Future<_FakeAuthRepository> _pumpAuth(
  WidgetTester tester, {
  SessionState session = SessionState.signedOut,
}) async {
  final repo = _FakeAuthRepository();
  final container = ProviderContainer(
    overrides: [
      sessionStateProvider.overrideWithValue(session),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AscendApp()),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('Pantalla de inicio de sesión', () {
    testWidgets('muestra los campos y la acción principal', (tester) async {
      await _pumpAuth(tester);

      expect(find.text('Iniciar sesión'), findsWidgets);
      expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Contraseña'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    });

    testWidgets('un email inválido no llega al repositorio', (tester) async {
      final repo = await _pumpAuth(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'no-es-un-email',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Contraseña'),
        'secreto123',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(
        repo.signInCalls,
        0,
        reason: 'la validación corta antes de la red',
      );
      expect(find.text('Ese email no parece válido.'), findsOneWidget);
    });

    testWidgets('credenciales incorrectas muestran un mensaje humano', (
      tester,
    ) async {
      final repo = await _pumpAuth(tester);
      repo.nextResult = const Failed<AppUser>(AuthFailure.invalidCredentials());

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'ana@ascend.app',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Contraseña'),
        'incorrecta1',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(repo.signInCalls, 1);
      expect(
        find.text('El email o la contraseña no coinciden.'),
        findsOneWidget,
      );
      // Nunca se filtra el detalle técnico ni aparece la pantalla roja.
      expect(find.textContaining('FirebaseAuthException'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin conexión el mensaje explica que se reintenta', (
      tester,
    ) async {
      final repo = await _pumpAuth(tester);
      repo.nextResult = const Failed<AppUser>(NetworkFailure());

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'ana@ascend.app',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Contraseña'),
        'secreto123',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Revisá tu internet'), findsOneWidget);
    });

    testWidgets('el error se limpia al corregir el campo', (tester) async {
      final repo = await _pumpAuth(tester);
      repo.nextResult = const Failed<AppUser>(AuthFailure.invalidCredentials());

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'ana@ascend.app',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Contraseña'),
        'mal',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(
        find.text('El email o la contraseña no coinciden.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Contraseña'),
        'ahora si1',
      );
      await tester.pumpAndSettle();

      expect(find.text('El email o la contraseña no coinciden.'), findsNothing);
    });
  });

  group('Pantalla de registro', () {
    Future<_FakeAuthRepository> openRegister(WidgetTester tester) async {
      final repo = await _pumpAuth(tester);
      await tester.tap(find.text('Creá una'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('pide nombre, usuario, email y contraseña', (tester) async {
      await openRegister(tester);

      expect(find.text('Creá tu cuenta'), findsWidgets);
      expect(find.widgetWithText(TextField, 'Tu nombre'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Nombre de usuario'),
        findsOneWidget,
      );
      expect(find.text('Crear cuenta'), findsOneWidget);
    });

    testWidgets('sin aceptar los términos no se crea la cuenta', (
      tester,
    ) async {
      final repo = await openRegister(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Tu nombre'),
        'Ana',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre de usuario'),
        'ana',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'ana@ascend.app',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Contraseña'),
        'secreto123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Repetí la contraseña'),
        'secreto123',
      );

      // El formulario es más alto que el viewport del test: sin esto el tap
      // cae fuera de pantalla y no impacta en el botón.
      await tester.ensureVisible(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();

      expect(repo.signUpCalls, 0);
      expect(find.textContaining('aceptes los términos'), findsOneWidget);
    });

    testWidgets('contraseñas distintas se avisan antes de la red', (
      tester,
    ) async {
      final repo = await openRegister(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Tu nombre'),
        'Ana',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre de usuario'),
        'ana',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'ana@ascend.app',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Contraseña'),
        'secreto123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Repetí la contraseña'),
        'otraCosa456',
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();

      expect(repo.signUpCalls, 0);
      expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    });
  });

  group('Recuperación de contraseña', () {
    testWidgets('el mensaje de confirmación no revela si el email existe', (
      tester,
    ) async {
      await _pumpAuth(tester);

      await tester.tap(find.text('¿Olvidaste tu contraseña?'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'quiensabe@ascend.app',
      );
      await tester.tap(find.text('Enviar enlace'));
      await tester.pumpAndSettle();

      expect(find.text('Revisá tu correo'), findsWidgets);
      expect(
        find.textContaining('Si ese email tiene una cuenta'),
        findsOneWidget,
      );
    });
  });
}
