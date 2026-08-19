import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Traducción entre el documento `users/{uid}` de Firestore y [AppUser].
///
/// ## Por qué está escrito a mano y no con Freezed + json_serializable
///
/// El diseño preveía codegen para los DTOs, y para la mayoría va a servir. Este
/// documento en concreto no encaja: la mitad de lo que se escribe no es JSON.
///
///   · `FieldValue.serverTimestamp()` es un centinela, no un valor. Un
///     serializador lo emitiría como objeto vacío y el timestamp quedaría nulo.
///   · Las actualizaciones son **parciales por obligación**: las reglas exigen
///     `onlyFields([...])`. Un `toJson()` completo mandaría `aura` y `stats` en
///     cada guardado y Firestore rechazaría la escritura entera.
///   · `Timestamp` de Firestore necesita converter propio en los dos sentidos.
///
/// Escribirlo a mano hace explícito qué campo viaja en cada operación, que es
/// exactamente lo que hay que poder auditar cuando las reglas rechazan algo.
/// El límite arquitectónico se respeta igual: ningún `DocumentSnapshot` sale de
/// esta capa.
abstract final class UserDto {
  /// Convierte un documento de Firestore en la entidad de dominio.
  ///
  /// Nunca lanza ante un documento incompleto o con campos de un tipo
  /// inesperado: cae al valor por defecto. Un perfil a medio escribir tiene que
  /// poder abrirse para que la persona lo arregle, no romper la app.
  static AppUser fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    bool emailVerified = false,
    UserRole? roleFromClaims,
  }) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return fromMap(
      data,
      uid: snapshot.id,
      emailVerified: emailVerified,
      roleFromClaims: roleFromClaims,
    );
  }

  /// Convierte un mapa plano en la entidad. Separado de [fromFirestore] para
  /// poder testear el mapeo sin instanciar Firestore.
  static AppUser fromMap(
    Map<String, dynamic> data, {
    required String uid,
    bool emailVerified = false,
    UserRole? roleFromClaims,
  }) {
    final aura = _mapOf(data['aura']);
    final stats = _mapOf(data['stats']);
    final settings = _mapOf(data['settings']);
    final onboarding = _mapOf(data['onboarding']);

    return AppUser(
      uid: uid,
      email: _stringOf(data['email']),
      displayName: _stringOf(data['displayName']),
      handle: _stringOf(data['handle']),
      createdAt: _dateOf(data['createdAt']) ?? DateTime.now().toUtc(),
      photoUrl: _nullableStringOf(data['photoUrl']),
      bio: _nullableStringOf(data['bio']),
      // El claim manda sobre el campo del documento. El campo es un espejo de
      // conveniencia para el panel; si alguna vez se desincronizan, el que
      // decide permisos es el token (ADR-004).
      role:
          roleFromClaims ?? UserRole.fromWire(_nullableStringOf(data['role'])),
      status: UserStatus.fromWire(_nullableStringOf(data['status'])),
      aura: Aura(
        total: _intOf(aura['total']),
        level: _intOf(aura['level'], fallback: 1),
        levelName: _stringOf(aura['levelName'], fallback: 'Iniciado'),
        xpInLevel: _intOf(aura['xpInLevel']),
        xpForNextLevel: _intOf(aura['xpForNextLevel'], fallback: 100),
      ),
      stats: UserStats(
        goalsActive: _intOf(stats['goalsActive']),
        goalsCompleted: _intOf(stats['goalsCompleted']),
        missionsCompleted: _intOf(stats['missionsCompleted']),
        currentStreak: _intOf(stats['currentStreak']),
        longestStreak: _intOf(stats['longestStreak']),
        postsCount: _intOf(stats['postsCount']),
        followersCount: _intOf(stats['followersCount']),
        followingCount: _intOf(stats['followingCount']),
        lastActivityDate: _nullableStringOf(stats['lastActivityDate']),
      ),
      settings: _settingsFrom(settings, locale: _stringOf(data['locale'])),
      emailVerified: emailVerified,
      onboardingCompleted: onboarding['completed'] == true,
      interests: _stringListOf(onboarding['interests']),
      updatedAt: _dateOf(data['updatedAt']),
      lastLoginAt: _dateOf(data['lastLoginAt']),
    );
  }

  /// Campos del perfil que el cliente tiene permitido escribir.
  ///
  /// El mapa se arma solo con lo que efectivamente cambió. Mandar un campo de
  /// más no es inofensivo: `onlyFields` compara el conjunto exacto de claves
  /// afectadas y rechaza la operación completa.
  static Map<String, Object?> profileUpdate({
    String? displayName,
    String? bio,
    String? photoUrl,
  }) => <String, Object?>{
    if (displayName != null) 'displayName': displayName,
    if (bio != null) 'bio': bio,
    if (photoUrl != null) 'photoUrl': photoUrl,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Serializa los ajustes completos.
  static Map<String, Object?> settingsUpdate(UserSettings settings) =>
      <String, Object?>{
        'settings': <String, Object?>{
          'themeMode': settings.themeMode,
          'timezone': settings.timezone,
          'notifications': <String, Object?>{
            'dailyReminder': settings.notifications.dailyReminder,
            'reminderTime': settings.notifications.reminderTime,
            'streakAlerts': settings.notifications.streakAlerts,
            'socialActivity': settings.notifications.socialActivity,
            'aiSuggestions': settings.notifications.aiSuggestions,
            'quietHoursStart': settings.notifications.quietHoursStart,
            'quietHoursEnd': settings.notifications.quietHoursEnd,
          },
          'privacy': <String, Object?>{
            'profileVisibility': settings.privacy.profileVisibility.wireValue,
            'autoPublishAchievements': settings.privacy.autoPublishAchievements,
            'showInLeaderboard': settings.privacy.showInLeaderboard,
          },
        },
        'locale': settings.locale,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Serializa el cierre del onboarding.
  static Map<String, Object?> onboardingUpdate(
    List<String> interests,
  ) => <String, Object?>{
    'onboarding': <String, Object?>{'completed': true, 'interests': interests},
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static UserSettings _settingsFrom(
    Map<String, dynamic> settings, {
    required String locale,
  }) {
    final notifications = _mapOf(settings['notifications']);
    final privacy = _mapOf(settings['privacy']);

    return UserSettings(
      themeMode: _stringOf(settings['themeMode'], fallback: 'system'),
      locale: locale.isEmpty ? 'es' : locale,
      timezone: _stringOf(
        settings['timezone'],
        fallback: 'America/Argentina/Buenos_Aires',
      ),
      notifications: NotificationSettings(
        dailyReminder: notifications['dailyReminder'] != false,
        reminderTime: _stringOf(
          notifications['reminderTime'],
          fallback: '20:00',
        ),
        streakAlerts: notifications['streakAlerts'] != false,
        socialActivity: notifications['socialActivity'] != false,
        aiSuggestions: notifications['aiSuggestions'] != false,
        quietHoursStart: _nullableStringOf(notifications['quietHoursStart']),
        quietHoursEnd: _nullableStringOf(notifications['quietHoursEnd']),
      ),
      privacy: PrivacySettings(
        profileVisibility: Visibility.fromWire(
          _nullableStringOf(privacy['profileVisibility']),
        ),
        autoPublishAchievements: privacy['autoPublishAchievements'] == true,
        showInLeaderboard: privacy['showInLeaderboard'] != false,
      ),
    );
  }

  static Map<String, dynamic> _mapOf(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  static String _stringOf(Object? value, {String fallback = ''}) =>
      value is String && value.isNotEmpty ? value : fallback;

  static String? _nullableStringOf(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static int _intOf(Object? value, {int fallback = 0}) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => fallback,
  };

  static List<String> _stringListOf(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];

  // Todo lo que entra al dominio va en UTC. `Timestamp.toDate()` devuelve hora
  // local, así que sin este `toUtc()` el mismo instante se compararía distinto
  // según el huso del dispositivo — y las rachas se calculan con fechas.
  static DateTime? _dateOf(Object? value) => switch (value) {
    final Timestamp v => v.toDate().toUtc(),
    final DateTime v => v.toUtc(),
    // Entre que se escribe con `serverTimestamp()` y que el servidor confirma,
    // la caché local devuelve null. No es un error: es el valor pendiente.
    _ => null,
  };
}
