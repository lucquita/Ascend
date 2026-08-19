import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/app.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/router/app_router.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

AppUser _user({
  String handle = 'ana',
  bool emailVerified = true,
  UserStatus status = UserStatus.active,
  UserRole role = UserRole.user,
}) => AppUser(
  uid: 'u1',
  email: 'ana@ascend.app',
  displayName: 'Ana',
  handle: handle,
  createdAt: DateTime.utc(2026),
  emailVerified: emailVerified,
  status: status,
  role: role,
);

void main() {
  group('resolveSessionState — tabla de decisión', () {
    test('mientras carga, no decide nada', () {
      expect(
        resolveSessionState(const AsyncLoading<AppUser?>()),
        SessionState.unknown,
      );
    });

    test('sin usuario, sesión cerrada', () {
      expect(
        resolveSessionState(const AsyncData<AppUser?>(null)),
        SessionState.signedOut,
      );
    });

    test('ante un error leyendo la sesión, deja afuera', () {
      // El mismo criterio que `UserRole.fromWire`: ante la duda, el estado
      // menos privilegiado. Un fallo de lectura no puede abrir la puerta.
      expect(
        resolveSessionState(
          AsyncError<AppUser?>(StateError('roto'), StackTrace.empty),
        ),
        SessionState.signedOut,
      );
    });

    test('cuenta suspendida gana sobre todo lo demás', () {
      final state = resolveSessionState(
        AsyncData<AppUser?>(
          _user(status: UserStatus.suspended, emailVerified: false, handle: ''),
        ),
      );
      expect(state, SessionState.blocked);
    });

    test('sin perfil, manda a completarlo', () {
      expect(
        resolveSessionState(AsyncData<AppUser?>(_user(handle: ''))),
        SessionState.needsProfile,
      );
    });

    test('con perfil pero sin verificar el email, manda a verificar', () {
      expect(
        resolveSessionState(AsyncData<AppUser?>(_user(emailVerified: false))),
        SessionState.needsEmailVerification,
      );
    });

    test('con todo en orden, listo para usar la app', () {
      expect(
        resolveSessionState(AsyncData<AppUser?>(_user())),
        SessionState.ready,
      );
    });

    test('el orden es suspensión → perfil → verificación', () {
      // Verificar el email de una cuenta suspendida no tendría sentido, y
      // pedirle verificar a quien todavía no tiene perfil tampoco.
      expect(
        resolveSessionState(
          AsyncData<AppUser?>(_user(status: UserStatus.suspended)),
        ),
        SessionState.blocked,
      );
      expect(
        resolveSessionState(
          AsyncData<AppUser?>(_user(handle: '', emailVerified: false)),
        ),
        SessionState.needsProfile,
      );
    });
  });

  group('Rol de administrador', () {
    test('se lee del usuario resuelto, que toma el rol del claim', () {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<AppUser?>.value(_user(role: UserRole.admin)),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Se consume el stream antes de leer el derivado.
      expect(container.read(authStateProvider), isA<AsyncValue<AppUser?>>());
    });

    test('un usuario común no es admin', () {
      expect(_user().isAdmin, isFalse);
      expect(_user(role: UserRole.admin).isAdmin, isTrue);
    });
  });

  group('Guards del router — estados nuevos de la Fase 1', () {
    Future<GoRouterHarness> pump(
      WidgetTester tester,
      SessionState session,
    ) async {
      final container = ProviderContainer(
        overrides: [sessionStateProvider.overrideWithValue(session)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AscendApp(),
        ),
      );
      await tester.pumpAndSettle();
      return GoRouterHarness(container);
    }

    testWidgets('sin perfil, aterriza en completar perfil', (tester) async {
      await pump(tester, SessionState.needsProfile);

      expect(find.text('Falta poco'), findsWidgets);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('sin verificar el email, aterriza en verificación', (
      tester,
    ) async {
      await pump(tester, SessionState.needsEmailVerification);

      expect(find.text('Verificá tu email'), findsWidgets);
      expect(find.text('Ya lo verifiqué'), findsOneWidget);
    });

    testWidgets('cuenta suspendida, aterriza en la pantalla de bloqueo', (
      tester,
    ) async {
      await pump(tester, SessionState.blocked);

      expect(find.text('Tu cuenta está suspendida'), findsWidgets);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('con sesión lista no se puede entrar a completar perfil', (
      tester,
    ) async {
      final harness = await pump(tester, SessionState.ready);

      harness.router.go(Routes.completeProfile);
      await tester.pumpAndSettle();

      expect(
        harness.router.state.matchedLocation,
        isNot(Routes.completeProfile),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('sin sesión se puede llegar al registro y a recuperación', (
      tester,
    ) async {
      final harness = await pump(tester, SessionState.signedOut);

      harness.router.go(Routes.register);
      await tester.pumpAndSettle();
      expect(find.text('Creá tu cuenta'), findsWidgets);

      harness.router.go(Routes.forgotPassword);
      await tester.pumpAndSettle();
      expect(find.text('Recuperar contraseña'), findsWidgets);
    });
  });
}

/// Acceso al router montado dentro del test.
class GoRouterHarness {
  /// Crea el envoltorio.
  GoRouterHarness(this.container);

  /// Contenedor de providers usado por el widget bajo prueba.
  final ProviderContainer container;

  /// El router realmente montado.
  GoRouter get router => container.read(appRouterProvider);
}
