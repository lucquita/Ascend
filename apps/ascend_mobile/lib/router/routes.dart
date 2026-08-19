/// Rutas de la aplicación como constantes tipadas.
///
/// Nunca se escriben strings de ruta sueltos en las pantallas: un `context.go`
/// con una ruta mal tipeada compila igual y falla en runtime. Centralizarlas
/// convierte ese error en un error de compilación.
abstract final class Routes {
  // ── Arranque y autenticación ──────────────────────────────────────────
  /// Puerta de entrada: decide a dónde mandar según el estado de sesión.
  static const String root = '/';

  /// Onboarding de bienvenida.
  static const String onboarding = '/onboarding';

  /// Inicio de sesión.
  static const String login = '/login';

  /// Registro.
  static const String register = '/register';

  /// Recuperación de contraseña.
  static const String forgotPassword = '/forgot-password';

  /// Confirmación de envío del correo de recuperación.
  static const String resetSent = '/reset-sent';

  /// Verificación de correo.
  static const String verifyEmail = '/verify-email';

  /// Cuenta suspendida.
  static const String blocked = '/blocked';

  /// Recuperación de un registro que quedó a medias: hay cuenta pero no perfil.
  static const String completeProfile = '/complete-profile';

  // ── Ramas del shell ───────────────────────────────────────────────────
  /// Pantalla "Hoy".
  static const String home = '/home';

  /// Lista de objetivos.
  static const String goals = '/goals';

  /// Feed de la comunidad.
  static const String community = '/community';

  /// Perfil propio.
  static const String profile = '/profile';

  // ── Hoy ───────────────────────────────────────────────────────────────
  /// Todas las misiones pendientes.
  static const String allMissions = '/home/all-missions';

  /// Detalle de la racha.
  static const String streak = '/home/streak';

  /// Sugerencias de la IA.
  static const String aiSuggestions = '/home/ai-suggestions';

  // ── Objetivos ─────────────────────────────────────────────────────────
  /// Asistente de creación de objetivo.
  static const String goalNew = '/goals/new';

  /// Pantalla de generación con IA.
  static const String goalGenerating = '/goals/new/generating';

  /// Revisión del plan generado.
  static const String goalReview = '/goals/new/review';

  /// Detalle de un objetivo.
  static String goalDetail(String id) => '/goals/$id';

  /// Edición de un objetivo.
  static String goalEdit(String id) => '/goals/$id/edit';

  /// Misiones de un objetivo.
  static String goalMissions(String id) => '/goals/$id/missions';

  /// Alta de una misión dentro de un objetivo.
  ///
  /// Cuelga del objetivo y no de `/missions` porque una misión no existe sin
  /// uno: el formulario necesita su título y su categoría para desnormalizarlos.
  static String goalMissionNew(String id) => '/goals/$id/missions/new';

  // ── Misiones ──────────────────────────────────────────────────────────
  /// Creación manual de misión.
  static const String missionNew = '/missions/new';

  /// Historial de misiones.
  static const String missionHistory = '/missions/history';

  /// Detalle de una misión.
  static String missionDetail(String id) => '/missions/$id';

  /// Captura de evidencia.
  static String missionEvidence(String id) => '/missions/$id/evidence';

  // ── Aura ──────────────────────────────────────────────────────────────
  /// Nivel y progreso de Aura.
  static const String aura = '/profile/aura';

  /// Historial del ledger de Aura.
  static const String auraHistory = '/profile/aura/history';

  /// Estadísticas.
  static const String stats = '/profile/stats';

  /// Logros.
  static const String achievements = '/profile/achievements';

  /// Ranking.
  static const String leaderboard = '/leaderboard';

  // ── Comunidad ─────────────────────────────────────────────────────────
  /// Creación de publicación.
  static const String createPost = '/community/create';

  /// Detalle de publicación.
  static String postDetail(String id) => '/community/post/$id';

  /// Comentarios de una publicación.
  static String postComments(String id) => '/community/post/$id/comments';

  /// Perfil público de otra persona.
  static String publicProfile(String handle) => '/u/$handle';

  /// Formulario de reporte.
  static String report(String type, String id) => '/report/$type/$id';

  // ── Perfil y ajustes ──────────────────────────────────────────────────
  /// Edición del perfil.
  static const String profileEdit = '/profile/edit';

  /// Bandeja de notificaciones.
  static const String notifications = '/notifications';

  /// Buscador.
  static const String search = '/search';

  /// Índice de ajustes.
  static const String settings = '/settings';

  /// Ajustes de cuenta.
  static const String settingsAccount = '/settings/account';

  /// Ajustes de notificaciones.
  static const String settingsNotifications = '/settings/notifications';

  /// Ajustes de privacidad.
  static const String settingsPrivacy = '/settings/privacy';

  /// Apariencia e idioma.
  static const String settingsAppearance = '/settings/appearance';

  /// Textos legales.
  static const String settingsLegal = '/settings/legal';

  /// Eliminación de cuenta.
  static const String deleteAccount = '/settings/delete-account';

  // ── Estados bloqueantes ───────────────────────────────────────────────
  /// Actualización obligatoria.
  static const String forceUpdate = '/force-update';

  /// Mantenimiento programado.
  static const String maintenance = '/maintenance';

  /// Pantalla de diagnóstico (solo fuera de producción).
  static const String devTools = '/dev-tools';
}
