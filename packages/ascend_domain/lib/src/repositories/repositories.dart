/// Contratos de acceso a datos.
///
/// Son interfaces puras: el dominio declara **qué** necesita y la capa `data`
/// decide **cómo**. Ninguna firma menciona Firebase, HTTP ni SQL — esa es la
/// razón por la que el dominio se puede testear sin levantar nada y por la que
/// cambiar de backend no obligaría a reescribir la lógica de negocio.
///
/// Convenciones:
/// - Todo devuelve `Result`: ninguna implementación puede lanzar.
/// - Los `Stream` entregan `Result` también, para poder emitir un fallo sin
///   cortar la suscripción.
/// - Los identificadores los genera el cliente, así las escrituras son
///   idempotentes y sobreviven a un reintento offline.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/app_user.dart';
import 'package:ascend_domain/src/entities/aura.dart';
import 'package:ascend_domain/src/entities/category.dart';
import 'package:ascend_domain/src/entities/goal.dart';
import 'package:ascend_domain/src/entities/mission.dart';
import 'package:ascend_domain/src/entities/post.dart';

import 'package:ascend_domain/src/enums/enums.dart';
import 'package:ascend_domain/src/usecases/ai_usecases.dart';
import 'package:ascend_domain/src/usecases/notification_usecases.dart'
    show NotificationPermission;

/// Autenticación y ciclo de vida de la sesión.
abstract interface class AuthRepository {
  /// Emite el usuario autenticado, o `null` si no hay sesión.
  Stream<AppUser?> authStateChanges();

  /// Usuario actual sin esperar al stream.
  AppUser? get currentUser;

  /// Entra con email y contraseña.
  Future<Result<AppUser>> signInWithEmail({
    required String email,
    required String password,
  });

  /// Registra una cuenta nueva.
  Future<Result<AppUser>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String handle,
  });

  /// Entra con Google.
  Future<Result<AppUser>> signInWithGoogle();

  /// Entra con Apple. Obligatorio en iOS si se ofrece login social.
  Future<Result<AppUser>> signInWithApple();

  /// Cierra la sesión.
  Future<Result<void>> signOut();

  /// Envía el correo de recuperación de contraseña.
  Future<Result<void>> sendPasswordResetEmail(String email);

  /// Envía el correo de verificación.
  Future<Result<void>> sendEmailVerification();

  /// Vuelve a leer el estado del usuario desde el servidor.
  Future<Result<AppUser>> reloadUser();

  /// Cambia la contraseña, revalidando la actual.
  Future<Result<void>> updatePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Elimina la cuenta y todos sus datos. Ejecuta una Cloud Function.
  Future<Result<void>> deleteAccount({required String password});

  /// Fuerza el refresco del token para releer los custom claims.
  ///
  /// Necesario tras un cambio de rol: sin esto el claim viejo sigue vigente
  /// hasta que el token expira por su cuenta.
  Future<Result<void>> refreshToken();
}

/// Perfil y datos de la persona.
abstract interface class UserRepository {
  /// Observa el perfil propio.
  Stream<Result<AppUser>> watchUser(String uid);

  /// Lee un perfil.
  Future<Result<AppUser>> getUser(String uid);

  /// Actualiza los campos editables del perfil.
  Future<Result<void>> updateProfile({
    required String uid,
    String? displayName,
    String? bio,
    String? photoUrl,
  });

  /// Actualiza los ajustes.
  Future<Result<void>> updateSettings({
    required String uid,
    required UserSettings settings,
  });

  /// Indica si un handle está libre.
  Future<Result<bool>> isHandleAvailable(String handle);

  /// Reclama un handle en una transacción junto al perfil.
  Future<Result<void>> claimHandle({
    required String uid,
    required String handle,
  });

  /// Marca el onboarding como terminado.
  Future<Result<void>> completeOnboarding({
    required String uid,
    required List<String> interests,
  });

  /// Sube el avatar y devuelve su URL.
  Future<Result<String>> uploadAvatar({
    required String uid,
    required String localPath,
  });
}

/// Objetivos.
abstract interface class GoalRepository {
  /// Observa los objetivos de una persona, opcionalmente filtrados.
  Stream<Result<List<Goal>>> watchGoals({
    required String uid,
    GoalStatus? status,
    String? categoryId,
  });

  /// Observa un objetivo concreto.
  Stream<Result<Goal>> watchGoal({required String uid, required String goalId});

  /// Crea un objetivo.
  Future<Result<Goal>> createGoal(Goal goal);

  /// Crea un objetivo junto a sus misiones en una única escritura atómica.
  ///
  /// Es el cierre del asistente con IA: si se guardara el objetivo y fallara el
  /// alta de misiones, quedaría un objetivo huérfano y vacío.
  Future<Result<Goal>> createGoalWithMissions({
    required Goal goal,
    required List<Mission> missions,
  });

  /// Actualiza un objetivo.
  Future<Result<void>> updateGoal(Goal goal);

  /// Cambia el estado.
  Future<Result<void>> updateStatus({
    required String uid,
    required String goalId,
    required GoalStatus status,
  });

  /// Elimina el objetivo y, en cascada, sus misiones y evidencias.
  Future<Result<void>> deleteGoal({
    required String uid,
    required String goalId,
  });

  /// Marca un hito como alcanzado.
  Future<Result<void>> toggleMilestone({
    required String uid,
    required String goalId,
    required String milestoneId,
    required bool done,
  });
}

/// Misiones.
abstract interface class MissionRepository {
  /// Observa las misiones del día. Es la consulta más usada de la app.
  Stream<Result<List<Mission>>> watchToday({
    required String uid,
    DateTime? day,
  });

  /// Observa las misiones de un objetivo.
  Stream<Result<List<Mission>>> watchByGoal({
    required String uid,
    required String goalId,
  });

  /// Observa misiones con filtros combinados.
  Stream<Result<List<Mission>>> watchMissions({
    required String uid,
    MissionStatus? status,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    String? categoryId,
    String? goalId,
  });

  /// Lee una misión.
  Future<Result<Mission>> getMission({
    required String uid,
    required String missionId,
  });

  /// Crea una misión.
  Future<Result<Mission>> createMission(Mission mission);

  /// Actualiza una misión.
  Future<Result<void>> updateMission(Mission mission);

  /// Marca una misión como completada.
  ///
  /// El cliente **solo** cambia el estado: la Aura la otorga un trigger del
  /// servidor. Ver ADR-003.
  Future<Result<void>> completeMission({
    required String uid,
    required String missionId,
    Evidence? evidence,
  });

  /// Saltea una misión.
  Future<Result<void>> skipMission({
    required String uid,
    required String missionId,
    String? reason,
  });

  /// Reordena misiones dentro de una lista.
  Future<Result<void>> reorderMissions({
    required String uid,
    required List<String> orderedIds,
  });

  /// Elimina una misión.
  Future<Result<void>> deleteMission({
    required String uid,
    required String missionId,
  });

  /// Historial paginado de misiones completadas.
  Future<Result<Paginated<Mission>>> getHistory({
    required String uid,
    Object? cursor,
    int limit = 20,
  });
}

/// Evidencias y su cola de subida offline.
abstract interface class EvidenceRepository {
  /// Encola una evidencia para subir y devuelve la misión actualizada.
  Future<Result<Evidence>> enqueueUpload({
    required String uid,
    required String missionId,
    required String localPath,
    String? note,
  });

  /// Procesa la cola pendiente. Se invoca al recuperar la conexión.
  Future<Result<int>> processPendingUploads();

  /// Observa cuántas subidas quedan pendientes (alimenta el banner offline).
  Stream<int> watchPendingCount();

  /// Elimina una evidencia y su archivo en Storage.
  Future<Result<void>> deleteEvidence({
    required String uid,
    required String missionId,
  });
}

/// Aura: saldo, historial y estadísticas. Todo de solo lectura.
abstract interface class AuraRepository {
  /// Observa el saldo y nivel.
  Stream<Result<Aura>> watchAura(String uid);

  /// Historial paginado del ledger.
  Future<Result<Paginated<AuraEntry>>> getLedger({
    required String uid,
    Object? cursor,
    int limit = 30,
  });

  /// Aura ganada por día en los últimos [days] días, para los gráficos.
  Future<Result<Map<String, int>>> getDailyAura({
    required String uid,
    int days = 30,
  });

  /// Tabla de niveles configurada en el servidor.
  Future<Result<List<AuraLevel>>> getLevels();
}

/// Generación con IA.
///
/// La implementación invoca una Cloud Function llamable: **el cliente nunca
/// habla con Gemini** (ADR-002). Si la key viajara en el binario, se extraería
/// de un APK en cinco minutos.
abstract interface class AiRepository {
  /// Pide un plan de misiones para un objetivo.
  Future<Result<ProposedPlan>> generateGoalPlan({
    required String goalTitle,
    required String categoryId,
    String? description,
    int horizonDays,
    int missionCount,
    MissionBudget budget,
  });

  /// Cuántas generaciones quedan hoy.
  Future<Result<int>> remainingQuota(String uid);
}

/// Feed de la comunidad.
///
/// El feed es una colección global paginada con cursores (ADR-006). El fan-out
/// por seguidor llega recién cuando el volumen lo justifique; esta interfaz no
/// cambia cuando eso pase, solo su implementación.
abstract interface class PostRepository {
  /// Página del feed, del más reciente al más viejo.
  Future<Result<Paginated<Post>>> getFeed({
    Object? cursor,
    int limit = 20,
    String? categoryId,
  });

  /// Publicaciones de una persona.
  Future<Result<Paginated<Post>>> getByAuthor({
    required String authorId,
    Object? cursor,
    int limit = 20,
  });

  /// Observa una publicación concreta.
  Stream<Result<Post>> watchPost(String postId);

  /// Publica.
  Future<Result<Post>> createPost(Post post);

  /// Corrige el texto de una publicación propia.
  Future<Result<void>> updateText({
    required String postId,
    required String text,
  });

  /// Borra una publicación propia.
  Future<Result<void>> deletePost(String postId);

  /// Da o quita "me gusta".
  ///
  /// El id del documento de like **es** el uid, así que la operación es
  /// idempotente por construcción: no existe forma de dar like dos veces.
  Future<Result<void>> setLike({
    required String postId,
    required String uid,
    required bool liked,
  });

  /// Indica si [uid] ya dio "me gusta".
  Future<Result<bool>> hasLiked({required String postId, required String uid});
}

/// Comentarios de una publicación.
abstract interface class CommentRepository {
  /// Observa el hilo de comentarios.
  Stream<Result<List<Comment>>> watchComments(String postId);

  /// Publica un comentario.
  Future<Result<Comment>> addComment(Comment comment);

  /// Borra un comentario propio.
  Future<Result<void>> deleteComment({
    required String postId,
    required String commentId,
  });
}

/// Reportes de moderación.
abstract interface class ReportRepository {
  /// Reporta un contenido.
  ///
  /// Es idempotente: el id es `{targetId}_{reporterId}`, así que reportar dos
  /// veces lo mismo sobrescribe en lugar de inflar el contador.
  Future<Result<void>> report(Report report);

  /// Indica si [reporterId] ya reportó [targetId].
  Future<Result<bool>> hasReported({
    required String targetId,
    required String reporterId,
  });
}

/// Perfiles públicos: la proyección que lee el feed.
abstract interface class PublicProfileRepository {
  /// Lee un perfil público por uid.
  Future<Result<PostAuthor>> getByUid(String uid);

  /// Observa un perfil público.
  Stream<Result<PostAuthor>> watchByUid(String uid);
}

/// Catálogo de categorías.
abstract interface class CategoryRepository {
  /// Observa las categorías activas.
  Stream<Result<List<Category>>> watchCategories({bool onlyActive = true});

  /// Lee una categoría.
  Future<Result<Category>> getCategory(String id);
}

/// Bandeja de notificaciones y registro de dispositivos.
abstract interface class NotificationRepository {
  /// Observa la bandeja.
  Stream<Result<List<AppNotification>>> watchNotifications(String uid);

  /// Observa cuántas hay sin leer.
  Stream<int> watchUnreadCount(String uid);

  /// Marca una como leída.
  Future<Result<void>> markAsRead({required String uid, required String id});

  /// Marca todas como leídas.
  Future<Result<void>> markAllAsRead(String uid);

  /// Registra el token FCM del dispositivo actual.
  Future<Result<void>> registerDeviceToken(String uid);

  /// Da de baja el token del dispositivo actual (al cerrar sesión).
  Future<Result<void>> unregisterDeviceToken(String uid);

  /// Estado actual del permiso del sistema.
  Future<NotificationPermission> permissionStatus();

  /// Pide permiso de notificaciones al sistema operativo.
  ///
  /// Devuelve el estado resultante y no un `bool`: "denegado" y "denegado para
  /// siempre" son situaciones distintas —la segunda solo se revierte desde los
  /// ajustes del sistema— y la pantalla tiene que poder explicar cuál es.
  Future<NotificationPermission> requestPermission();
}

/// Estado de la conexión.
abstract interface class ConnectivityRepository {
  /// Emite `true` cuando hay conexión.
  Stream<bool> watchConnectivity();

  /// Estado actual.
  Future<bool> get isOnline;
}

/// Configuración remota de la app.
abstract interface class ConfigRepository {
  /// Versión mínima soportada. Por debajo, se fuerza actualizar.
  Future<Result<String>> getMinimumSupportedVersion();

  /// Valor de un feature flag.
  Future<Result<bool>> isFeatureEnabled(String flag);

  /// Si la app está en mantenimiento.
  Future<Result<bool>> isMaintenanceMode();
}
