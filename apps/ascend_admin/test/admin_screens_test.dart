import 'package:ascend_admin/features/audit/presentation/audit_screen.dart';
import 'package:ascend_admin/features/dashboard/presentation/dashboard_screen.dart';
import 'package:ascend_admin/features/moderation/presentation/reports_screen.dart';
import 'package:ascend_admin/features/users/presentation/users_screen.dart';
import 'package:ascend_admin/shared/admin_widgets.dart';
import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
// `Page` existe en el dominio (paginación) y en Flutter (navegación): se oculta
// el de Flutter y se usa el del dominio con prefijo donde hace falta.
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Doble del repositorio de administración.
///
/// Anota lo que recibe: la mitad de lo que hay que verificar en un panel no es
/// lo que se pinta sino qué se le pidió al servidor.
class _FakeAdminRepository implements AdminRepository {
  List<AppUser> users = const <AppUser>[];
  List<Report> reports = const <Report>[];
  List<AuditEntry> audit = const <AuditEntry>[];
  AdminStats? stats;
  Failure? statsFailure;
  Failure? actionFailure;
  bool hasMore = false;

  int listCalls = 0;
  ({String uid, UserRole role})? roleChange;
  ({String uid, UserStatus status, String? reason})? statusChange;
  ({String id, ModerationAction action, String? note})? resolution;
  Category? savedCategory;

  @override
  Stream<Result<AdminStats>> watchStats() => Stream<Result<AdminStats>>.value(
    statsFailure != null
        ? Failed<AdminStats>(statsFailure!)
        : Success<AdminStats>(stats ?? AdminStats(generatedAt: DateTime.now())),
  );

  @override
  Future<Result<Paginated<AppUser>>> listUsers({
    Object? cursor,
    int limit = 25,
  }) async {
    listCalls++;
    return Success<Paginated<AppUser>>(
      Paginated<AppUser>(items: users, hasMore: hasMore),
    );
  }

  @override
  Stream<Result<List<Report>>> watchOpenReports({int limit = 50}) =>
      Stream<Result<List<Report>>>.value(
        Success<List<Report>>(sortModerationQueue(reports)),
      );

  @override
  Stream<Result<List<AuditEntry>>> watchAuditLog({int limit = 100}) =>
      Stream<Result<List<AuditEntry>>>.value(Success<List<AuditEntry>>(audit));

  @override
  Future<Result<void>> setUserRole({
    required String targetUid,
    required UserRole role,
    String? reason,
  }) async {
    roleChange = (uid: targetUid, role: role);
    return actionFailure == null
        ? const Success<void>(null)
        : Failed<void>(actionFailure!);
  }

  @override
  Future<Result<void>> setUserStatus({
    required String targetUid,
    required UserStatus status,
    String? reason,
  }) async {
    statusChange = (uid: targetUid, status: status, reason: reason);
    return actionFailure == null
        ? const Success<void>(null)
        : Failed<void>(actionFailure!);
  }

  @override
  Future<Result<void>> resolveReport({
    required String reportId,
    required ModerationAction action,
    String? note,
  }) async {
    resolution = (id: reportId, action: action, note: note);
    return actionFailure == null
        ? const Success<void>(null)
        : Failed<void>(actionFailure!);
  }

  @override
  Future<Result<void>> saveCategory(Category category) async {
    savedCategory = category;
    return const Success<void>(null);
  }
}

final AppUser _admin = AppUser(
  uid: 'admin1',
  email: 'admin@ascend.app',
  displayName: 'Admin',
  handle: 'admin',
  createdAt: DateTime.utc(2026),
  role: UserRole.admin,
  emailVerified: true,
);

AppUser _person({
  String uid = 'u1',
  String name = 'Ana Pérez',
  String handle = 'ana',
  UserRole role = UserRole.user,
  UserStatus status = UserStatus.active,
}) => AppUser(
  uid: uid,
  email: '$handle@ascend.app',
  displayName: name,
  handle: handle,
  createdAt: DateTime.utc(2026),
  role: role,
  status: status,
);

Report _report({
  String id = 'r1',
  ReportReason reason = ReportReason.spam,
  int daysAgo = 0,
}) => Report(
  id: id,
  reporterId: 'u9',
  targetType: 'post',
  targetId: 'p1',
  reason: reason,
  createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
);

/// Monta una pantalla del panel con el repositorio de mentira enchufado.
///
/// El tipo `Override` no lo exporta `flutter_riverpod`, así que la lista se
/// construye acá dentro.
Widget _host(Widget child, _FakeAdminRepository admin) => ProviderScope(
  overrides: [
    adminRepositoryProvider.overrideWithValue(admin),
    authStateProvider.overrideWith((ref) => Stream<AppUser?>.value(_admin)),
  ],
  child: MaterialApp(
    theme: AscendTheme.light,
    home: Scaffold(body: child),
  ),
);

/// Deja que los streams emitan sin esperar a que todo se asiente.
///
/// No se usa `pumpAndSettle`: los skeletons tienen un shimmer infinito y
/// "asentar" nunca ocurre.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(Duration.zero);
  // 300 ms cubren la transición de un diálogo y el cierre del menú emergente.
  // Menos que eso deja el diálogo a mitad de camino y `find` no lo encuentra.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late _FakeAdminRepository admin;

  setUp(() => admin = _FakeAdminRepository());

  group('Dashboard', () {
    testWidgets('muestra los KPIs agregados', (tester) async {
      _useTallScreen(tester);
      admin.stats = AdminStats(
        generatedAt: DateTime.now(),
        usersTotal: 1200,
        usersActive7d: 300,
      );

      await tester.pumpWidget(_host(const DashboardScreen(), admin));
      await _settle(tester);

      expect(find.text('1200'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      expect(find.text('No hay reportes pendientes.'), findsOneWidget);
    });

    testWidgets('avisa cuando las métricas quedaron viejas', (tester) async {
      // Mostrar números de hace días como si fueran de hoy es peor que no
      // mostrar nada: alguien decide con ellos.
      _useTallScreen(tester);
      admin.stats = AdminStats(
        generatedAt: DateTime.now().subtract(const Duration(days: 4)),
        usersTotal: 10,
      );

      await tester.pumpWidget(_host(const DashboardScreen(), admin));
      await _settle(tester);

      expect(find.textContaining('agregación diaria'), findsOneWidget);
    });

    testWidgets('sin métricas calculadas lo dice, no muestra ceros a secas', (
      tester,
    ) async {
      _useTallScreen(tester);
      admin.stats = AdminStats(
        generatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

      await tester.pumpWidget(_host(const DashboardScreen(), admin));
      await _settle(tester);

      expect(find.textContaining('aggregateStats'), findsOneWidget);
    });

    testWidgets('un fallo de lectura ofrece reintentar', (tester) async {
      _useTallScreen(tester);
      admin.statsFailure = const PermissionFailure();

      await tester.pumpWidget(_host(const DashboardScreen(), admin));
      await _settle(tester);

      expect(find.byType(ErrorStateView), findsOneWidget);
    });

    testWidgets('los reportes abiertos llevan a moderación', (tester) async {
      // Es el único número del dashboard que significa trabajo pendiente.
      _useTallScreen(tester);
      admin.stats = AdminStats(generatedAt: DateTime.now(), reportsOpen: 3);

      await tester.pumpWidget(_host(const DashboardScreen(), admin));
      await _settle(tester);

      expect(find.textContaining('3 reportes esperan'), findsOneWidget);
      expect(find.text('Ir a moderación'), findsOneWidget);
    });
  });

  group('Usuarios', () {
    testWidgets('lista las cuentas traídas', (tester) async {
      _useTallScreen(tester);
      admin.users = <AppUser>[_person(), _person(uid: 'u2', name: 'Bruno')];

      await tester.pumpWidget(_host(const UsersScreen(), admin));
      await _settle(tester);

      expect(find.text('Ana Pérez'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
    });

    testWidgets('el filtro de texto acota la tabla', (tester) async {
      _useTallScreen(tester);
      admin.users = <AppUser>[
        _person(),
        _person(uid: 'u2', name: 'Bruno', handle: 'bruno'),
      ];

      await tester.pumpWidget(_host(const UsersScreen(), admin));
      await _settle(tester);

      await tester.enterText(find.byType(TextField).first, 'bruno');
      // El debounce por defecto son 350 ms.
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);

      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Ana Pérez'), findsNothing);
    });

    testWidgets('marca a los administradores y a las suspendidas', (
      tester,
    ) async {
      _useTallScreen(tester);
      admin.users = <AppUser>[
        _person(role: UserRole.admin),
        _person(uid: 'u2', handle: 'b', status: UserStatus.suspended),
      ];

      await tester.pumpWidget(_host(const UsersScreen(), admin));
      await _settle(tester);

      // `widgetWithText` y no `find.text`: "admin" aparece también como opción
      // del filtro de rol, y el test tiene que mirar la insignia de la fila.
      expect(find.widgetWithText(AdminBadge, 'admin'), findsOneWidget);
      expect(find.widgetWithText(AdminBadge, 'suspendida'), findsOneWidget);
    });

    testWidgets('la propia cuenta no tiene acciones', (tester) async {
      // Quitarse el rol o suspenderse deja el panel sin quien lo administre.
      _useTallScreen(tester);
      admin.users = <AppUser>[
        _person(uid: 'admin1', name: 'Admin', handle: 'admin'),
      ];

      await tester.pumpWidget(_host(const UsersScreen(), admin));
      await _settle(tester);

      expect(find.text('Vos'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('dar rol de administrador pide confirmación', (tester) async {
      _useTallScreen(tester);
      admin.users = <AppUser>[_person()];

      await tester.pumpWidget(_host(const UsersScreen(), admin));
      await _settle(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await _settle(tester);
      await tester.tap(find.text('Hacer administrador'));
      await _settle(tester);

      expect(find.text('¿Dar acceso de administrador?'), findsOneWidget);
      // Todavía no se llamó a nada: solo se abrió el diálogo.
      expect(admin.roleChange, isNull);

      await tester.tap(find.text('Dar acceso'));
      await _settle(tester);

      expect(admin.roleChange?.uid, 'u1');
      expect(admin.roleChange?.role, UserRole.admin);
    });

    testWidgets('cancelar la confirmación no cambia nada', (tester) async {
      _useTallScreen(tester);
      admin.users = <AppUser>[_person()];

      await tester.pumpWidget(_host(const UsersScreen(), admin));
      await _settle(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await _settle(tester);
      await tester.tap(find.text('Hacer administrador'));
      await _settle(tester);
      await tester.tap(find.text('Cancelar'));
      await _settle(tester);

      expect(admin.roleChange, isNull);
    });

    testWidgets('suspender exige escribir un motivo', (tester) async {
      _useTallScreen(tester);
      admin.users = <AppUser>[_person()];

      await tester.pumpWidget(_host(const UsersScreen(), admin));
      await _settle(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await _settle(tester);
      await tester.tap(find.text('Suspender cuenta'));
      await _settle(tester);

      expect(find.text('¿Por qué se suspende?'), findsOneWidget);

      // Confirmar sin motivo no suspende.
      await tester.tap(find.text('Suspender'));
      await _settle(tester);
      expect(admin.statusChange, isNull);
    });

    testWidgets('con motivo, la suspensión llega al servidor', (tester) async {
      _useTallScreen(tester);
      admin.users = <AppUser>[_person()];

      await tester.pumpWidget(_host(const UsersScreen(), admin));
      await _settle(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await _settle(tester);
      await tester.tap(find.text('Suspender cuenta'));
      await _settle(tester);

      await tester.enterText(
        find.byType(TextField).last,
        'Acoso reiterado tras dos advertencias',
      );
      await tester.tap(find.text('Suspender'));
      await _settle(tester);

      expect(admin.statusChange?.status, UserStatus.suspended);
      expect(admin.statusChange?.reason, contains('Acoso'));
    });

    testWidgets('sin cuentas lo dice en vez de mostrar una tabla vacía', (
      tester,
    ) async {
      _useTallScreen(tester);

      await tester.pumpWidget(_host(const UsersScreen(), admin));
      await _settle(tester);

      expect(find.text('Todavía no hay cuentas'), findsOneWidget);
    });
  });

  group('Moderación', () {
    testWidgets('la cola pone primero lo grave', (tester) async {
      _useTallScreen(tester);
      admin.reports = <Report>[
        _report(id: 'spam', daysAgo: 9),
        _report(id: 'violencia', reason: ReportReason.violence),
      ];

      await tester.pumpWidget(_host(const ReportsScreen(), admin));
      await _settle(tester);

      final badges = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data)
          .whereType<String>()
          .toList();
      expect(
        badges.indexOf('violencia') < badges.indexOf('spam'),
        isTrue,
        reason: 'lo grave tiene que aparecer antes en el árbol',
      );
    });

    testWidgets('descartar resuelve sin pedir nada más', (tester) async {
      _useTallScreen(tester);
      admin.reports = <Report>[_report()];

      await tester.pumpWidget(_host(const ReportsScreen(), admin));
      await _settle(tester);

      await tester.tap(find.text('Descartar reporte'));
      await _settle(tester);

      expect(admin.resolution?.action, ModerationAction.dismiss);
    });

    testWidgets('suspender al autor exige un motivo', (tester) async {
      _useTallScreen(tester);
      admin.reports = <Report>[_report()];

      await tester.pumpWidget(_host(const ReportsScreen(), admin));
      await _settle(tester);

      await tester.tap(find.text('Ocultar y suspender'));
      await _settle(tester);

      expect(find.text('Ocultar y suspender'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Suspender'));
      await _settle(tester);

      expect(admin.resolution, isNull, reason: 'sin motivo no se suspende');
    });

    testWidgets('bandeja vacía es buena señal, no un error', (tester) async {
      _useTallScreen(tester);

      await tester.pumpWidget(_host(const ReportsScreen(), admin));
      await _settle(tester);

      expect(find.text('Nada pendiente'), findsOneWidget);
      expect(find.byType(ErrorStateView), findsNothing);
    });
  });

  group('Auditoría', () {
    testWidgets('lista las acciones registradas', (tester) async {
      _useTallScreen(tester);
      admin.audit = <AuditEntry>[
        AuditEntry(
          id: 'a1',
          action: 'set_user_role',
          actorUid: 'admin1',
          targetUid: 'u2',
          createdAt: DateTime.utc(2026, 8, 17),
        ),
      ];

      await tester.pumpWidget(_host(const AuditScreen(), admin));
      await _settle(tester);

      expect(find.text('Cambio de rol'), findsOneWidget);
      expect(find.textContaining('admin1'), findsOneWidget);
    });

    testWidgets('sin acciones lo explica', (tester) async {
      _useTallScreen(tester);

      await tester.pumpWidget(_host(const AuditScreen(), admin));
      await _settle(tester);

      expect(find.text('Sin acciones registradas'), findsOneWidget);
    });
  });
}
