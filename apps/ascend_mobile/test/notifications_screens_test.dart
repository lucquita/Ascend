import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/notifications/presentation/screens/notification_settings_screen.dart';
import 'package:ascend_mobile/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:ascend_mobile/features/notifications/presentation/widgets/notification_bell.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeNotificationRepository implements NotificationRepository {
  List<AppNotification> inbox = const <AppNotification>[];
  int unread = 0;
  Failure? inboxFailure;
  NotificationPermission permission = NotificationPermission.granted;

  final List<String> marked = <String>[];
  int markAllCalls = 0;
  int permissionRequests = 0;
  int registrations = 0;

  @override
  Stream<Result<List<AppNotification>>> watchNotifications(String uid) =>
      Stream<Result<List<AppNotification>>>.value(
        inboxFailure != null
            ? Failed<List<AppNotification>>(inboxFailure!)
            : Success<List<AppNotification>>(inbox),
      );

  @override
  Stream<int> watchUnreadCount(String uid) => Stream<int>.value(unread);

  @override
  Future<Result<void>> markAsRead({
    required String uid,
    required String id,
  }) async {
    marked.add(id);
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> markAllAsRead(String uid) async {
    markAllCalls++;
    return const Success<void>(null);
  }

  @override
  Future<NotificationPermission> permissionStatus() async => permission;

  @override
  Future<NotificationPermission> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<Result<void>> registerDeviceToken(String uid) async {
    registrations++;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> unregisterDeviceToken(String uid) async =>
      const Success<void>(null);
}

class _FakeUserRepository implements UserRepository {
  UserSettings? saved;

  @override
  Future<Result<void>> updateSettings({
    required String uid,
    required UserSettings settings,
  }) async {
    saved = settings;
    return const Success<void>(null);
  }

  @override
  Stream<Result<AppUser>> watchUser(String uid) =>
      const Stream<Result<AppUser>>.empty();

  @override
  Future<Result<AppUser>> getUser(String uid) async =>
      const Failed<AppUser>(NotFoundFailure());

  @override
  Future<Result<void>> updateProfile({
    required String uid,
    String? displayName,
    String? bio,
    String? photoUrl,
  }) async => const Success<void>(null);

  @override
  Future<Result<bool>> isHandleAvailable(String handle) async =>
      const Success<bool>(true);

  @override
  Future<Result<void>> claimHandle({
    required String uid,
    required String handle,
  }) async => const Success<void>(null);

  @override
  Future<Result<String>> uploadAvatar({
    required String uid,
    required String localPath,
  }) async => const Failed<String>(PermissionFailure());

  @override
  Future<Result<void>> completeOnboarding({
    required String uid,
    required List<String> interests,
  }) async => const Success<void>(null);
}

AppUser _user({NotificationSettings? notifications}) => AppUser(
  uid: 'u1',
  email: 'ana@ascend.app',
  displayName: 'Ana',
  handle: 'ana',
  createdAt: DateTime.utc(2026),
  emailVerified: true,
  settings: UserSettings(
    notifications: notifications ?? const NotificationSettings(),
  ),
);

AppNotification _notification({
  String id = 'n1',
  NotificationType type = NotificationType.newLike,
  bool read = false,
  String? route,
}) => AppNotification(
  id: id,
  type: type,
  title: 'Nuevo me gusta',
  body: 'A Ana le gustó tu publicación.',
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  data: <String, String>{if (route != null) 'route': route},
  read: read,
);

/// Monta una pantalla con los dobles enchufados.
///
/// El tipo `Override` no lo exporta `flutter_riverpod`, así que la lista se
/// arma acá dentro.
Widget _host(
  Widget child, {
  required _FakeNotificationRepository notifications,
  _FakeUserRepository? users,
  AppUser? profile,
}) {
  final user = profile ?? _user();

  return ProviderScope(
    overrides: [
      notificationRepositoryProvider.overrideWithValue(notifications),
      userRepositoryProvider.overrideWithValue(users ?? _FakeUserRepository()),
      authStateProvider.overrideWith((ref) => Stream<AppUser?>.value(user)),
      profileProvider.overrideWith(
        (ref) => Stream<Result<AppUser>>.value(Success<AppUser>(user)),
      ),
    ],
    child: MaterialApp.router(
      theme: AscendTheme.light,
      // Router real: la bandeja navega al destino de la notificación, y sin
      // GoRouter esa navegación falla con "No GoRouter found in context".
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(path: '/', builder: (_, _) => child),
          GoRoute(
            path: '/community/:id',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('llegó al post'))),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('bandeja'))),
          ),
        ],
      ),
    ),
  );
}

/// Deja que los streams emitan sin esperar a que todo se asiente.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakeNotificationRepository notifications;

  setUp(() => notifications = _FakeNotificationRepository());

  group('Bandeja', () {
    testWidgets('lista las notificaciones recibidas', (tester) async {
      _useTallScreen(tester);
      notifications.inbox = <AppNotification>[_notification()];

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      expect(find.text('Nuevo me gusta'), findsOneWidget);
      expect(find.text('2 h'), findsOneWidget);
    });

    testWidgets('sin nada explica qué va a aparecer', (tester) async {
      _useTallScreen(tester);

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      expect(find.text('Nada por acá'), findsOneWidget);
    });

    testWidgets('tocar una la marca leída y navega a su destino', (
      tester,
    ) async {
      _useTallScreen(tester);
      notifications.inbox = <AppNotification>[
        _notification(route: '/community/p1'),
      ];

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      await tester.tap(find.text('Nuevo me gusta'));
      await _settle(tester);

      expect(notifications.marked, <String>['n1']);
      expect(find.text('llegó al post'), findsOneWidget);
    });

    testWidgets('una ya leída no se vuelve a marcar', (tester) async {
      _useTallScreen(tester);
      notifications.inbox = <AppNotification>[
        _notification(read: true, route: '/community/p1'),
      ];

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      await tester.tap(find.text('Nuevo me gusta'));
      await _settle(tester);

      expect(notifications.marked, isEmpty);
      expect(find.text('llegó al post'), findsOneWidget);
    });

    testWidgets('sin destino no rompe al tocarla', (tester) async {
      _useTallScreen(tester);
      notifications.inbox = <AppNotification>[_notification()];

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      await tester.tap(find.text('Nuevo me gusta'));
      await _settle(tester);

      expect(notifications.marked, <String>['n1']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('marcar todas como leídas llega al repositorio', (
      tester,
    ) async {
      _useTallScreen(tester);
      notifications.inbox = <AppNotification>[_notification()];

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.done_all_rounded));
      await _settle(tester);

      expect(notifications.markAllCalls, 1);
    });

    testWidgets('sin permiso ofrece activarlo con una explicación', (
      tester,
    ) async {
      // El diálogo del sistema se muestra una sola vez: gastarlo sin contexto
      // convierte el rechazo en definitivo.
      _useTallScreen(tester);
      notifications.permission = NotificationPermission.notDetermined;

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      expect(find.textContaining('Activá los avisos'), findsOneWidget);

      await tester.tap(find.text('Activar avisos'));
      await _settle(tester);

      expect(notifications.permissionRequests, 1);
    });

    testWidgets('con el permiso denegado NO ofrece un botón inútil', (
      tester,
    ) async {
      // Volver a pedirlo no muestra nada: solo se revierte desde los ajustes
      // del sistema, y hay que decirlo.
      _useTallScreen(tester);
      notifications.permission = NotificationPermission.denied;

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      expect(find.textContaining('ajustes del sistema'), findsOneWidget);
      expect(find.text('Activar avisos'), findsNothing);
    });

    testWidgets('con el permiso concedido no muestra ningún aviso', (
      tester,
    ) async {
      _useTallScreen(tester);

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      expect(find.textContaining('Activá los avisos'), findsNothing);
    });

    testWidgets('un fallo de lectura ofrece reintentar', (tester) async {
      _useTallScreen(tester);
      notifications.inboxFailure = const NetworkFailure();

      await tester.pumpWidget(
        _host(const NotificationsScreen(), notifications: notifications),
      );
      await _settle(tester);

      expect(find.byType(ErrorStateView), findsOneWidget);
    });
  });

  group('Campana', () {
    testWidgets('sin nada sin leer no muestra insignia', (tester) async {
      await tester.pumpWidget(
        _host(
          const Scaffold(body: NotificationBell()),
          notifications: notifications,
        ),
      );
      await _settle(tester);

      expect(find.text('0'), findsNothing);
    });

    testWidgets('muestra la cantidad sin leer', (tester) async {
      notifications.unread = 7;

      await tester.pumpWidget(
        _host(
          const Scaffold(body: NotificationBell()),
          notifications: notifications,
        ),
      );
      await _settle(tester);

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('acota en 99+', (tester) async {
      notifications.unread = 250;

      await tester.pumpWidget(
        _host(
          const Scaffold(body: NotificationBell()),
          notifications: notifications,
        ),
      );
      await _settle(tester);

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('lleva a la bandeja', (tester) async {
      await tester.pumpWidget(
        _host(
          const Scaffold(body: NotificationBell()),
          notifications: notifications,
        ),
      );
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await _settle(tester);

      expect(find.text('bandeja'), findsOneWidget);
    });
  });

  group('Preferencias', () {
    late _FakeUserRepository users;

    setUp(() => users = _FakeUserRepository());

    testWidgets('apagar un interruptor lo guarda en el perfil', (tester) async {
      // El criterio de aceptación: desactivar un tipo lo detiene de verdad,
      // porque el servidor lee este mismo campo antes de enviar.
      _useTallScreen(tester);

      await tester.pumpWidget(
        _host(
          const NotificationSettingsScreen(),
          notifications: notifications,
          users: users,
        ),
      );
      await _settle(tester);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Actividad de la comunidad'),
      );
      await _settle(tester);

      expect(users.saved?.notifications.socialActivity, isFalse);
    });

    testWidgets('guardar no pisa el resto de los ajustes', (tester) async {
      // Mandar el bloque entero desde cero borraría el tema y el huso horario.
      _useTallScreen(tester);

      await tester.pumpWidget(
        _host(
          const NotificationSettingsScreen(),
          notifications: notifications,
          users: users,
          profile: AppUser(
            uid: 'u1',
            email: 'ana@ascend.app',
            displayName: 'Ana',
            handle: 'ana',
            createdAt: DateTime.utc(2026),
            settings: const UserSettings(
              themeMode: 'dark',
              timezone: 'Europe/Madrid',
            ),
          ),
        ),
      );
      await _settle(tester);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Racha en riesgo'));
      await _settle(tester);

      expect(users.saved?.themeMode, 'dark');
      expect(users.saved?.timezone, 'Europe/Madrid');
      expect(users.saved?.notifications.streakAlerts, isFalse);
    });

    testWidgets('el horario de silencio se puede apagar', (tester) async {
      // `copyWith` no puede poner `null`: si el formulario lo usara, el
      // silencio quedaría encendido para siempre.
      _useTallScreen(tester);

      await tester.pumpWidget(
        _host(
          const NotificationSettingsScreen(),
          notifications: notifications,
          users: users,
          profile: _user(
            notifications: const NotificationSettings(
              quietHoursStart: '22:00',
              quietHoursEnd: '07:00',
            ),
          ),
        ),
      );
      await _settle(tester);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Activar horario de silencio'),
      );
      await _settle(tester);

      expect(users.saved?.notifications.quietHoursStart, isNull);
      expect(users.saved?.notifications.quietHoursEnd, isNull);
    });

    testWidgets('sin permiso del sistema lo advierte', (tester) async {
      // Sin esto alguien activa todo y sigue sin recibir nada, sin entender
      // por qué.
      _useTallScreen(tester);
      notifications.permission = NotificationPermission.denied;

      await tester.pumpWidget(
        _host(
          const NotificationSettingsScreen(),
          notifications: notifications,
          users: users,
        ),
      );
      await _settle(tester);

      expect(find.textContaining('bloqueados para Ascend'), findsOneWidget);
    });

    testWidgets('dice que la moderación llega siempre', (tester) async {
      _useTallScreen(tester);

      await tester.pumpWidget(
        _host(
          const NotificationSettingsScreen(),
          notifications: notifications,
          users: users,
        ),
      );
      await _settle(tester);

      expect(find.textContaining('moderación'), findsOneWidget);
    });
  });
}
