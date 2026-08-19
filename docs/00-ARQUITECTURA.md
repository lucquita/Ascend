# ASCEND — Arquitectura del Sistema

> "Crecé constantemente."
> Documento maestro de arquitectura. Versión 1.0 — Fase de diseño (sin código).

---

## 1. Principios rectores

| # | Principio | Consecuencia práctica |
|---|-----------|----------------------|
| 1 | **El dominio no conoce a Firebase** | `ascend_domain` es Dart puro, sin una sola dependencia de Flutter ni Firebase. Si mañana migramos a Supabase/backend propio, cambia una capa. |
| 2 | **La verdad vive en el servidor** | Aura, niveles, contadores y roles se calculan en Cloud Functions. El cliente nunca los escribe. |
| 3 | **Nada falla en rojo** | Toda operación devuelve `Result<T>`; ningún `throw` llega a la UI. Pantalla roja de Flutter = bug de severidad 1. |
| 4 | **Offline-first pragmático** | Firestore persistence + outbox local para archivos. La app se abre y es útil sin red. |
| 5 | **Costo por usuario es una métrica de arquitectura** | Cada query se diseña pensando en lecturas/mes. Desnormalizamos para leer barato. |
| 6 | **Feature-first, no layer-first en presentación** | Un desarrollador toca una carpeta para tocar una funcionalidad. |

---

## 2. Stack tecnológico y justificación

### 2.1 Núcleo

| Área | Elección | Por qué esta y no otra |
|------|----------|------------------------|
| Framework | **Flutter (stable channel)** | Un solo código para Android, iOS y el panel web. Requisito del producto. |
| Lenguaje | **Dart 3 (records, sealed classes, patterns)** | `sealed class` es la base de nuestro modelo de errores exhaustivo verificado por el compilador. |
| Estado | **Riverpod 3.x + `riverpod_generator`** | Compile-safe (sin `BuildContext` para leer estado), testeable sin widgets, `AsyncValue` modela loading/error/data de forma nativa — exactamente el requisito de resiliencia. Codegen elimina el boilerplate y los errores de tipo en providers. |
| Ruteo | **GoRouter** | Declarativo, deep links, guards por rol, y `ShellRoute` para el bottom nav persistente. Es el router oficialmente recomendado por el equipo de Flutter. |
| DI | **Riverpod como contenedor de DI** | No agregamos `get_it`. Riverpod ya es un grafo de dependencias con override por test/entorno. Dos contenedores es deuda técnica gratuita. |
| Inmutabilidad | **Freezed + json_serializable** | `copyWith`, `==`, unions y (de)serialización sin escribir 300 líneas a mano. |
| Errores funcionales | **`Result<T>` propio (sealed)** | Preferimos un tipo propio de 40 líneas a `dartz`/`fpdart` completo: menos curva de aprendizaje para el equipo, API adaptada a nuestros `Failure`. |
| Local storage | **Hive CE** (outbox + caché de preferencias) | Rápido, sin codegen pesado, suficiente para colas y flags. No usamos Isar (mantenimiento incierto) ni Drift (SQL es sobredimensionado aquí). |
| Imágenes | `cached_network_image` + `flutter_image_compress` | Comprimir en cliente antes de subir baja el costo de Storage ~80%. |
| Tipografía | **`google_fonts` en dev → fuente empaquetada en release** | Poppins descargada en runtime rompe el arranque offline. En release va como asset. |
| Logging | `logger` + Crashlytics | Logs estructurados; en release solo warning/error van a Crashlytics. |
| Tests | `flutter_test`, `mocktail`, `fake_cloud_firestore`, `integration_test`, `patrol` (E2E) | Cobertura objetivo: 90% en `domain`, 70% en `data`, smoke tests en flujos críticos. |
| CI/CD | GitHub Actions + Fastlane + Firebase App Distribution | Build, análisis, tests y distribución a testers en cada merge a `develop`. |

### 2.2 Backend

| Área | Elección | Justificación |
|------|----------|---------------|
| Auth | **Firebase Authentication** (email/password + Google + Apple) | Apple Sign-In es **obligatorio** en iOS si ofrecemos login social (guideline 4.8). Lo contemplamos desde el diseño. |
| Base de datos | **Cloud Firestore** (modo nativo, multi-región `nam5` o `eur3`) | Realtime, offline nativo, reglas de seguridad declarativas, escala horizontal sin ops. |
| Archivos | **Firebase Storage** | Integrado con Auth para reglas por UID. |
| Lógica servidor | **Cloud Functions v2 (TypeScript, Node 20)** | Triggers de Firestore para Aura y contadores; `onCall` para Gemini; Scheduler para recordatorios y agregados. |
| Push | **Firebase Cloud Messaging** | Requisito. Tokens multi-dispositivo. |
| IA | **Gemini API vía Cloud Function proxy** | Ver ADR-002. |
| Observabilidad | Crashlytics + Analytics + Performance + Cloud Logging | KPIs de producto y de estabilidad desde el día 1. |
| Config remota | **Firebase Remote Config** + doc `config/app` | Feature flags, versión mínima soportada, tabla de niveles de Aura editable sin release. |

---

## 3. Decisiones de arquitectura (ADR)

### ADR-001 — Monorepo con Melos, no un proyecto único

**Decisión:** repositorio único con `apps/ascend_mobile`, `apps/ascend_admin` y paquetes compartidos, orquestado con **Melos**.

**Por qué:** la app móvil y el panel admin comparten el 100% del dominio y ~80% de la capa de datos, pero **no** deben compartir presentación. Si fueran un solo proyecto Flutter con dos entrypoints, el bundle web del admin arrastraría cámara, FCM, animaciones y assets de la app móvil — inaceptable para tiempo de carga de un dashboard. Si fueran dos repos, el modelo de dominio divergiría en tres meses.

**Costo aceptado:** curva inicial de Melos (~medio día) y `melos bootstrap` obligatorio en onboarding de devs.

---

### ADR-002 — Gemini se llama SIEMPRE desde Cloud Functions, nunca desde el cliente ⚠️

**Esta es la corrección más importante a la propuesta original.**

Si el cliente Flutter llama a la Gemini API directamente, la API key viaja dentro del binario. Un APK se descompila en 5 minutos con `apktool`; en Flutter Web la key está literalmente en el JS servido. Consecuencia real: alguien extrae tu key y te genera una factura de miles de dólares en 48 horas. Esto **no es hipotético**, es el modo de fallo más común en apps con IA.

**Diseño correcto:**

```
Flutter  ──onCall──►  Cloud Function "generateGoalPlan"
                        1. verifica auth (context.auth.uid)
                        2. rate limit por usuario (App Check + contador Firestore)
                        3. valida y sanitiza el input
                        4. lee GEMINI_API_KEY de Secret Manager
                        5. llama a Gemini con structured output (JSON schema)
                        6. valida el JSON contra el schema
                        7. registra costo/tokens en aiJobs
                        8. devuelve DTO limpio
```

**Beneficios adicionales:** presupuesto por usuario (ej. 20 generaciones/día), cambio de modelo sin release de app, caché de prompts, prompts versionados en servidor, y auditoría de costos por feature.

**Complemento: Firebase App Check** (Play Integrity + DeviceCheck + reCAPTCHA en web) para que solo binarios legítimos puedan invocar las funciones.

---

### ADR-003 — Aura es servidor-autoritativa

Si el cliente puede escribir `users/{uid}.aura`, el ranking es ficción: cualquiera con el SDK de Firebase se pone 1.000.000 de Aura. La gamificación pierde todo significado y con ella el producto.

**Diseño:**
- El cliente **solo** escribe `missions/{id}.status = completed`.
- Un trigger `onDocumentUpdated` valida la transición, calcula la recompensa según `config/app.auraRules`, escribe una entrada **append-only** en `users/{uid}/auraLedger` y actualiza `users/{uid}.aura` en una **transacción**.
- Las reglas de Firestore rechazan cualquier escritura del cliente sobre `aura`, `stats`, `role` y `counters`.

**Beneficio secundario:** el ledger es auditable. Si un día hay que revertir un exploit, se recalcula el saldo desde el ledger sin perder historia.

---

### ADR-004 — Roles por Custom Claims, no por campo en Firestore

Poner `role: "admin"` en `users/{uid}` y leerlo desde las reglas con `get()` cuesta **una lectura facturada por cada evaluación de regla** y es más lento. Peor: si el usuario puede escribir su propio documento, se auto-promueve a admin.

**Diseño:** el rol vive en el **custom claim** del token de Auth (`request.auth.token.role == 'admin'`), asignado exclusivamente por una Cloud Function protegida. Se espeja en Firestore **solo lectura** para poder listarlo en el panel admin.

---

### ADR-005 — Misiones en colección plana bajo el usuario, no anidadas bajo el objetivo

Intuitivamente `users/{uid}/goals/{goalId}/missions/{missionId}` parece correcto. Pero la pantalla más usada de la app es **"Hoy"**: todas las misiones del día, de todos los objetivos. Con misiones anidadas eso exige un `collectionGroup` con índices extra, o N queries.

**Diseño:** `users/{uid}/missions/{missionId}` con `goalId` como campo indexado.
- "Hoy" → 1 query: `where dueDate <= hoy and status == pending order by order`
- "Misiones de este objetivo" → 1 query: `where goalId == X`
- Reglas de seguridad triviales: todo bajo `/users/{uid}/**` pertenece a `uid`.
- Borrado en cascada de un objetivo → Function con `bulkWriter`.

---

### ADR-006 — Feed global paginado en el MVP; fan-out en v2

Fan-out on write (copiar cada post al timeline de cada seguidor) es lo correcto a escala de millones, pero multiplica escrituras y complejidad antes de tener usuarios.

**MVP:** colección global `posts` ordenada por `createdAt desc`, paginada con cursores (`startAfterDocument`), con filtros por categoría y pestaña "Siguiendo" (`whereIn` sobre hasta 30 seguidos).
**Disparador de migración documentado:** cuando p95 de seguidos > 30 o el feed supere ~500 escrituras/min, se activa `users/{uid}/timeline` por fan-out. La capa `PostRepository` no cambia — solo su implementación.

---

### ADR-007 — Sin lógica de negocio en widgets, garantizado por estructura

No es una convención voluntaria: `ascend_domain` **no depende de Flutter**, así que es físicamente imposible importar un widget ahí. Y el análisis estático (`import_lint` / reglas de `custom_lint`) rompe el build si `presentation` importa `data` directamente.

---

## 4. Arquitectura en capas

```
┌───────────────────────────────────────────────────────────────┐
│  PRESENTATION        (Flutter · Widgets · GoRouter)           │
│  Pantallas, componentes, navegación. Cero lógica de negocio.  │
│  Sólo lee providers y despacha intenciones.                   │
└──────────────────────────┬────────────────────────────────────┘
                           │ observa AsyncValue<T> / llama métodos
┌──────────────────────────▼────────────────────────────────────┐
│  APPLICATION         (Riverpod Notifiers · Controllers)       │
│  Orquesta casos de uso, mantiene estado de pantalla,          │
│  traduce Failure → mensaje amigable. Sin Firebase.            │
└──────────────────────────┬────────────────────────────────────┘
                           │ invoca UseCase
┌──────────────────────────▼────────────────────────────────────┐
│  DOMAIN              (Dart puro · sin dependencias)           │
│  Entities · Value Objects · Failures · UseCases ·             │
│  Repository (interfaces abstractas) · reglas de negocio       │
└──────────────────────────▲────────────────────────────────────┘
                           │ implementa (Dependency Inversion)
┌──────────────────────────┴────────────────────────────────────┐
│  DATA                (Firebase · HTTP · Hive)                 │
│  RepositoryImpl · DataSources (remote/local) · DTOs ·         │
│  Mappers · manejo de excepciones → Failure                    │
└───────────────────────────────────────────────────────────────┘
```

**Regla de dependencias:** las flechas apuntan siempre hacia adentro. `data` conoce a `domain`; `domain` no conoce a nadie.

### 4.1 Flujo completo de ejemplo — "Completar misión"

```
MissionDetailScreen
  └─ ref.read(missionControllerProvider.notifier).complete(missionId, evidence)
       │
       ├─ MissionController (application)
       │    ├─ state = AsyncLoading()
       │    ├─ result = await completeMissionUseCase(params)
       │    └─ state = result.fold(
       │           onFailure: (f) => AsyncError(f),      // nunca throw
       │           onSuccess: (m) => AsyncData(m))
       │
       ├─ CompleteMissionUseCase (domain)
       │    ├─ valida: ¿la misión requiere evidencia? ¿ya está completada?
       │    ├─ uploadEvidenceUseCase(...)  → EvidenceRepository
       │    └─ missionRepository.complete(...)
       │
       ├─ MissionRepositoryImpl (data)
       │    ├─ try { await remoteDs.updateStatus(...) }
       │    ├─ on FirebaseException  → Failure.server / Failure.permission
       │    ├─ on SocketException    → encola en outbox → Failure.offline(queued)
       │    └─ devuelve Result<Mission>
       │
       └─ [SERVIDOR] onMissionCompleted (Cloud Function)
            ├─ transacción: auraLedger += reward, users.aura += reward
            ├─ recalcula goal.progress y streak
            ├─ si progress == 100% → desbloquea logro + push
            └─ opcional: crea post automático si el usuario lo permitió
```

La UI nunca ve una excepción. Ve `AsyncLoading`, `AsyncData` o `AsyncError(Failure)` — y `Failure` ya trae un mensaje traducido y una acción sugerida.

---

## 5. Estrategia de resiliencia — "jamás un error de Flutter"

### 5.1 Cuatro anillos de defensa

**Anillo 1 — Tipos.** Ninguna función de `data` lanza. Todas devuelven `Result<T, Failure>`.

```dart
sealed class Failure {
  const Failure({required this.messageKey, this.cause, this.stackTrace});
  final String messageKey;   // clave i18n, no texto crudo
  final Object? cause;
  final StackTrace? stackTrace;
}

final class NetworkFailure     extends Failure {}  // sin conexión
final class TimeoutFailure     extends Failure {}
final class ServerFailure      extends Failure {}  // 5xx / Firestore unavailable
final class AuthFailure        extends Failure {}  // credenciales, sesión expirada
final class PermissionFailure  extends Failure {}  // reglas de Firestore
final class ValidationFailure  extends Failure {}  // input del usuario
final class NotFoundFailure    extends Failure {}
final class QuotaFailure       extends Failure {}  // límite de IA alcanzado
final class UnknownFailure     extends Failure {}
```

Al ser `sealed`, un `switch` sobre `Failure` que olvide un caso **no compila**. El mapeo a mensajes amigables es exhaustivo por construcción.

**Anillo 2 — Estados de UI obligatorios.** Todo widget que consume datos usa un componente compartido que exige los cinco estados:

```
AsyncStateBuilder<T>(
  value:    ...,
  loading:  → Skeleton (shimmer), nunca un spinner desnudo a pantalla completa
  error:    → ErrorStateView(failure, onRetry:)   // ilustración + causa + acción
  empty:    → EmptyStateView(illustration, título, CTA)
  offline:  → OfflineBanner + datos cacheados en modo lectura
  data:     → contenido
)
```

**Anillo 3 — Red de seguridad global.**

```dart
FlutterError.onError        → Crashlytics + log
PlatformDispatcher.instance.onError → Crashlytics
runZonedGuarded(...)        → captura async no manejado
ErrorWidget.builder         → reemplaza la PANTALLA ROJA por un widget
                              de fallback discreto, incluso en release
```

**Anillo 4 — Degradación.** Si Gemini no responde: se ofrecen plantillas de misiones predefinidas por categoría. Si Storage falla: la misión se completa igual y la evidencia queda en la cola de subida. La app **nunca bloquea al usuario por una dependencia externa**.

### 5.2 Offline

- Firestore `persistenceEnabled: true` con caché ilimitada en móvil → lecturas y escrituras funcionan sin red y se sincronizan solas.
- `connectivity_plus` alimenta un `connectivityProvider` global → banner "Sin conexión — se sincronizará al volver".
- **Outbox propio en Hive** solo para lo que Firestore no cubre: **subidas de imágenes**. Cada evidencia pendiente se guarda con su path local y se reintenta con backoff exponencial cuando vuelve la red.
- Escrituras críticas son **idempotentes** (ID generado en cliente) para que el reintento no duplique.

---

## 6. Árbol de carpetas

```
ascend/
├── melos.yaml
├── pubspec.yaml                      # workspace raíz
├── analysis_options.yaml             # lints estrictos compartidos
├── .github/workflows/                # ci.yaml · release-android.yaml · release-ios.yaml · deploy-web.yaml
├── docs/                             # ESTE conjunto de documentos
│
├── apps/
│   ├── ascend_mobile/                # ← App Android + iOS
│   │   ├── lib/
│   │   │   ├── main.dart
│   │   │   ├── bootstrap.dart              # init Firebase, Crashlytics, zonas, DI overrides
│   │   │   ├── app.dart                    # MaterialApp.router
│   │   │   ├── router/
│   │   │   │   ├── app_router.dart         # GoRouter + ShellRoute
│   │   │   │   ├── routes.dart             # constantes de rutas tipadas
│   │   │   │   ├── guards.dart             # authGuard · onboardingGuard · forceUpdateGuard
│   │   │   │   └── transitions.dart
│   │   │   └── features/                   # ← FEATURE-FIRST
│   │   │       ├── splash/
│   │   │       ├── onboarding/
│   │   │       ├── auth/
│   │   │       │   ├── application/        # auth_controller.dart, form_state.dart
│   │   │       │   └── presentation/
│   │   │       │       ├── screens/        # login · register · forgot_password · verify_email
│   │   │       │       └── widgets/
│   │   │       ├── home/                   # pantalla "Hoy"
│   │   │       ├── goals/
│   │   │       │   ├── application/        # goals_list_controller · goal_form_controller
│   │   │       │   └── presentation/
│   │   │       │       ├── screens/        # goals_list · goal_detail · goal_wizard · goal_edit
│   │   │       │       └── widgets/        # goal_card · progress_ring · category_chip
│   │   │       ├── missions/
│   │   │       ├── evidence/               # cámara, recorte, compresión, preview
│   │   │       ├── aura/                   # nivel, historial, logros, estadísticas
│   │   │       ├── community/
│   │   │       │   └── presentation/screens/  # feed · post_detail · create_post · comments · public_profile · report
│   │   │       ├── ai/                     # wizard IA, streaming de plan, revisión
│   │   │       ├── notifications/
│   │   │       ├── profile/
│   │   │       └── settings/               # tema · idioma · notificaciones · privacidad · eliminar cuenta
│   │   ├── assets/  (fonts/ · images/ · lottie/ · illustrations/)
│   │   ├── android/  ios/
│   │   └── test/  integration_test/
│   │
│   └── ascend_admin/                 # ← Panel Web (Flutter Web)
│       ├── lib/
│       │   ├── main.dart · bootstrap.dart · app.dart
│       │   ├── router/               # rutas con guard de rol admin
│       │   ├── shell/                # AdminScaffold: sidebar + topbar + breadcrumbs responsive
│       │   └── features/
│       │       ├── auth/             # login admin (rechaza no-admins)
│       │       ├── dashboard/        # KPIs, gráficos, actividad reciente
│       │       ├── users/            # tabla, detalle, suspender, cambiar rol
│       │       ├── goals/            # explorador + plantillas de objetivos
│       │       ├── missions/         # CRUD de plantillas de misiones por categoría
│       │       ├── posts/            # moderación de publicaciones y comentarios
│       │       ├── reports/          # cola de reportes (bandeja de moderación)
│       │       ├── categories/       # CRUD de categorías
│       │       ├── analytics/        # métricas y exportación CSV
│       │       ├── config/           # niveles de Aura, feature flags, versión mínima
│       │       └── audit/            # log de acciones administrativas
│       └── web/  test/
│
├── packages/
│   ├── ascend_core/                  # Dart puro — sin Flutter
│   │   └── lib/src/
│   │       ├── result/               # Result<T> · extensiones fold/map/flatMap
│   │       ├── errors/               # Failure (sealed) · AppException
│   │       ├── typedefs.dart
│   │       ├── utils/                # date_utils · id_generator · debouncer · retry_policy
│   │       ├── validators/           # email · password · handle · longitud
│   │       └── logging/
│   │
│   ├── ascend_domain/                # Dart puro — el corazón del negocio
│   │   └── lib/src/
│   │       ├── entities/             # app_user · goal · mission · evidence · post · comment
│   │       │                         # aura_entry · aura_level · notification · category · report
│   │       ├── value_objects/        # email · handle · aura_points · progress · difficulty
│   │       ├── enums/                # goal_status · mission_status · post_type · user_role · report_reason
│   │       ├── repositories/         # INTERFACES: auth · user · goal · mission · evidence
│   │       │                         # post · comment · aura · notification · category · report · ai · storage
│   │       └── usecases/
│   │           ├── auth/             # sign_in · sign_up · sign_out · reset_password · delete_account
│   │           ├── goals/            # create · update · delete · watch_goals · complete_goal · recalc_progress
│   │           ├── missions/         # watch_today · complete_mission · skip · reorder · filter_missions
│   │           ├── aura/             # get_level · watch_aura · get_stats · get_leaderboard
│   │           ├── community/        # publish_post · toggle_like · add_comment · report_content · watch_feed
│   │           ├── ai/               # generate_goal_plan · suggest_missions · get_motivation
│   │           └── notifications/    # register_token · schedule_reminder · mark_read
│   │
│   ├── ascend_data/                  # implementaciones — aquí vive Firebase
│   │   └── lib/src/
│   │       ├── dtos/                 # *_dto.dart con Freezed + json_serializable
│   │       ├── mappers/              # DTO ⇄ Entity (ningún DTO sale de esta capa)
│   │       ├── datasources/
│   │       │   ├── remote/           # firebase_auth_ds · firestore_user_ds · firestore_goal_ds
│   │       │   │                     # firestore_mission_ds · firestore_post_ds · storage_ds
│   │       │   │                     # gemini_functions_ds · fcm_ds
│   │       │   └── local/            # hive_outbox_ds · prefs_ds · cache_ds
│   │       ├── repositories/         # *_repository_impl.dart  ← try/catch vive AQUÍ
│   │       ├── mappers/error_mapper.dart   # FirebaseException → Failure (mapa exhaustivo)
│   │       └── providers/            # providers de infraestructura (FirebaseAuth, Firestore, …)
│   │
│   ├── ascend_ui/                    # Design System
│   │   └── lib/src/
│   │       ├── theme/                # app_theme (light/dark) · color_scheme · text_theme · spacing
│   │       │                         # radii · shadows · durations · breakpoints
│   │       ├── tokens/               # AscendColors · AscendSpacing · AscendRadius
│   │       ├── atoms/                # AscendButton · AscendTextField · AscendChip · AscendAvatar
│   │       ├── molecules/            # AscendCard · ProgressRing · AuraBadge · StreakFlame · MissionTile
│   │       ├── organisms/            # AsyncStateBuilder · ErrorStateView · EmptyStateView
│   │       │                         # OfflineBanner · AscendSkeleton · ConfirmSheet
│   │       ├── responsive/           # Breakpoints · ResponsiveBuilder · AdaptiveScaffold
│   │       └── gallery/              # widgetbook — catálogo visual de componentes
│   │
│   └── ascend_l10n/                  # ARB es/en desde el día 1
│
└── backend/
    ├── firebase.json
    ├── firestore.rules               # ← cerradas por defecto
    ├── firestore.indexes.json
    ├── storage.rules
    └── functions/                    # TypeScript · Node 20
        └── src/
            ├── index.ts
            ├── triggers/             # onMissionCompleted · onGoalWrite · onPostLike
            │                         # onCommentWrite · onReportCreated · onUserCreate · onUserDelete
            ├── callable/             # generateGoalPlan · suggestMissions · getMotivation
            │                         # setUserRole · moderateContent · deleteAccount
            ├── scheduled/            # dailyReminders · streakChecker · aggregateStats
            │                         # cleanupExpiredMissions · costReport
            ├── services/             # geminiService · auraService · notificationService · moderationService
            ├── config/               # prompts versionados · auraRules · limits
            └── lib/                  # validators · errors · logger
```

---

## 7. Inyección de dependencias

Riverpod es el contenedor. Grafo por capas:

```dart
// data/providers — infraestructura
final firebaseAuthProvider  = Provider((_) => FirebaseAuth.instance);
final firestoreProvider     = Provider((_) => FirebaseFirestore.instance);

// data — datasources
final goalRemoteDsProvider  = Provider((ref) => FirestoreGoalDs(ref.watch(firestoreProvider)));

// data — implementación del contrato del dominio
final goalRepositoryProvider = Provider<GoalRepository>(   // ← tipo del DOMINIO
  (ref) => GoalRepositoryImpl(ref.watch(goalRemoteDsProvider)),
);

// domain — caso de uso
final createGoalUseCaseProvider =
    Provider((ref) => CreateGoalUseCase(ref.watch(goalRepositoryProvider)));

// application — controlador de pantalla
@riverpod
class GoalFormController extends _$GoalFormController { ... }
```

**En tests:** `ProviderScope(overrides: [goalRepositoryProvider.overrideWithValue(FakeGoalRepository())])`. Cero mocks de Firebase en tests de dominio.

---

## 8. Sistema de diseño

### 8.1 Paleta

| Token | Light | Dark | Uso |
|-------|-------|------|-----|
| `primary` | `#3B82F6` | `#60A5FA` | acciones, marca, navegación |
| `success` | `#22C55E` | `#4ADE80` | progreso, misión completada |
| `aura` | `#F59E0B` | `#FBBF24` | puntos, niveles, rachas — **color emocional del producto** |
| `surface` | `#FFFFFF` | `#111827` | fondo de tarjetas |
| `background` | `#F9FAFB` | `#0B0F17` | fondo de pantalla |
| `onSurface` | `#1F2937` | `#F3F4F6` | texto principal |
| `outline` | `#E5E7EB` | `#1F2937` | bordes, separadores |
| `error` | `#EF4444` | `#F87171` | errores, destructivo |

**Nota de accesibilidad:** `#F59E0B` sobre blanco da contraste 2.15:1 — **reprueba WCAG AA para texto**. Se usa como color de *relleno* (badges, anillos, iconos ≥24px), nunca para texto pequeño sobre fondo claro. Para texto de Aura en light mode usamos `#B45309`. Todos los pares de color se validan en CI con un test de contraste.

### 8.2 Tipografía — Poppins

| Rol | Tamaño / Peso |
|-----|---------------|
| Display | 32 / SemiBold |
| Headline | 24 / SemiBold |
| Title | 20 / Medium |
| Body | 16 / Regular |
| Label | 14 / Medium |
| Caption | 12 / Regular |

### 8.3 Fundamentos

- **Espaciado:** escala 4pt → `4, 8, 12, 16, 24, 32, 48, 64`.
- **Radios:** `8` (chips), `12` (inputs), `16` (tarjetas), `24` (sheets), `999` (píldoras).
- **Elevación:** sombras suaves, nunca las de Material por defecto. Estética Linear: bordes 1px + sombra sutil.
- **Movimiento:** 150ms (micro), 250ms (transición), 400ms (celebración). `Curves.easeOutCubic`.
- **Momentos de celebración:** completar misión → háptico + animación de Aura + confeti sobrio. Es la mecánica de refuerzo central (Duolingo).
- **Breakpoints:** `<600` móvil · `600–1024` tablet · `>1024` escritorio. El admin usa sidebar fija >1024, drawer debajo.
- **Accesibilidad:** contraste AA, targets táctiles ≥48dp, semantics en todo elemento interactivo, soporte de `textScaleFactor` hasta 1.5 sin overflow.

---

## 9. Rendimiento y costos

| Riesgo | Mitigación |
|--------|-----------|
| Lecturas de Firestore explotan | Paginación con cursores (20 items), `snapshots()` solo donde el realtime aporta valor (feed, misiones de hoy); `get()` con caché en el resto. |
| N+1 al pintar el feed | Autor **desnormalizado** en cada post (`author.displayName`, `photoUrl`, `level`). Una Function propaga cambios de perfil. |
| Contar likes/comentarios | Contadores desnormalizados actualizados por trigger. Nunca `collection.count()` en el render. |
| Imágenes pesadas | Compresión en cliente (máx 1080px, JPEG q80) + generación de thumbnail en Function. |
| Costo de Gemini | Cuota por usuario/día, structured output (menos tokens), caché de planes por categoría, y registro de costo en `aiJobs`. |
| Arranque lento | Firebase se inicializa en `bootstrap.dart` con splash nativa; features pesadas cargan diferido. |

**Presupuestos de rendimiento:** arranque en frío < 2s (gama media), jank < 1% de frames, tamaño APK < 40MB, primer render del admin web < 3s.

---

## 10. Seguridad — resumen

1. Firestore y Storage **cerrados por defecto** (`allow read, write: if false`), permisos concedidos por ruta.
2. Roles por **custom claims**, asignados solo por Function protegida.
3. **App Check** obligatorio en todas las Functions callable.
4. Campos protegidos (`aura`, `stats`, `role`, `counters`, `moderation`) rechazados en escrituras de cliente por regla explícita.
5. Secretos (Gemini key) en **Secret Manager**, jamás en el repo ni en `--dart-define` del cliente.
6. Validación en tres niveles: UI → UseCase → Reglas/Function.
7. **Eliminación de cuenta** real (requisito de App Store y Google Play): Function que borra Auth, documentos, Storage y anonimiza contenido público.
8. Cumplimiento: política de privacidad, consentimiento de datos, exportación de datos del usuario (GDPR/Ley 25.326 AR).

---

## 11. Riesgos identificados

| # | Riesgo | Impacto | Plan |
|---|--------|---------|------|
| R1 | Fuga de la API key de Gemini | Alto | ADR-002 (proxy + App Check + cuotas) |
| R2 | Manipulación de Aura | Alto | ADR-003 (servidor-autoritativo + ledger) |
| R3 | Contenido abusivo en el feed | Alto (retiro de la tienda) | Moderación IA + reportes + cola admin + bloqueo de usuarios |
| R4 | Costos de Firestore fuera de control | Medio | Presupuestos, alertas de facturación, revisión de queries en PR |
| R5 | Baja retención (el problema real de las apps de hábitos) | Alto | Rachas, recordatorios inteligentes, misiones de 2 minutos, celebración |
| R6 | Rechazo en App Store por login social | Medio | Apple Sign-In desde Fase 1 |
| R7 | Peso del bundle web del admin | Medio | ADR-001 (apps separadas) + `--wasm` / tree shaking |
