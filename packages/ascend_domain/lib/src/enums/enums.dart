/// Enumeraciones del dominio de Ascend.
///
/// Cada una expone `wireValue`, que es la cadena exacta que viaja a Firestore,
/// y `fromWire`, que **nunca lanza**: ante un valor desconocido devuelve el
/// caso por defecto. Esto importa más de lo que parece: si mañana el backend
/// agrega un estado nuevo, las versiones viejas de la app lo degradan en vez de
/// romperse en las manos del usuario.
library;

/// Rol de una persona en el sistema.
enum UserRole {
  /// Usuario final.
  user('user'),

  /// Administrador: moderación, catálogos y configuración.
  admin('admin');

  const UserRole(this.wireValue);

  /// Valor tal como se guarda en el custom claim y en Firestore.
  final String wireValue;

  /// Convierte desde el valor persistido. Ante lo desconocido, [user].
  ///
  /// El sesgo hacia el rol menos privilegiado es deliberado: un error de
  /// parseo jamás debe conceder permisos de administrador.
  static UserRole fromWire(String? value) => switch (value) {
    'admin' => UserRole.admin,
    _ => UserRole.user,
  };

  /// `true` si es administrador.
  bool get isAdmin => this == UserRole.admin;
}

/// Estado de una cuenta.
enum UserStatus {
  /// Cuenta operativa.
  active('active'),

  /// Suspendida por moderación.
  suspended('suspended'),

  /// Marcada para eliminación.
  deleted('deleted');

  const UserStatus(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static UserStatus fromWire(String? value) => switch (value) {
    'suspended' => UserStatus.suspended,
    'deleted' => UserStatus.deleted,
    _ => UserStatus.active,
  };

  /// `true` si la cuenta puede operar con normalidad.
  bool get canOperate => this == UserStatus.active;
}

/// Estado de un objetivo.
enum GoalStatus {
  /// Creado pero todavía sin plan confirmado.
  draft('draft'),

  /// En curso.
  active('active'),

  /// Pausado por la persona.
  paused('paused'),

  /// Terminado.
  completed('completed'),

  /// Archivado: no aparece en las listas principales.
  archived('archived');

  const GoalStatus(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static GoalStatus fromWire(String? value) => switch (value) {
    'draft' => GoalStatus.draft,
    'paused' => GoalStatus.paused,
    'completed' => GoalStatus.completed,
    'archived' => GoalStatus.archived,
    _ => GoalStatus.active,
  };

  /// `true` si el objetivo cuenta para el progreso del día.
  bool get isOngoing => this == GoalStatus.active;

  /// `true` si admite modificaciones.
  bool get isEditable =>
      this == GoalStatus.draft ||
      this == GoalStatus.active ||
      this == GoalStatus.paused;
}

/// Estado de una misión.
enum MissionStatus {
  /// Pendiente.
  pending('pending'),

  /// Empezada.
  inProgress('in_progress'),

  /// Completada.
  completed('completed'),

  /// Salteada a propósito.
  skipped('skipped'),

  /// Vencida sin completar.
  expired('expired');

  const MissionStatus(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static MissionStatus fromWire(String? value) => switch (value) {
    'in_progress' => MissionStatus.inProgress,
    'completed' => MissionStatus.completed,
    'skipped' => MissionStatus.skipped,
    'expired' => MissionStatus.expired,
    _ => MissionStatus.pending,
  };

  /// `true` si todavía se puede trabajar en ella.
  bool get isOpen =>
      this == MissionStatus.pending || this == MissionStatus.inProgress;

  /// `true` si otorgó Aura.
  bool get isCompleted => this == MissionStatus.completed;
}

/// Dificultad de una misión. Determina la recompensa base de Aura.
enum MissionDifficulty {
  /// Menos de 15 minutos.
  easy('easy'),

  /// Entre 15 y 45 minutos.
  medium('medium'),

  /// Más de 45 minutos o alta exigencia.
  hard('hard');

  const MissionDifficulty(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static MissionDifficulty fromWire(String? value) => switch (value) {
    'easy' => MissionDifficulty.easy,
    'hard' => MissionDifficulty.hard,
    _ => MissionDifficulty.medium,
  };
}

/// Estado de revisión de una evidencia.
///
/// **Distinto de `EvidenceUploadStatus`**, que describe si el archivo llegó al
/// servidor. Este describe si el contenido fue aceptado. Una evidencia puede
/// estar `uploaded` y `rejected` a la vez: subió bien, pero no corresponde.
///
/// Solo entra en juego cuando la evidencia se publica en la comunidad: mientras
/// es privada —el default, ver `storage.rules`— no hay nada que moderar y queda
/// en [pending] sin molestar a nadie.
///
/// 🔒 **Lo escribe el servidor.** Si el cliente pudiera marcarse una evidencia
/// como aprobada, la moderación no existiría.
enum EvidenceReviewStatus {
  /// Sin revisar. Es el estado normal de una evidencia privada.
  pending('pending'),

  /// Revisada y aceptada.
  approved('approved'),

  /// Rechazada por moderación: no acredita el logro.
  rejected('rejected');

  const EvidenceReviewStatus(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido. Ante lo desconocido, [pending].
  static EvidenceReviewStatus fromWire(String? value) => switch (value) {
    'approved' => EvidenceReviewStatus.approved,
    'rejected' => EvidenceReviewStatus.rejected,
    _ => EvidenceReviewStatus.pending,
  };

  /// `true` si la evidencia fue rechazada.
  bool get isRejected => this == EvidenceReviewStatus.rejected;
}

/// Costo económico estimado de una misión.
///
/// Existe porque el producto propone experiencias reales, no solo hábitos: una
/// misión puede ser "salir a correr" o "ir a un taller de cerámica". Sin este
/// dato, alguien filtra misiones que no puede pagar y la app deja de servirle.
///
/// **No influye en la recompensa de Aura.** Pagar más no puede comprar
/// progreso: eso convertiría la gamificación en un ranking de poder
/// adquisitivo. La recompensa la determina [MissionDifficulty].
enum MissionBudget {
  /// Sin costo.
  free('free'),

  /// Costo bajo.
  low('low'),

  /// Costo medio.
  medium('medium'),

  /// Costo alto.
  high('high');

  const MissionBudget(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido. Ante lo desconocido, [free].
  ///
  /// El sesgo hacia "gratis" es deliberado: si un valor se corrompe, es
  /// preferible mostrar de más en un filtro de presupuesto que esconderle a
  /// alguien una misión que sí podía hacer.
  static MissionBudget fromWire(String? value) => switch (value) {
    'low' => MissionBudget.low,
    'medium' => MissionBudget.medium,
    'high' => MissionBudget.high,
    _ => MissionBudget.free,
  };

  /// `true` si no requiere gastar dinero.
  bool get isFree => this == MissionBudget.free;
}

/// Tipo de publicación del feed.
enum PostType {
  /// Misión completada.
  missionCompleted('mission_completed'),

  /// Objetivo completado.
  goalCompleted('goal_completed'),

  /// Hito intermedio alcanzado.
  milestone('milestone'),

  /// Reflexión libre (único tipo que no exige un logro asociado).
  reflection('reflection');

  const PostType(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static PostType fromWire(String? value) => switch (value) {
    'goal_completed' => PostType.goalCompleted,
    'milestone' => PostType.milestone,
    'reflection' => PostType.reflection,
    _ => PostType.missionCompleted,
  };

  /// `true` si el tipo obliga a referenciar un logro real.
  ///
  /// Es la premisa del producto —el feed solo muestra logros reales— expresada
  /// como regla de dominio, no como detalle de la interfaz.
  bool get requiresSource => this != PostType.reflection;
}

/// Estado de moderación de un contenido.
enum ModerationStatus {
  /// Visible en el feed.
  visible('visible'),

  /// Oculto preventivamente a la espera de revisión.
  underReview('under_review'),

  /// Oculto por decisión de moderación.
  hidden('hidden'),

  /// Eliminado.
  removed('removed');

  const ModerationStatus(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static ModerationStatus fromWire(String? value) => switch (value) {
    'under_review' => ModerationStatus.underReview,
    'hidden' => ModerationStatus.hidden,
    'removed' => ModerationStatus.removed,
    _ => ModerationStatus.visible,
  };

  /// `true` si el contenido puede aparecer en el feed público.
  bool get isPublic => this == ModerationStatus.visible;
}

/// Motivo de un reporte.
enum ReportReason {
  /// Spam o contenido repetido.
  spam('spam'),

  /// Acoso o agresión.
  harassment('harassment'),

  /// Contenido sexual o violento.
  nsfw('nsfw'),

  /// Logro falso: evidencia que no corresponde.
  fakeAchievement('fake_achievement'),

  /// Violencia.
  violence('violence'),

  /// Otro.
  other('other');

  const ReportReason(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static ReportReason fromWire(String? value) => switch (value) {
    'harassment' => ReportReason.harassment,
    'nsfw' => ReportReason.nsfw,
    'fake_achievement' => ReportReason.fakeAchievement,
    'violence' => ReportReason.violence,
    'spam' => ReportReason.spam,
    _ => ReportReason.other,
  };
}

/// Motivo por el que se otorgó o quitó Aura.
enum AuraReason {
  /// Misión completada.
  missionCompleted('mission_completed'),

  /// Objetivo completado.
  goalCompleted('goal_completed'),

  /// Hito alcanzado.
  milestone('milestone'),

  /// Bonificación por racha.
  streakBonus('streak_bonus'),

  /// Logro desbloqueado.
  achievement('achievement'),

  /// Ingreso diario.
  dailyLogin('daily_login'),

  /// Penalización por moderación.
  penalty('penalty'),

  /// Ajuste manual de un administrador.
  adminAdjustment('admin_adjustment');

  const AuraReason(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static AuraReason fromWire(String? value) => switch (value) {
    'goal_completed' => AuraReason.goalCompleted,
    'milestone' => AuraReason.milestone,
    'streak_bonus' => AuraReason.streakBonus,
    'achievement' => AuraReason.achievement,
    'daily_login' => AuraReason.dailyLogin,
    'penalty' => AuraReason.penalty,
    'admin_adjustment' => AuraReason.adminAdjustment,
    _ => AuraReason.missionCompleted,
  };
}

/// Visibilidad de un perfil o publicación.
enum Visibility {
  /// Visible para cualquier persona autenticada.
  public('public'),

  /// Visible solo para quienes te siguen.
  followers('followers'),

  /// Solo para vos.
  private('private');

  const Visibility(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  ///
  /// Ante un valor desconocido devuelve [private]: en privacidad, el default
  /// seguro es el más restrictivo.
  static Visibility fromWire(String? value) => switch (value) {
    'public' => Visibility.public,
    'followers' => Visibility.followers,
    _ => Visibility.private,
  };
}

/// Tipo de notificación.
enum NotificationType {
  /// Recordatorio de misión.
  missionReminder('mission_reminder'),

  /// Aviso de racha en riesgo.
  streakWarning('streak_warning'),

  /// Aura ganada.
  auraGained('aura_gained'),

  /// Subida de nivel.
  levelUp('level_up'),

  /// Nuevo like.
  newLike('new_like'),

  /// Nuevo comentario.
  newComment('new_comment'),

  /// Nuevo seguidor.
  newFollower('new_follower'),

  /// Sugerencia generada por la IA.
  aiSuggestion('ai_suggestion'),

  /// Acción de moderación sobre tu contenido.
  moderationAction('moderation_action'),

  /// Anuncio del equipo.
  system('system');

  const NotificationType(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static NotificationType fromWire(String? value) => switch (value) {
    'streak_warning' => NotificationType.streakWarning,
    'aura_gained' => NotificationType.auraGained,
    'level_up' => NotificationType.levelUp,
    'new_like' => NotificationType.newLike,
    'new_comment' => NotificationType.newComment,
    'new_follower' => NotificationType.newFollower,
    'ai_suggestion' => NotificationType.aiSuggestion,
    'moderation_action' => NotificationType.moderationAction,
    'system' => NotificationType.system,
    _ => NotificationType.missionReminder,
  };
}
