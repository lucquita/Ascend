import 'package:ascend_admin/features/audit/presentation/audit_screen.dart';
import 'package:ascend_admin/features/auth/application/admin_session.dart';
import 'package:ascend_admin/features/auth/presentation/admin_login_screen.dart';
import 'package:ascend_admin/features/catalog/presentation/categories_screen.dart';
import 'package:ascend_admin/features/dashboard/presentation/dashboard_screen.dart';
import 'package:ascend_admin/features/moderation/presentation/reports_screen.dart';
import 'package:ascend_admin/features/users/presentation/users_screen.dart';
import 'package:ascend_admin/shell/admin_placeholder.dart';
import 'package:ascend_admin/shell/admin_shell.dart';
import 'package:ascend_core/ascend_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Rutas del panel.
abstract final class AdminRoutes {
  /// Login de administrador.
  static const String login = '/login';

  /// Acceso denegado.
  static const String unauthorized = '/unauthorized';

  /// Panel principal.
  static const String dashboard = '/admin/dashboard';

  /// Gestión de usuarios.
  static const String users = '/admin/users';

  /// Explorador de objetivos.
  static const String goals = '/admin/goals';

  /// Plantillas de misiones.
  static const String missions = '/admin/missions';

  /// Moderación de publicaciones.
  static const String posts = '/admin/posts';

  /// Bandeja de reportes.
  static const String reports = '/admin/reports';

  /// Categorías.
  static const String categories = '/admin/categories';

  /// Analíticas.
  static const String analytics = '/admin/analytics';

  /// Configuración.
  static const String config = '/admin/config';

  /// Registro de auditoría.
  static const String audit = '/admin/audit';
}

/// Router del panel.
///
/// El guard se apoya en [adminSessionProvider], que lee el claim `role` del
/// token. Es una comodidad de navegación, **no** el control de acceso: las
/// reglas de Firestore vuelven a validar el mismo claim en cada lectura, así
/// que un cliente manipulado llega a un panel que no puede leer nada.
final Provider<GoRouter> adminRouterProvider = Provider<GoRouter>((ref) {
  // Sin `refreshListenable` el guard no se reevalúa al entrar o salir: la
  // pantalla anterior quedaría a la vista hasta la siguiente navegación.
  final notifier = _AdminSessionRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: AdminRoutes.dashboard,
    debugLogDiagnostics: !AppFlavor.current.isProd,
    refreshListenable: notifier,
    redirect: (BuildContext context, GoRouterState state) {
      final session = ref.read(adminSessionProvider);
      final location = state.matchedLocation;

      return switch (session) {
        // Mientras se restaura la sesión no se redirige: decidir antes de
        // tiempo hace parpadear el login en cada recarga de la página.
        AdminSessionState.unknown => null,
        AdminSessionState.signedOut =>
          location == AdminRoutes.login ? null : AdminRoutes.login,
        AdminSessionState.notAdmin || AdminSessionState.suspended =>
          location == AdminRoutes.unauthorized
              ? null
              : AdminRoutes.unauthorized,
        // Ya adentro, el login y la pantalla de rechazo no tienen sentido.
        AdminSessionState.ready =>
          location == AdminRoutes.login || location == AdminRoutes.unauthorized
              ? AdminRoutes.dashboard
              : null,
      };
    },
    errorBuilder: (BuildContext context, GoRouterState state) =>
        AdminPlaceholder(
          title: 'Página no encontrada',
          description: 'La ruta ${state.uri} no existe en el panel.',
          icon: Icons.explore_off_rounded,
          standalone: true,
        ),
    routes: <RouteBase>[
      GoRoute(
        path: AdminRoutes.login,
        builder: (_, _) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: AdminRoutes.unauthorized,
        builder: (BuildContext context, _) => Consumer(
          builder: (_, WidgetRef ref, _) =>
              AdminUnauthorizedScreen(reason: ref.watch(adminSessionProvider)),
        ),
      ),
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            AdminShell(location: state.matchedLocation, child: child),
        routes: <RouteBase>[
          for (final section in AdminSection.values)
            GoRoute(
              path: section.path,
              // Las secciones construidas tienen su pantalla; el resto sigue
              // siendo un placeholder que dice en qué fase llega, en vez de
              // desaparecer del menú y hacer creer que no existen.
              builder: (_, _) => switch (section) {
                AdminSection.dashboard => const DashboardScreen(),
                AdminSection.users => const UsersScreen(),
                AdminSection.reports => const ReportsScreen(),
                AdminSection.categories => const CategoriesScreen(),
                AdminSection.audit => const AuditScreen(),
                _ => AdminPlaceholder(
                  title: section.label,
                  description: section.description,
                  phase: section.phase,
                  icon: section.icon,
                ),
              },
            ),
        ],
      ),
    ],
  );
}, name: 'adminRouter');

/// Reevalúa el guard cuando cambia quién está usando el panel.
class _AdminSessionRefreshNotifier extends ChangeNotifier {
  _AdminSessionRefreshNotifier(this._ref) {
    _subscription = _ref.listen<AdminSessionState>(
      adminSessionProvider,
      // No se notifica de entrada: el router ya lee el estado en su primer
      // redirect, y hacerlo durante la construcción provoca un rebuild
      // reentrante.
      (_, _) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AdminSessionState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

/// Secciones del panel. Alimentan a la vez el menú lateral y las rutas, así que
/// es imposible que se desincronicen.
enum AdminSection {
  /// KPIs generales.
  dashboard(
    AdminRoutes.dashboard,
    'Dashboard',
    'Usuarios activos, misiones completadas, Aura otorgada y costo de IA.',
    Icons.dashboard_rounded,
  ),

  /// Gestión de personas.
  users(
    AdminRoutes.users,
    'Usuarios',
    'Buscar, inspeccionar, suspender y asignar roles.',
    Icons.people_rounded,
  ),

  /// Objetivos de todas las personas.
  goals(
    AdminRoutes.goals,
    'Objetivos',
    'Explorador global de objetivos.',
    Icons.flag_rounded,
    phase: 'Fase 10',
  ),

  /// Plantillas de misiones.
  missions(
    AdminRoutes.missions,
    'Misiones',
    'Biblioteca de plantillas por categoría.',
    Icons.task_alt_rounded,
    phase: 'Fase 10',
  ),

  /// Moderación de contenido.
  posts(
    AdminRoutes.posts,
    'Publicaciones',
    'Moderación del feed y de los comentarios.',
    Icons.article_rounded,
    phase: 'Fase 10',
  ),

  /// Cola de reportes.
  reports(
    AdminRoutes.reports,
    'Reportes',
    'Bandeja de moderación priorizada.',
    Icons.flag_circle_rounded,
  ),

  /// Catálogo de categorías.
  categories(
    AdminRoutes.categories,
    'Categorías',
    'Alta, baja y modificación del catálogo.',
    Icons.category_rounded,
  ),

  /// Métricas de producto.
  analytics(
    AdminRoutes.analytics,
    'Analíticas',
    'Retención, embudo de activación y costos.',
    Icons.insights_rounded,
    phase: 'Fase 10',
  ),

  /// Configuración remota.
  config(
    AdminRoutes.config,
    'Configuración',
    'Reglas de Aura, feature flags y versión mínima.',
    Icons.tune_rounded,
    phase: 'Fase 10',
  ),

  /// Auditoría.
  audit(
    AdminRoutes.audit,
    'Auditoría',
    'Registro de todas las acciones administrativas.',
    Icons.receipt_long_rounded,
  );

  const AdminSection(
    this.path,
    this.label,
    this.description,
    this.icon, {
    this.phase,
  });

  /// Ruta de la sección.
  final String path;

  /// Nombre en el menú.
  final String label;

  /// Qué hace la sección.
  final String description;

  /// Icono del menú.
  final IconData icon;

  /// Fase en la que se implementa, si todavía es un placeholder.
  ///
  /// `null` significa que la sección ya está construida. Sirve además para que
  /// el menú marque visualmente lo que todavía no existe, en vez de dejar que
  /// alguien descubra el placeholder recién al hacer clic.
  final String? phase;

  /// `true` si la sección ya tiene funcionalidad real.
  bool get isImplemented => phase == null;
}
