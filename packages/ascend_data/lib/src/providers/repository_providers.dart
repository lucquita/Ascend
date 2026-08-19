/// Grafo de dependencias de la capa de datos.
///
/// Cada provider expone el **tipo del dominio**, nunca la implementación. Esa
/// es la inversión de dependencias en la práctica: la app depende de
/// `AuthRepository`, no de `AuthRepositoryImpl`, y en un test se sustituye con
/// un `overrideWithValue` sin mockear una sola clase de Firebase.
///
/// Los providers se escriben a mano en lugar de con `@riverpod` por el tope de
/// toolchain documentado en la Fase 0: `riverpod_generator` exige
/// `build_runner >= 2.15.3`, incompatible con el Flutter fijado. El grafo
/// resultante es idéntico.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/local/evidence_outbox.dart';
import 'package:ascend_data/src/datasources/remote/ascend_http_client.dart';
import 'package:ascend_data/src/datasources/remote/firebase_auth_datasource.dart';
import 'package:ascend_data/src/datasources/remote/firebase_messaging_datasource.dart';
import 'package:ascend_data/src/datasources/remote/firestore_aura_datasource.dart';
import 'package:ascend_data/src/datasources/remote/firestore_category_datasource.dart';
import 'package:ascend_data/src/datasources/remote/firestore_community_datasource.dart';
import 'package:ascend_data/src/datasources/remote/firestore_goal_datasource.dart';
import 'package:ascend_data/src/datasources/remote/firestore_mission_datasource.dart';
import 'package:ascend_data/src/datasources/remote/firestore_user_datasource.dart';
import 'package:ascend_data/src/providers/infrastructure_providers.dart';
import 'package:ascend_data/src/repositories/admin_repository_impl.dart';
import 'package:ascend_data/src/repositories/ai_repository_impl.dart';
import 'package:ascend_data/src/repositories/aura_repository_impl.dart';
import 'package:ascend_data/src/repositories/auth_repository_impl.dart';
import 'package:ascend_data/src/repositories/category_repository_impl.dart';
import 'package:ascend_data/src/repositories/community_repository_impl.dart';
import 'package:ascend_data/src/repositories/evidence_repository_impl.dart';
import 'package:ascend_data/src/repositories/goal_repository_impl.dart';
import 'package:ascend_data/src/repositories/integration_repository_impl.dart';
import 'package:ascend_data/src/repositories/mission_repository_impl.dart';
import 'package:ascend_data/src/repositories/notification_repository_impl.dart';
import 'package:ascend_data/src/repositories/user_repository_impl.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Datasource de Firebase Authentication.
final Provider<FirebaseAuthDataSource> firebaseAuthDataSourceProvider =
    Provider<FirebaseAuthDataSource>(
      (ref) => FirebaseAuthDataSource(
        auth: ref.watch(firebaseAuthProvider),
        functions: ref.watch(firebaseFunctionsProvider),
      ),
      name: 'firebaseAuthDataSource',
    );

/// Datasource del documento de perfil.
final Provider<FirestoreUserDataSource> firestoreUserDataSourceProvider =
    Provider<FirestoreUserDataSource>(
      (ref) => FirestoreUserDataSource(ref.watch(firestoreProvider)),
      name: 'firestoreUserDataSource',
    );

/// Contrato de autenticación.
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (ref) => AuthRepositoryImpl(
        authDataSource: ref.watch(firebaseAuthDataSourceProvider),
        userDataSource: ref.watch(firestoreUserDataSourceProvider),
      ),
      name: 'authRepository',
    );

/// Contrato de perfil.
final Provider<UserRepository> userRepositoryProvider =
    Provider<UserRepository>(
      (ref) => UserRepositoryImpl(
        userDataSource: ref.watch(firestoreUserDataSourceProvider),
        storage: ref.watch(firebaseStorageProvider),
      ),
      name: 'userRepository',
    );

/// Datasource de objetivos.
final Provider<FirestoreGoalDataSource> firestoreGoalDataSourceProvider =
    Provider<FirestoreGoalDataSource>(
      (ref) => FirestoreGoalDataSource(ref.watch(firestoreProvider)),
      name: 'firestoreGoalDataSource',
    );

/// Datasource del catálogo de categorías.
final Provider<FirestoreCategoryDataSource>
firestoreCategoryDataSourceProvider = Provider<FirestoreCategoryDataSource>(
  (ref) => FirestoreCategoryDataSource(ref.watch(firestoreProvider)),
  name: 'firestoreCategoryDataSource',
);

/// Datasource de misiones.
final Provider<FirestoreMissionDataSource> firestoreMissionDataSourceProvider =
    Provider<FirestoreMissionDataSource>(
      (ref) => FirestoreMissionDataSource(ref.watch(firestoreProvider)),
      name: 'firestoreMissionDataSource',
    );

/// Contrato de objetivos.
///
/// Depende también del datasource de misiones porque el alta de un objetivo con
/// plan escribe ambos en un único lote atómico.
final Provider<GoalRepository> goalRepositoryProvider =
    Provider<GoalRepository>(
      (ref) => GoalRepositoryImpl(
        goalDataSource: ref.watch(firestoreGoalDataSourceProvider),
        missionDataSource: ref.watch(firestoreMissionDataSourceProvider),
      ),
      name: 'goalRepository',
    );

/// Cola local de evidencias pendientes de subir.
///
/// Hoy es en memoria. Pasarla a Hive es cambiar esta línea: el contrato
/// `EvidenceOutbox` ya está, y `hive_ce` es dependencia del paquete. Se difiere
/// porque sin Cloud Storage la cola no puede vaciarse nunca, y persistir en
/// disco una cola que no drena solo acumula archivos huérfanos.
final Provider<EvidenceOutbox> evidenceOutboxProvider =
    Provider<EvidenceOutbox>(
      (ref) => InMemoryEvidenceOutbox(),
      name: 'evidenceOutbox',
    );

/// Puerto de subida de archivos.
///
/// Devuelve el uploader inactivo porque Cloud Storage requiere plan pago y el
/// proyecto está en el gratuito. Cuando se habilite, se reemplaza acá por la
/// implementación sobre `FirebaseStorage` y no cambia nada más.
final Provider<EvidenceUploader> evidenceUploaderProvider =
    Provider<EvidenceUploader>(
      (ref) => const UnavailableEvidenceUploader(),
      name: 'evidenceUploader',
    );

/// Contrato de evidencias.
final Provider<EvidenceRepository> evidenceRepositoryProvider =
    Provider<EvidenceRepository>(
      (ref) => EvidenceRepositoryImpl(
        outbox: ref.watch(evidenceOutboxProvider),
        missionDataSource: ref.watch(firestoreMissionDataSourceProvider),
        uploader: ref.watch(evidenceUploaderProvider),
      ),
      name: 'evidenceRepository',
    );

/// Contrato de misiones.
final Provider<MissionRepository> missionRepositoryProvider =
    Provider<MissionRepository>(
      (ref) => MissionRepositoryImpl(
        missionDataSource: ref.watch(firestoreMissionDataSourceProvider),
      ),
      name: 'missionRepository',
    );

/// Datasource de Aura, ledger y consumo diario.
final Provider<FirestoreAuraDataSource> firestoreAuraDataSourceProvider =
    Provider<FirestoreAuraDataSource>(
      (ref) => FirestoreAuraDataSource(ref.watch(firestoreProvider)),
      name: 'firestoreAuraDataSource',
    );

/// Contrato de IA.
///
/// Depende de `FirebaseFunctions` y no de Gemini: el cliente nunca habla con el
/// modelo (ADR-002).
final Provider<AiRepository> aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepositoryImpl(
    functions: ref.watch(firebaseFunctionsProvider),
    firestore: ref.watch(firestoreProvider),
  ),
  name: 'aiRepository',
);

/// Generar un plan con IA, con caída a plantillas.
final Provider<GenerateGoalPlanUseCase> generateGoalPlanUseCaseProvider =
    Provider<GenerateGoalPlanUseCase>(
      (ref) => GenerateGoalPlanUseCase(ref.watch(aiRepositoryProvider)),
      name: 'generateGoalPlanUseCase',
    );

/// Materializar un plan revisado en objetivo + misiones.
final Provider<MaterializePlanUseCase> materializePlanUseCaseProvider =
    Provider<MaterializePlanUseCase>(
      (ref) => MaterializePlanUseCase(ref.watch(goalRepositoryProvider)),
      name: 'materializePlanUseCase',
    );

/// Contrato de Aura. Solo lectura: el saldo lo escribe el servidor (ADR-003).
final Provider<AuraRepository> auraRepositoryProvider =
    Provider<AuraRepository>(
      (ref) => AuraRepositoryImpl(
        auraDataSource: ref.watch(firestoreAuraDataSourceProvider),
      ),
      name: 'auraRepository',
    );

/// Datasource del feed, comentarios, likes y reportes.
final Provider<FirestoreCommunityDataSource>
firestoreCommunityDataSourceProvider = Provider<FirestoreCommunityDataSource>(
  (ref) => FirestoreCommunityDataSource(ref.watch(firestoreProvider)),
  name: 'firestoreCommunityDataSource',
);

/// Contrato del feed.
final Provider<PostRepository> postRepositoryProvider =
    Provider<PostRepository>(
      (ref) => PostRepositoryImpl(
        communityDataSource: ref.watch(firestoreCommunityDataSourceProvider),
      ),
      name: 'postRepository',
    );

/// Contrato de comentarios.
final Provider<CommentRepository> commentRepositoryProvider =
    Provider<CommentRepository>(
      (ref) => CommentRepositoryImpl(
        communityDataSource: ref.watch(firestoreCommunityDataSourceProvider),
      ),
      name: 'commentRepository',
    );

/// Contrato de reportes.
final Provider<ReportRepository> reportRepositoryProvider =
    Provider<ReportRepository>(
      (ref) => ReportRepositoryImpl(
        communityDataSource: ref.watch(firestoreCommunityDataSourceProvider),
      ),
      name: 'reportRepository',
    );

/// Contrato de perfiles públicos.
final Provider<PublicProfileRepository> publicProfileRepositoryProvider =
    Provider<PublicProfileRepository>(
      (ref) => PublicProfileRepositoryImpl(
        communityDataSource: ref.watch(firestoreCommunityDataSourceProvider),
      ),
      name: 'publicProfileRepository',
    );

/// Cliente HTTP compartido por las integraciones externas.
///
/// Uno solo para todas: `http.Client` mantiene un pool de conexiones, y crear
/// uno por llamada tira ese pool y renegocia TLS cada vez.
final Provider<AscendHttpClient> httpClientProvider =
    Provider<AscendHttpClient>((ref) {
      final client = http.Client();
      ref.onDispose(client.close);
      return AscendHttpClient(client: client);
    }, name: 'httpClient');

/// Contrato del clima (Open-Meteo). Sin API key.
final Provider<WeatherRepository> weatherRepositoryProvider =
    Provider<WeatherRepository>(
      (ref) => WeatherRepositoryImpl(client: ref.watch(httpClientProvider)),
      name: 'weatherRepository',
    );

/// Contrato del catálogo de libros (Open Library). Sin API key.
final Provider<BookRepository> bookRepositoryProvider =
    Provider<BookRepository>(
      (ref) => BookRepositoryImpl(client: ref.watch(httpClientProvider)),
      name: 'bookRepository',
    );

/// Consultar el clima de una misión al aire libre.
final Provider<CheckMissionWeatherUseCase> checkMissionWeatherUseCaseProvider =
    Provider<CheckMissionWeatherUseCase>(
      (ref) => CheckMissionWeatherUseCase(ref.watch(weatherRepositoryProvider)),
      name: 'checkMissionWeatherUseCase',
    );

/// Buscar libros para convertirlos en misiones.
final Provider<SearchBooksUseCase> searchBooksUseCaseProvider =
    Provider<SearchBooksUseCase>(
      (ref) => SearchBooksUseCase(ref.watch(bookRepositoryProvider)),
      name: 'searchBooksUseCase',
    );

/// Contrato del catálogo de categorías.
final Provider<CategoryRepository> categoryRepositoryProvider =
    Provider<CategoryRepository>(
      (ref) => CategoryRepositoryImpl(
        categoryDataSource: ref.watch(firestoreCategoryDataSourceProvider),
      ),
      name: 'categoryRepository',
    );

// ── Casos de uso ────────────────────────────────────────────────────────────

/// Entrar con email y contraseña.
final Provider<SignInWithEmailUseCase> signInWithEmailUseCaseProvider =
    Provider<SignInWithEmailUseCase>(
      (ref) => SignInWithEmailUseCase(ref.watch(authRepositoryProvider)),
      name: 'signInWithEmailUseCase',
    );

/// Registrarse.
final Provider<SignUpWithEmailUseCase> signUpWithEmailUseCaseProvider =
    Provider<SignUpWithEmailUseCase>(
      (ref) => SignUpWithEmailUseCase(ref.watch(authRepositoryProvider)),
      name: 'signUpWithEmailUseCase',
    );

/// Cerrar sesión.
final Provider<SignOutUseCase> signOutUseCaseProvider =
    Provider<SignOutUseCase>(
      (ref) => SignOutUseCase(ref.watch(authRepositoryProvider)),
      name: 'signOutUseCase',
    );

/// Recuperar contraseña.
final Provider<SendPasswordResetUseCase> sendPasswordResetUseCaseProvider =
    Provider<SendPasswordResetUseCase>(
      (ref) => SendPasswordResetUseCase(ref.watch(authRepositoryProvider)),
      name: 'sendPasswordResetUseCase',
    );

/// Reenviar la verificación de email.
final Provider<SendEmailVerificationUseCase>
sendEmailVerificationUseCaseProvider = Provider<SendEmailVerificationUseCase>(
  (ref) => SendEmailVerificationUseCase(ref.watch(authRepositoryProvider)),
  name: 'sendEmailVerificationUseCase',
);

/// Releer el usuario desde el servidor.
final Provider<ReloadUserUseCase> reloadUserUseCaseProvider =
    Provider<ReloadUserUseCase>(
      (ref) => ReloadUserUseCase(ref.watch(authRepositoryProvider)),
      name: 'reloadUserUseCase',
    );

/// Cambiar la contraseña.
final Provider<ChangePasswordUseCase> changePasswordUseCaseProvider =
    Provider<ChangePasswordUseCase>(
      (ref) => ChangePasswordUseCase(ref.watch(authRepositoryProvider)),
      name: 'changePasswordUseCase',
    );

/// Eliminar la cuenta.
final Provider<DeleteAccountUseCase> deleteAccountUseCaseProvider =
    Provider<DeleteAccountUseCase>(
      (ref) => DeleteAccountUseCase(ref.watch(authRepositoryProvider)),
      name: 'deleteAccountUseCase',
    );

/// Actualizar el perfil.
final Provider<UpdateProfileUseCase> updateProfileUseCaseProvider =
    Provider<UpdateProfileUseCase>(
      (ref) => UpdateProfileUseCase(ref.watch(userRepositoryProvider)),
      name: 'updateProfileUseCase',
    );

/// Consultar disponibilidad de un handle.
final Provider<CheckHandleAvailabilityUseCase>
checkHandleAvailabilityUseCaseProvider =
    Provider<CheckHandleAvailabilityUseCase>(
      (ref) =>
          CheckHandleAvailabilityUseCase(ref.watch(userRepositoryProvider)),
      name: 'checkHandleAvailabilityUseCase',
    );

/// Subir el avatar.
final Provider<UploadAvatarUseCase> uploadAvatarUseCaseProvider =
    Provider<UploadAvatarUseCase>(
      (ref) => UploadAvatarUseCase(ref.watch(userRepositoryProvider)),
      name: 'uploadAvatarUseCase',
    );

/// Cerrar el onboarding.
final Provider<CompleteOnboardingUseCase> completeOnboardingUseCaseProvider =
    Provider<CompleteOnboardingUseCase>(
      (ref) => CompleteOnboardingUseCase(ref.watch(userRepositoryProvider)),
      name: 'completeOnboardingUseCase',
    );

/// Guardar los ajustes.
final Provider<UpdateSettingsUseCase> updateSettingsUseCaseProvider =
    Provider<UpdateSettingsUseCase>(
      (ref) => UpdateSettingsUseCase(ref.watch(userRepositoryProvider)),
      name: 'updateSettingsUseCase',
    );

// ── Casos de uso de objetivos ───────────────────────────────────────────────

/// Observar la lista de objetivos.
final Provider<WatchGoalsUseCase> watchGoalsUseCaseProvider =
    Provider<WatchGoalsUseCase>(
      (ref) => WatchGoalsUseCase(ref.watch(goalRepositoryProvider)),
      name: 'watchGoalsUseCase',
    );

/// Observar un objetivo.
final Provider<WatchGoalUseCase> watchGoalUseCaseProvider =
    Provider<WatchGoalUseCase>(
      (ref) => WatchGoalUseCase(ref.watch(goalRepositoryProvider)),
      name: 'watchGoalUseCase',
    );

/// Crear un objetivo.
final Provider<CreateGoalUseCase> createGoalUseCaseProvider =
    Provider<CreateGoalUseCase>(
      (ref) => CreateGoalUseCase(ref.watch(goalRepositoryProvider)),
      name: 'createGoalUseCase',
    );

/// Editar un objetivo.
final Provider<UpdateGoalUseCase> updateGoalUseCaseProvider =
    Provider<UpdateGoalUseCase>(
      (ref) => UpdateGoalUseCase(ref.watch(goalRepositoryProvider)),
      name: 'updateGoalUseCase',
    );

/// Cambiar el estado de un objetivo.
final Provider<ChangeGoalStatusUseCase> changeGoalStatusUseCaseProvider =
    Provider<ChangeGoalStatusUseCase>(
      (ref) => ChangeGoalStatusUseCase(ref.watch(goalRepositoryProvider)),
      name: 'changeGoalStatusUseCase',
    );

/// Eliminar un objetivo.
final Provider<DeleteGoalUseCase> deleteGoalUseCaseProvider =
    Provider<DeleteGoalUseCase>(
      (ref) => DeleteGoalUseCase(ref.watch(goalRepositoryProvider)),
      name: 'deleteGoalUseCase',
    );

/// Marcar o desmarcar un hito.
final Provider<ToggleMilestoneUseCase> toggleMilestoneUseCaseProvider =
    Provider<ToggleMilestoneUseCase>(
      (ref) => ToggleMilestoneUseCase(ref.watch(goalRepositoryProvider)),
      name: 'toggleMilestoneUseCase',
    );

/// Observar el catálogo de categorías.
final Provider<WatchCategoriesUseCase> watchCategoriesUseCaseProvider =
    Provider<WatchCategoriesUseCase>(
      (ref) => WatchCategoriesUseCase(ref.watch(categoryRepositoryProvider)),
      name: 'watchCategoriesUseCase',
    );

/// Catálogo de categorías activas, en vivo.
///
/// Vive acá y no en la app porque lo consumen las dos: el móvil para el alta de
/// objetivos y el panel para los filtros del explorador.
final StreamProvider<Result<List<Category>>> categoriesProvider =
    StreamProvider<Result<List<Category>>>(
      (ref) => ref.watch(watchCategoriesUseCaseProvider).call(),
      name: 'categories',
    );

// ── Casos de uso de misiones ────────────────────────────────────────────────

/// Observar las misiones del día.
final Provider<WatchTodayMissionsUseCase> watchTodayMissionsUseCaseProvider =
    Provider<WatchTodayMissionsUseCase>(
      (ref) => WatchTodayMissionsUseCase(ref.watch(missionRepositoryProvider)),
      name: 'watchTodayMissionsUseCase',
    );

/// Observar las misiones de un objetivo.
final Provider<WatchMissionsByGoalUseCase> watchMissionsByGoalUseCaseProvider =
    Provider<WatchMissionsByGoalUseCase>(
      (ref) => WatchMissionsByGoalUseCase(ref.watch(missionRepositoryProvider)),
      name: 'watchMissionsByGoalUseCase',
    );

/// Observar misiones con filtros.
final Provider<WatchMissionsUseCase> watchMissionsUseCaseProvider =
    Provider<WatchMissionsUseCase>(
      (ref) => WatchMissionsUseCase(ref.watch(missionRepositoryProvider)),
      name: 'watchMissionsUseCase',
    );

/// Crear una misión.
final Provider<CreateMissionUseCase> createMissionUseCaseProvider =
    Provider<CreateMissionUseCase>(
      (ref) => CreateMissionUseCase(ref.watch(missionRepositoryProvider)),
      name: 'createMissionUseCase',
    );

/// Editar una misión.
final Provider<UpdateMissionUseCase> updateMissionUseCaseProvider =
    Provider<UpdateMissionUseCase>(
      (ref) => UpdateMissionUseCase(ref.watch(missionRepositoryProvider)),
      name: 'updateMissionUseCase',
    );

/// Completar una misión.
final Provider<CompleteMissionUseCase> completeMissionUseCaseProvider =
    Provider<CompleteMissionUseCase>(
      (ref) => CompleteMissionUseCase(ref.watch(missionRepositoryProvider)),
      name: 'completeMissionUseCase',
    );

/// Saltear una misión.
final Provider<SkipMissionUseCase> skipMissionUseCaseProvider =
    Provider<SkipMissionUseCase>(
      (ref) => SkipMissionUseCase(ref.watch(missionRepositoryProvider)),
      name: 'skipMissionUseCase',
    );

/// Reordenar misiones.
final Provider<ReorderMissionsUseCase> reorderMissionsUseCaseProvider =
    Provider<ReorderMissionsUseCase>(
      (ref) => ReorderMissionsUseCase(ref.watch(missionRepositoryProvider)),
      name: 'reorderMissionsUseCase',
    );

/// Eliminar una misión.
final Provider<DeleteMissionUseCase> deleteMissionUseCaseProvider =
    Provider<DeleteMissionUseCase>(
      (ref) => DeleteMissionUseCase(ref.watch(missionRepositoryProvider)),
      name: 'deleteMissionUseCase',
    );

/// Historial de misiones completadas.
final Provider<GetMissionHistoryUseCase> getMissionHistoryUseCaseProvider =
    Provider<GetMissionHistoryUseCase>(
      (ref) => GetMissionHistoryUseCase(ref.watch(missionRepositoryProvider)),
      name: 'getMissionHistoryUseCase',
    );

// ── Casos de uso de evidencias ──────────────────────────────────────────────

/// Adjuntar una evidencia.
final Provider<AttachEvidenceUseCase> attachEvidenceUseCaseProvider =
    Provider<AttachEvidenceUseCase>(
      (ref) => AttachEvidenceUseCase(ref.watch(evidenceRepositoryProvider)),
      name: 'attachEvidenceUseCase',
    );

/// Procesar la cola de subidas.
final Provider<ProcessPendingUploadsUseCase>
processPendingUploadsUseCaseProvider = Provider<ProcessPendingUploadsUseCase>(
  (ref) => ProcessPendingUploadsUseCase(ref.watch(evidenceRepositoryProvider)),
  name: 'processPendingUploadsUseCase',
);

/// Observar cuántas evidencias quedan pendientes.
final Provider<WatchPendingUploadsUseCase> watchPendingUploadsUseCaseProvider =
    Provider<WatchPendingUploadsUseCase>(
      (ref) =>
          WatchPendingUploadsUseCase(ref.watch(evidenceRepositoryProvider)),
      name: 'watchPendingUploadsUseCase',
    );

/// Quitar la evidencia de una misión.
final Provider<RemoveEvidenceUseCase> removeEvidenceUseCaseProvider =
    Provider<RemoveEvidenceUseCase>(
      (ref) => RemoveEvidenceUseCase(ref.watch(evidenceRepositoryProvider)),
      name: 'removeEvidenceUseCase',
    );

/// Cuántas evidencias esperan subir. Alimenta el aviso de sincronización.
final StreamProvider<int> pendingUploadsProvider = StreamProvider<int>(
  (ref) => ref.watch(watchPendingUploadsUseCaseProvider).call(),
  name: 'pendingUploads',
);

// ── Casos de uso de Aura ────────────────────────────────────────────────────

/// Observar el saldo y el nivel.
final Provider<WatchAuraUseCase> watchAuraUseCaseProvider =
    Provider<WatchAuraUseCase>(
      (ref) => WatchAuraUseCase(ref.watch(auraRepositoryProvider)),
      name: 'watchAuraUseCase',
    );

/// Historial del ledger.
final Provider<GetAuraLedgerUseCase> getAuraLedgerUseCaseProvider =
    Provider<GetAuraLedgerUseCase>(
      (ref) => GetAuraLedgerUseCase(ref.watch(auraRepositoryProvider)),
      name: 'getAuraLedgerUseCase',
    );

/// Aura por día, para el gráfico.
final Provider<GetDailyAuraUseCase> getDailyAuraUseCaseProvider =
    Provider<GetDailyAuraUseCase>(
      (ref) => GetDailyAuraUseCase(ref.watch(auraRepositoryProvider)),
      name: 'getDailyAuraUseCase',
    );

/// Tabla de niveles.
final Provider<GetAuraLevelsUseCase> getAuraLevelsUseCaseProvider =
    Provider<GetAuraLevelsUseCase>(
      (ref) => GetAuraLevelsUseCase(ref.watch(auraRepositoryProvider)),
      name: 'getAuraLevelsUseCase',
    );

// ── Estado de sesión ────────────────────────────────────────────────────────

/// Usuario autenticado, o `null` si no hay sesión.
///
/// Es la raíz de la que cuelgan los guards del router y todo lo que necesite
/// saber quién está usando la app.
final StreamProvider<AppUser?> authStateProvider = StreamProvider<AppUser?>((
  ref,
) {
  // Modo sin backend: si no se corrió `flutterfire configure`, no hay app de
  // Firebase y tocar `FirebaseAuth.instance` lanza. Sin este corte el provider
  // falla, Riverpod lo reintenta con backoff y la app queda girando
  // temporizadores contra un backend que no existe. Sin sesión es la respuesta
  // correcta y honesta.
  if (Firebase.apps.isEmpty) {
    return Stream<AppUser?>.value(null);
  }
  return ref.watch(authRepositoryProvider).authStateChanges();
}, name: 'authState');

/// Perfil en vivo de la persona autenticada.
///
/// Va aparte de [authStateProvider] porque cambia por motivos distintos: el
/// stream de Auth solo reacciona a entrar y salir, mientras que el perfil
/// cambia al editarlo, al completar el onboarding o cuando el servidor otorga
/// Aura. Sin esta separación, editar el nombre no refrescaría la pantalla.
final StreamProvider<Result<AppUser>> profileProvider =
    StreamProvider<Result<AppUser>>((ref) {
      final uid = ref.watch(authStateProvider).value?.uid;
      if (uid == null) {
        return const Stream<Result<AppUser>>.empty();
      }
      return ref.watch(userRepositoryProvider).watchUser(uid);
    }, name: 'profile');

/// Repositorio de administración.
///
/// Lecturas directas contra Firestore —las reglas ya las restringen a
/// `isAdmin()`— y escrituras a través de Cloud Functions, para que ninguna
/// acción administrativa pueda ocurrir sin su entrada en `auditLog`.
final Provider<AdminRepository> adminRepositoryProvider =
    Provider<AdminRepository>(
      (ref) => AdminRepositoryImpl(
        firestore: ref.watch(firestoreProvider),
        functions: ref.watch(firebaseFunctionsProvider),
      ),
      name: 'adminRepository',
    );

/// Cambio de rol, con la salvaguarda de no cambiarse el propio.
final Provider<SetUserRoleUseCase> setUserRoleUseCaseProvider =
    Provider<SetUserRoleUseCase>(
      (ref) => SetUserRoleUseCase(ref.watch(adminRepositoryProvider)),
      name: 'setUserRoleUseCase',
    );

/// Suspensión y reactivación de cuentas.
final Provider<SetUserStatusUseCase> setUserStatusUseCaseProvider =
    Provider<SetUserStatusUseCase>(
      (ref) => SetUserStatusUseCase(ref.watch(adminRepositoryProvider)),
      name: 'setUserStatusUseCase',
    );

/// Resolución de reportes de la bandeja de moderación.
final Provider<ResolveReportUseCase> resolveReportUseCaseProvider =
    Provider<ResolveReportUseCase>(
      (ref) => ResolveReportUseCase(ref.watch(adminRepositoryProvider)),
      name: 'resolveReportUseCase',
    );

/// Métricas agregadas del panel.
final StreamProvider<Result<AdminStats>> adminStatsProvider =
    StreamProvider<Result<AdminStats>>(
      (ref) => ref.watch(adminRepositoryProvider).watchStats(),
      name: 'adminStats',
    );

/// Cola de moderación pendiente.
final StreamProvider<Result<List<Report>>> openReportsProvider =
    StreamProvider<Result<List<Report>>>(
      (ref) => ref.watch(adminRepositoryProvider).watchOpenReports(),
      name: 'openReports',
    );

/// Registro de auditoría, del más reciente al más viejo.
final StreamProvider<Result<List<AuditEntry>>> auditLogProvider =
    StreamProvider<Result<List<AuditEntry>>>(
      (ref) => ref.watch(adminRepositoryProvider).watchAuditLog(),
      name: 'auditLog',
    );

/// Acceso a Firebase Cloud Messaging.
final Provider<FirebaseMessagingDataSource>
firebaseMessagingDataSourceProvider = Provider<FirebaseMessagingDataSource>(
  (ref) => FirebaseMessagingDataSource(),
  name: 'firebaseMessagingDataSource',
);

/// Bandeja de notificaciones y registro de dispositivos.
final Provider<NotificationRepository> notificationRepositoryProvider =
    Provider<NotificationRepository>(
      (ref) => NotificationRepositoryImpl(
        firestore: ref.watch(firestoreProvider),
        messaging: ref.watch(firebaseMessagingDataSourceProvider),
      ),
      name: 'notificationRepository',
    );

/// Marca una notificación como leída y devuelve su destino.
final Provider<OpenNotificationUseCase> openNotificationUseCaseProvider =
    Provider<OpenNotificationUseCase>(
      (ref) =>
          OpenNotificationUseCase(ref.watch(notificationRepositoryProvider)),
      name: 'openNotificationUseCase',
    );

/// Pide el permiso del sistema y registra el dispositivo.
final Provider<EnableNotificationsUseCase> enableNotificationsUseCaseProvider =
    Provider<EnableNotificationsUseCase>(
      (ref) =>
          EnableNotificationsUseCase(ref.watch(notificationRepositoryProvider)),
      name: 'enableNotificationsUseCase',
    );

/// Bandeja en vivo de la persona autenticada.
final StreamProvider<Result<List<AppNotification>>> notificationsProvider =
    StreamProvider<Result<List<AppNotification>>>((ref) {
      final uid = ref.watch(authStateProvider).value?.uid;
      if (uid == null) {
        return Stream<Result<List<AppNotification>>>.value(
          const Failed<List<AppNotification>>(
            AuthFailure(
              messageKey: 'failure.auth.sessionExpired',
              code: 'no-session',
            ),
          ),
        );
      }
      return ref.watch(notificationRepositoryProvider).watchNotifications(uid);
    }, name: 'notifications');

/// Cantidad de notificaciones sin leer, para la insignia.
final StreamProvider<int> unreadNotificationsProvider = StreamProvider<int>((
  ref,
) {
  final uid = ref.watch(authStateProvider).value?.uid;
  // Sin sesión la insignia es cero, no un error: no hay nada que avisar.
  return uid == null
      ? Stream<int>.value(0)
      : ref.watch(notificationRepositoryProvider).watchUnreadCount(uid);
}, name: 'unreadNotifications');
