import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_mobile/features/ai/presentation/screens/ai_wizard_screen.dart';
import 'package:ascend_mobile/features/aura/presentation/screens/aura_screen.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/features/auth/presentation/screens/complete_profile_screen.dart';
import 'package:ascend_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:ascend_mobile/features/auth/presentation/screens/password_recovery_screens.dart';
import 'package:ascend_mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:ascend_mobile/features/community/presentation/screens/create_post_screen.dart';
import 'package:ascend_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:ascend_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:ascend_mobile/features/goals/presentation/screens/goal_detail_screen.dart';
import 'package:ascend_mobile/features/goals/presentation/screens/goal_form_screen.dart';
import 'package:ascend_mobile/features/goals/presentation/screens/goals_list_screen.dart';
import 'package:ascend_mobile/features/missions/presentation/screens/mission_detail_screen.dart';
import 'package:ascend_mobile/features/missions/presentation/screens/mission_form_screen.dart';
import 'package:ascend_mobile/features/missions/presentation/screens/mission_history_screen.dart';
import 'package:ascend_mobile/features/missions/presentation/screens/pick_goal_screen.dart';
import 'package:ascend_mobile/features/missions/presentation/screens/today_screen.dart';
import 'package:ascend_mobile/features/notifications/presentation/screens/notification_settings_screen.dart';
import 'package:ascend_mobile/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:ascend_mobile/features/placeholder/placeholder_screen.dart';
import 'package:ascend_mobile/features/profile/presentation/screens/profile_edit_screen.dart';
import 'package:ascend_mobile/features/profile/presentation/screens/profile_screen.dart';
import 'package:ascend_mobile/features/shell/app_shell.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// `SessionState` y `sessionStateProvider` viven ahora en la feature de auth,
// donde se derivan de Firebase Auth. Se reexportan desde acá para que nada de
// lo que ya los importaba —incluidos los tests de la Fase 0— tenga que cambiar.
export 'package:ascend_mobile/features/auth/application/session.dart'
    show SessionState, sessionStateProvider;

/// Claves de navegador. La raíz muestra pantallas a pantalla completa; la del
/// shell mantiene la barra inferior visible.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Router de la aplicación.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  // `refreshListenable` es lo que hace que el guard se reevalúe cuando cambia
  // la sesión. Sin esto, cerrar sesión dejaría la pantalla anterior a la vista
  // hasta la siguiente navegación manual.
  final sessionNotifier = _SessionRefreshNotifier(ref);
  ref.onDispose(sessionNotifier.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    debugLogDiagnostics: !AppFlavor.current.isProd,
    refreshListenable: sessionNotifier,

    // El guard central. Devolver `null` significa "dejá pasar".
    redirect: (context, state) {
      final session = ref.read(sessionStateProvider);
      final location = state.matchedLocation;

      final isAuthRoute =
          location == Routes.login ||
          location == Routes.register ||
          location == Routes.forgotPassword ||
          location == Routes.resetSent ||
          location == Routes.verifyEmail;

      return switch (session) {
        // Mientras se restaura la sesión no se redirige a ningún lado: evita
        // el parpadeo de login que aparece si decidís antes de tiempo.
        SessionState.unknown => null,
        SessionState.signedOut => isAuthRoute ? null : Routes.login,
        // Cada estado intermedio tiene una única salida posible, y desde ella
        // no se redirige: si no, la pantalla que resuelve el problema se
        // redirigiría a sí misma en bucle.
        SessionState.blocked =>
          location == Routes.blocked ? null : Routes.blocked,
        SessionState.needsProfile =>
          location == Routes.completeProfile ? null : Routes.completeProfile,
        SessionState.needsEmailVerification =>
          location == Routes.verifyEmail ? null : Routes.verifyEmail,
        SessionState.needsOnboarding =>
          location == Routes.onboarding ? null : Routes.onboarding,
        SessionState.ready =>
          isAuthRoute ||
                  location == Routes.onboarding ||
                  location == Routes.blocked ||
                  location == Routes.completeProfile
              ? Routes.home
              : null,
      };
    },

    errorBuilder: (context, state) => PlaceholderScreen(
      title: 'Página no encontrada',
      subtitle: 'La ruta ${state.uri} no existe.',
      icon: Icons.explore_off_rounded,
    ),

    routes: <RouteBase>[
      // ── Autenticación (fuera del shell) ─────────────────────────────
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.resetSent,
        builder: (_, _) => const ResetSentScreen(),
      ),
      GoRoute(
        path: Routes.verifyEmail,
        builder: (_, _) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: Routes.completeProfile,
        builder: (_, _) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const PlaceholderScreen(
          title: 'Onboarding',
          phase: 'Fase 1',
          icon: Icons.waving_hand_rounded,
        ),
      ),
      GoRoute(path: Routes.blocked, builder: (_, _) => const BlockedScreen()),

      // ── Shell con barra inferior ────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.home,
                builder: (_, _) => const TodayScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'all-missions',
                    builder: (_, _) => const PlaceholderScreen(
                      title: 'Todas las misiones',
                      phase: 'Fase 2',
                      icon: Icons.checklist_rounded,
                    ),
                  ),
                  GoRoute(
                    path: 'streak',
                    builder: (_, _) => const PlaceholderScreen(
                      title: 'Tu racha',
                      phase: 'Fase 4',
                      icon: Icons.local_fire_department_rounded,
                    ),
                  ),
                  GoRoute(
                    path: 'ai-suggestions',
                    builder: (_, _) => const PlaceholderScreen(
                      title: 'Sugerencias de la IA',
                      phase: 'Fase 5',
                      icon: Icons.auto_awesome_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.goals,
                builder: (_, _) => const GoalsListScreen(),
                routes: <RouteBase>[
                  // `new` va antes que `:goalId`: GoRouter evalúa en orden y
                  // si la ruta paramétrica fuera primero, /goals/new abriría
                  // el detalle de un objetivo con id "new".
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, _) => const GoalFormScreen(),
                  ),
                  // El asistente con IA es un camino alternativo al alta
                  // manual, no un reemplazo: quien prefiere escribir su plan
                  // sigue usando /goals/new.
                  GoRoute(
                    path: 'new/generating',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, _) => const AiWizardScreen(),
                  ),
                  GoRoute(
                    path: ':goalId',
                    builder: (_, state) => GoalDetailScreen(
                      goalId: state.pathParameters['goalId'] ?? '',
                    ),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (_, state) => GoalFormScreen.edit(
                          goalId: state.pathParameters['goalId'] ?? '',
                        ),
                      ),
                      GoRoute(
                        path: 'missions/new',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (_, state) => MissionFormScreen(
                          goalId: state.pathParameters['goalId'] ?? '',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.community,
                builder: (_, _) => const FeedScreen(),
                routes: <RouteBase>[
                  // `create` va antes que `post/:postId`: GoRouter evalúa en
                  // orden.
                  GoRoute(
                    path: 'create',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, _) => const CreatePostScreen(),
                  ),
                  GoRoute(
                    path: 'post/:postId',
                    builder: (_, state) => PostDetailScreen(
                      postId: state.pathParameters['postId'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.profile,
                builder: (_, _) => const ProfileScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'edit',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, _) => const ProfileEditScreen(),
                  ),
                  GoRoute(path: 'aura', builder: (_, _) => const AuraScreen()),
                  GoRoute(
                    path: 'stats',
                    builder: (_, _) => const PlaceholderScreen(
                      title: 'Estadísticas',
                      phase: 'Fase 4',
                      icon: Icons.insights_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // ── Pantalla completa, por encima del shell ─────────────────────
      // El "+" de la pantalla principal no sabe a qué objetivo apunta, así que
      // primero se elige uno: una misión no existe sin objetivo.
      GoRoute(
        path: Routes.missionNew,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PickGoalScreen(),
      ),
      // `history` va antes que `:missionId`: GoRouter evalúa en orden y si la
      // ruta paramétrica fuera primero, /missions/history abriría el detalle de
      // una misión con id "history".
      GoRoute(
        path: Routes.missionHistory,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const MissionHistoryScreen(),
      ),
      GoRoute(
        path: '/missions/:missionId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => MissionDetailScreen(
          missionId: state.pathParameters['missionId'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.notifications,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.settingsNotifications,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PlaceholderScreen(
          title: 'Ajustes',
          phase: 'Fase 1',
          icon: Icons.settings_rounded,
        ),
      ),
      GoRoute(
        path: Routes.forceUpdate,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PlaceholderScreen(
          title: 'Actualizá Ascend',
          subtitle: 'Esta versión ya no está soportada.',
          phase: 'Fase 9',
          icon: Icons.system_update_rounded,
        ),
      ),
      GoRoute(
        path: Routes.devTools,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const DevToolsScreen(),
      ),
    ],
  );
}, name: 'appRouter');

/// Avisa al router cada vez que cambia el estado de sesión.
///
/// GoRouter solo reevalúa `redirect` cuando navega o cuando este `Listenable`
/// notifica. Sin él, un cambio de sesión —cerrar sesión, verificar el email,
/// que el servidor suspenda la cuenta— no movería a nadie de su pantalla actual
/// hasta la siguiente navegación.
class _SessionRefreshNotifier extends ChangeNotifier {
  _SessionRefreshNotifier(this._ref) {
    _subscription = _ref.listen<SessionState>(
      sessionStateProvider,
      // No se notifica de entrada: el router ya lee el estado en su primer
      // redirect, y hacerlo durante la construcción provoca un rebuild
      // reentrante.
      (_, _) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<SessionState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
