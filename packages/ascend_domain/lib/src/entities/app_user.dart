import 'package:ascend_domain/src/entities/aura.dart';
import 'package:ascend_domain/src/enums/enums.dart';
import 'package:meta/meta.dart';

/// Estadísticas de actividad de una persona. Las calcula el servidor.
@immutable
class UserStats {
  /// Crea las estadísticas.
  const UserStats({
    this.goalsActive = 0,
    this.goalsCompleted = 0,
    this.missionsCompleted = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.postsCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.lastActivityDate,
  });

  /// Estadísticas de una cuenta recién creada.
  static const UserStats empty = UserStats();

  /// Objetivos en curso.
  final int goalsActive;

  /// Objetivos terminados.
  final int goalsCompleted;

  /// Misiones completadas en total.
  final int missionsCompleted;

  /// Días consecutivos con actividad.
  final int currentStreak;

  /// Mejor racha histórica.
  final int longestStreak;

  /// Publicaciones creadas.
  final int postsCount;

  /// Seguidores.
  final int followersCount;

  /// Cuentas seguidas.
  final int followingCount;

  /// Clave del último día con actividad (`YYYY-MM-DD` en zona local).
  final String? lastActivityDate;

  /// Copia con cambios.
  UserStats copyWith({
    int? goalsActive,
    int? goalsCompleted,
    int? missionsCompleted,
    int? currentStreak,
    int? longestStreak,
    int? postsCount,
    int? followersCount,
    int? followingCount,
    String? lastActivityDate,
  }) => UserStats(
    goalsActive: goalsActive ?? this.goalsActive,
    goalsCompleted: goalsCompleted ?? this.goalsCompleted,
    missionsCompleted: missionsCompleted ?? this.missionsCompleted,
    currentStreak: currentStreak ?? this.currentStreak,
    longestStreak: longestStreak ?? this.longestStreak,
    postsCount: postsCount ?? this.postsCount,
    followersCount: followersCount ?? this.followersCount,
    followingCount: followingCount ?? this.followingCount,
    lastActivityDate: lastActivityDate ?? this.lastActivityDate,
  );
}

/// Preferencias de notificación.
@immutable
class NotificationSettings {
  /// Crea las preferencias de notificación.
  const NotificationSettings({
    this.dailyReminder = true,
    this.reminderTime = '20:00',
    this.streakAlerts = true,
    this.socialActivity = true,
    this.aiSuggestions = true,
    this.quietHoursStart,
    this.quietHoursEnd,
  });

  /// Recordatorio diario activado.
  final bool dailyReminder;

  /// Hora local del recordatorio, en formato `HH:mm`.
  final String reminderTime;

  /// Avisos de racha en riesgo.
  final bool streakAlerts;

  /// Avisos de likes, comentarios y seguidores.
  final bool socialActivity;

  /// Sugerencias generadas por la IA.
  final bool aiSuggestions;

  /// Inicio del horario de silencio (`HH:mm`).
  final String? quietHoursStart;

  /// Fin del horario de silencio (`HH:mm`).
  final String? quietHoursEnd;

  /// Copia con cambios.
  NotificationSettings copyWith({
    bool? dailyReminder,
    String? reminderTime,
    bool? streakAlerts,
    bool? socialActivity,
    bool? aiSuggestions,
    String? quietHoursStart,
    String? quietHoursEnd,
  }) => NotificationSettings(
    dailyReminder: dailyReminder ?? this.dailyReminder,
    reminderTime: reminderTime ?? this.reminderTime,
    streakAlerts: streakAlerts ?? this.streakAlerts,
    socialActivity: socialActivity ?? this.socialActivity,
    aiSuggestions: aiSuggestions ?? this.aiSuggestions,
    quietHoursStart: quietHoursStart ?? this.quietHoursStart,
    quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
  );
}

/// Preferencias de privacidad.
@immutable
class PrivacySettings {
  /// Crea las preferencias de privacidad.
  const PrivacySettings({
    this.profileVisibility = Visibility.public,
    this.autoPublishAchievements = false,
    this.showInLeaderboard = true,
  });

  /// Quién puede ver el perfil.
  final Visibility profileVisibility;

  /// Si los logros se publican solos al completarse.
  ///
  /// Por defecto `false`: publicar en nombre de alguien sin que lo pida es la
  /// clase de sorpresa que hace que se desinstale la app.
  final bool autoPublishAchievements;

  /// Si aparece en el ranking público.
  final bool showInLeaderboard;

  /// Copia con cambios.
  PrivacySettings copyWith({
    Visibility? profileVisibility,
    bool? autoPublishAchievements,
    bool? showInLeaderboard,
  }) => PrivacySettings(
    profileVisibility: profileVisibility ?? this.profileVisibility,
    autoPublishAchievements:
        autoPublishAchievements ?? this.autoPublishAchievements,
    showInLeaderboard: showInLeaderboard ?? this.showInLeaderboard,
  );
}

/// Ajustes de la aplicación para una persona.
@immutable
class UserSettings {
  /// Crea los ajustes.
  const UserSettings({
    this.themeMode = 'system',
    this.locale = 'es',
    this.timezone = 'America/Argentina/Buenos_Aires',
    this.notifications = const NotificationSettings(),
    this.privacy = const PrivacySettings(),
  });

  /// Ajustes por defecto.
  static const UserSettings defaults = UserSettings();

  /// `system`, `light` o `dark`.
  final String themeMode;

  /// Idioma de la interfaz.
  final String locale;

  /// Zona horaria IANA. Base del cálculo de rachas y recordatorios.
  final String timezone;

  /// Preferencias de notificación.
  final NotificationSettings notifications;

  /// Preferencias de privacidad.
  final PrivacySettings privacy;

  /// Copia con cambios.
  UserSettings copyWith({
    String? themeMode,
    String? locale,
    String? timezone,
    NotificationSettings? notifications,
    PrivacySettings? privacy,
  }) => UserSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    timezone: timezone ?? this.timezone,
    notifications: notifications ?? this.notifications,
    privacy: privacy ?? this.privacy,
  );
}

/// Persona usuaria de Ascend.
///
/// Se llama `AppUser` y no `User` a propósito: `User` ya existe en
/// `firebase_auth` y tener dos tipos con el mismo nombre en distintas capas es
/// una fuente garantizada de confusión.
@immutable
class AppUser {
  /// Crea un usuario.
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.handle,
    required this.createdAt,
    this.photoUrl,
    this.bio,
    this.role = UserRole.user,
    this.status = UserStatus.active,
    this.aura = Aura.initial,
    this.stats = UserStats.empty,
    this.settings = UserSettings.defaults,
    this.emailVerified = false,
    this.onboardingCompleted = false,
    this.interests = const <String>[],
    this.updatedAt,
    this.lastLoginAt,
  });

  /// Identificador de Firebase Auth.
  final String uid;

  /// Correo electrónico.
  final String email;

  /// Nombre visible.
  final String displayName;

  /// Nombre de usuario público, único y en minúsculas.
  final String handle;

  /// Fecha de alta.
  final DateTime createdAt;

  /// URL del avatar.
  final String? photoUrl;

  /// Biografía corta.
  final String? bio;

  /// Rol. Espejo del custom claim: el cliente lo lee, nunca lo escribe.
  final UserRole role;

  /// Estado de la cuenta.
  final UserStatus status;

  /// Saldo de Aura. Solo lectura para el cliente.
  final Aura aura;

  /// Estadísticas. Solo lectura para el cliente.
  final UserStats stats;

  /// Ajustes editables por la persona.
  final UserSettings settings;

  /// Si el email fue verificado.
  final bool emailVerified;

  /// Si terminó el onboarding.
  final bool onboardingCompleted;

  /// Categorías de interés elegidas en el onboarding.
  final List<String> interests;

  /// Última modificación.
  final DateTime? updatedAt;

  /// Último ingreso.
  final DateTime? lastLoginAt;

  /// `true` si la cuenta puede usar la app con normalidad.
  bool get canOperate => status.canOperate;

  /// `true` si tiene permisos de administración.
  bool get isAdmin => role.isAdmin;

  /// `true` si la cuenta ya tiene su perfil creado en Firestore.
  ///
  /// Existe un estado intermedio real: la cuenta de Auth se crea y, antes de
  /// que la Function termine de escribir el perfil, se corta la red o se cierra
  /// la app. Esa persona tiene sesión válida y ningún perfil. Detectarlo por el
  /// handle vacío permite mandarla a completar el registro en vez de dejarla
  /// con una cuenta inutilizable que ni siquiera puede volver a crear, porque
  /// su email ya figura como registrado.
  bool get hasProfile => handle.isNotEmpty;

  /// Handle con el arroba delante, listo para mostrar.
  String get displayHandle => '@$handle';

  /// Copia con cambios.
  AppUser copyWith({
    String? email,
    String? displayName,
    String? handle,
    String? photoUrl,
    String? bio,
    UserRole? role,
    UserStatus? status,
    Aura? aura,
    UserStats? stats,
    UserSettings? settings,
    bool? emailVerified,
    bool? onboardingCompleted,
    List<String>? interests,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
  }) => AppUser(
    uid: uid,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    handle: handle ?? this.handle,
    createdAt: createdAt,
    photoUrl: photoUrl ?? this.photoUrl,
    bio: bio ?? this.bio,
    role: role ?? this.role,
    status: status ?? this.status,
    aura: aura ?? this.aura,
    stats: stats ?? this.stats,
    settings: settings ?? this.settings,
    emailVerified: emailVerified ?? this.emailVerified,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    interests: interests ?? this.interests,
    updatedAt: updatedAt ?? this.updatedAt,
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppUser && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;

  @override
  String toString() => 'AppUser($uid, @$handle)';
}
