# ASCEND — Navegación, Pantallas y Funcionalidades

---

## 1. Diagrama de navegación — App móvil

```
                        ┌──────────────────┐
                        │   NativeSplash   │  (init Firebase, Remote Config,
                        └────────┬─────────┘   restauración de sesión)
                                 │
                        ┌────────▼─────────┐
                        │   /  RootGate    │  redirect de GoRouter
                        └────────┬─────────┘
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
  sin sesión              sesión sin onboarding      sesión completa
        │                        │                        │
┌───────▼────────┐      ┌────────▼────────┐      ┌────────▼────────┐
│  AUTH BRANCH   │      │   /onboarding   │      │   APP SHELL     │
└───────┬────────┘      │  0 bienvenida   │      │  (StatefulShell │
        │               │  1 intereses    │      │     Route)      │
        │               │  2 objetivo #1  │      └────────┬────────┘
        │               │  3 notificac.   │               │
        │               └─────────────────┘               │
        │                                                 │
 /login ──► /register ──► /verify-email                    │
   │  └──► /forgot-password ──► /reset-sent                │
   │                                                       │
   └───────────────────────────────────────────────────────┘

╔══════════════════════════════ APP SHELL ══════════════════════════════╗
║  BottomNavigationBar — 5 ramas con estado independiente               ║
║                                                                        ║
║  🏠 Hoy       🎯 Objetivos      ➕        🌐 Comunidad      👤 Perfil   ║
║  /home        /goals        (modal)      /community       /profile     ║
╚════════════════════════════════════════════════════════════════════════╝
     │              │            │              │                │
     │              │            │              │                │
┌────▼────┐  ┌──────▼──────┐  ┌──▼───────┐  ┌───▼──────┐  ┌──────▼──────┐
│ /home   │  │ /goals      │  │ FAB      │  │/community│  │ /profile    │
│         │  │             │  │ modal    │  │          │  │             │
│ ├ misión│  │ ├ /goals/   │  │ ├ Nuevo  │  │ ├ /post/ │  │ ├ /profile/ │
│ │ del   │  │ │  :id      │  │ │ objetivo│ │ │  :id   │  │ │  edit     │
│ │ día   │  │ │  ├ detalle│  │ ├ Nueva  │  │ │ ├coment│  │ ├ /profile/ │
│ ├ racha │  │ │  ├ editar │  │ │ misión  │ │ │ ├repor.│  │ │  aura     │
│ ├ aura  │  │ │  └ misio- │  │ └ Publicar│ │ ├/create-│  │ ├ /profile/ │
│ └ suger.│  │ │     nes   │  │           │  │ │  post  │  │ │  stats    │
│    IA   │  │ └ /goals/new│  │           │  │ └/u/:hand│  │ ├ /achieve- │
└────┬────┘  │    (wizard) │  └──────────┘  │   le     │  │ │  ments    │
     │       └──────┬──────┘                 └──────────┘  │ └ /settings │
     │              │                                      └──────┬──────┘
     └──────────────┴──────────────┬───────────────────────────────┘
                                   │
                        ┌──────────▼───────────┐
                        │  /missions/:id       │  detalle de misión
                        │   └ /missions/:id/   │
                        │       evidence       │  cámara / galería / nota
                        └──────────┬───────────┘
                                   │  al completar
                        ┌──────────▼───────────┐
                        │  CelebrationOverlay  │  +Aura · ¿nivel nuevo? · ¿publicar?
                        └──────────────────────┘

RUTAS TRANSVERSALES (fuera del shell, full screen)
  /notifications              bandeja
  /settings/*                 cuenta · notificaciones · privacidad · tema · idioma
                              · ayuda · legal · eliminar-cuenta
  /search                     buscar usuarios y objetivos públicos
  /force-update               bloqueante si versión < minSupportedVersion
  /maintenance                bloqueante por feature flag
  /error                      fallback global
```

### 1.1 Wizard de creación de objetivo con IA (flujo clave del producto)

```
/goals/new
   │
   ├─ Paso 1  ¿Qué querés lograr?         → título libre + categoría sugerida por IA
   ├─ Paso 2  ¿Para cuándo?               → horizonte 30/60/90 días o fecha
   ├─ Paso 3  ¿Cuánto tiempo por día?     → 10 / 20 / 45 / 60+ min
   ├─ Paso 4  ¿Tu nivel actual?           → principiante / intermedio / avanzado
   │
   ├─ [Cloud Function generateGoalPlan] ──► pantalla de generación
   │      · animación de progreso con mensajes rotativos
   │      · timeout 25s → fallback a plantillas de la categoría
   │      · error → "Creá tu plan manualmente" (nunca callejón sin salida)
   │
   ├─ Paso 5  REVISIÓN — el usuario es el dueño del plan
   │      · milestones editables (agregar/quitar/renombrar)
   │      · misiones editables (dificultad, fecha, eliminar)
   │      · botón "Regenerar" (consume cuota)
   │
   └─ Paso 6  Confirmar → escritura en batch (goal + N misiones) → /goals/:id
```

**Decisión de UX justificada:** la IA **propone**, nunca **impone**. Un plan que el usuario no editó no lo siente suyo, y el abandono se dispara. El paso 5 es obligatorio.

---

## 2. Diagrama de navegación — Panel Admin (Flutter Web)

```
┌────────────────────────────────────────────────────────────────────┐
│  /login   →  verifica claim role == 'admin'                        │
│              si no es admin → cierra sesión + "Acceso restringido" │
└──────────────────────────────┬─────────────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────────────┐
│  ADMIN SHELL   sidebar fija (>1024px) · drawer (<1024px)           │
│  ┌────────────────┬───────────────────────────────────────────────┐│
│  │ ASCEND admin   │  Topbar: buscador · notificaciones · perfil   ││
│  │                ├───────────────────────────────────────────────┤│
│  │ ▸ Dashboard    │                                               ││
│  │ ▸ Usuarios     │                                               ││
│  │ ▸ Objetivos    │            ÁREA DE CONTENIDO                  ││
│  │ ▸ Misiones     │         (con breadcrumbs y rutas anidadas)    ││
│  │ ▸ Publicaciones│                                               ││
│  │ ▸ Reportes  ⑦  │                                               ││
│  │ ▸ Categorías   │                                               ││
│  │ ▸ Analíticas   │                                               ││
│  │ ▸ Configuración│                                               ││
│  │ ▸ Auditoría    │                                               ││
│  └────────────────┴───────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────────┘

/admin/dashboard
/admin/users                 → /admin/users/:uid              (perfil · objetivos · actividad · acciones)
/admin/goals                 → /admin/goals/:uid/:goalId      (solo lectura + plantillas)
/admin/missions              → /admin/missions/templates/:id  (CRUD de plantillas)
/admin/posts                 → /admin/posts/:postId           (moderar · ver comentarios)
/admin/reports               → /admin/reports/:reportId       (resolver)
/admin/categories            → /admin/categories/:id
/admin/analytics             → retención · embudo · uso de IA · costos
/admin/config                → aura-rules · feature-flags · versión mínima
/admin/audit                 → log de acciones administrativas
```

**Guard de rol:** el `redirect` de GoRouter lee el custom claim del `IdTokenResult`. Además, las reglas de Firestore vuelven a validar el rol — **la seguridad nunca depende del cliente**.

---

## 3. Lista completa de pantallas

### 3.1 App móvil — 54 pantallas

#### Arranque y autenticación (9)
| # | Ruta | Pantalla | Notas |
|---|------|----------|-------|
| 1 | — | Splash nativa | Sin flash blanco entre nativa y Flutter |
| 2 | `/` | RootGate | Decide destino; nunca visible |
| 3 | `/onboarding` | Onboarding (4 pasos) | Valor, intereses, primer objetivo, permiso de notificaciones |
| 4 | `/login` | Login | Email/pass, Google, Apple |
| 5 | `/register` | Registro | Handle en tiempo real, fuerza de contraseña, T&C |
| 6 | `/forgot-password` | Recuperar contraseña | |
| 7 | `/reset-sent` | Confirmación de envío | |
| 8 | `/verify-email` | Verificación de email | Reenviar con cooldown |
| 9 | `/blocked` | Cuenta suspendida | Motivo + contacto de soporte |

#### Hoy (5)
| # | Ruta | Pantalla |
|---|------|----------|
| 10 | `/home` | Hoy — saludo, Aura, racha, misiones del día, progreso semanal |
| 11 | `/home/all-missions` | Todas las misiones pendientes con filtros |
| 12 | `/home/streak` | Detalle de racha con calendario |
| 13 | `/home/ai-suggestions` | Sugerencias de la IA |
| 14 | `/search` | Buscador global |

#### Objetivos (9)
| # | Ruta | Pantalla |
|---|------|----------|
| 15 | `/goals` | Lista con pestañas Activos / Pausados / Completados |
| 16 | `/goals/new` | Wizard de creación (6 pasos, ver §1.1) |
| 17 | `/goals/new/generating` | Generación IA con fallback |
| 18 | `/goals/new/review` | Revisión y edición del plan |
| 19 | `/goals/:id` | Detalle: progreso, milestones, misiones, Aura, historial |
| 20 | `/goals/:id/edit` | Edición |
| 21 | `/goals/:id/missions` | Todas las misiones del objetivo |
| 22 | `/goals/:id/stats` | Estadísticas del objetivo |
| 23 | `/goals/:id/complete` | Celebración de finalización |

#### Misiones y evidencias (7)
| # | Ruta | Pantalla |
|---|------|----------|
| 24 | `/missions/new` | Crear misión manual |
| 25 | `/missions/:id` | Detalle |
| 26 | `/missions/:id/edit` | Edición |
| 27 | `/missions/:id/evidence` | Captura de evidencia (cámara/galería) |
| 28 | `/missions/:id/evidence/preview` | Recorte, compresión y nota |
| 29 | `/missions/:id/complete` | Celebración: +Aura, nivel, CTA de publicar |
| 30 | `/missions/history` | Historial completo con evidencias |

#### Aura y progreso (5)
| # | Ruta | Pantalla |
|---|------|----------|
| 31 | `/profile/aura` | Nivel, barra de progreso, próximo nivel |
| 32 | `/profile/aura/history` | Ledger con motivo de cada movimiento |
| 33 | `/profile/stats` | Gráficos: Aura semanal, misiones por categoría, constancia |
| 34 | `/profile/achievements` | Grilla de logros (bloqueados/desbloqueados) |
| 35 | `/leaderboard` | Ranking (opt-in por privacidad) |

#### Comunidad (9)
| # | Ruta | Pantalla |
|---|------|----------|
| 36 | `/community` | Feed con pestañas Para vos / Siguiendo / Categorías |
| 37 | `/community/create` | Crear publicación (desde logro o reflexión) |
| 38 | `/community/post/:id` | Detalle de publicación |
| 39 | `/community/post/:id/comments` | Hilo de comentarios |
| 40 | `/community/post/:id/likes` | Quiénes dieron like |
| 41 | `/u/:handle` | Perfil público de otro usuario |
| 42 | `/u/:handle/followers` | Seguidores |
| 43 | `/u/:handle/following` | Siguiendo |
| 44 | `/report/:type/:id` | Reportar contenido |

#### Perfil y ajustes (10)
| # | Ruta | Pantalla |
|---|------|----------|
| 45 | `/profile` | Mi perfil |
| 46 | `/profile/edit` | Editar perfil (foto, nombre, handle, bio) |
| 47 | `/notifications` | Bandeja de notificaciones |
| 48 | `/settings` | Índice de ajustes |
| 49 | `/settings/account` | Email, contraseña, sesiones |
| 50 | `/settings/notifications` | Preferencias y horario de recordatorio |
| 51 | `/settings/privacy` | Visibilidad, ranking, bloqueados |
| 52 | `/settings/appearance` | Tema e idioma |
| 53 | `/settings/legal` | Términos, privacidad, licencias |
| 54 | `/settings/delete-account` | Baja de cuenta (doble confirmación) |

#### Estados globales (no cuentan como pantallas de producto)
`/force-update` · `/maintenance` · `/error` · `/no-connection` · pantalla de fallback de `ErrorWidget.builder`

---

### 3.2 Panel Admin — 24 pantallas

| # | Ruta | Pantalla |
|---|------|----------|
| 1 | `/login` | Login de administrador |
| 2 | `/unauthorized` | Acceso denegado |
| 3 | `/admin/dashboard` | KPIs: usuarios activos, misiones/día, Aura otorgada, reportes abiertos, costo de IA |
| 4 | `/admin/users` | Tabla con búsqueda, filtros, orden y paginación |
| 5 | `/admin/users/:uid` | Detalle: perfil, objetivos, actividad, Aura |
| 6 | `/admin/users/:uid/edit` | Editar estado y rol |
| 7 | `/admin/users/new` | Crear usuario/admin manualmente |
| 8 | `/admin/goals` | Explorador global de objetivos |
| 9 | `/admin/goals/:uid/:goalId` | Detalle de objetivo |
| 10 | `/admin/missions/templates` | Biblioteca de plantillas de misiones |
| 11 | `/admin/missions/templates/new` | Crear plantilla |
| 12 | `/admin/missions/templates/:id` | Editar plantilla |
| 13 | `/admin/posts` | Tabla de publicaciones con filtro de moderación |
| 14 | `/admin/posts/:id` | Detalle y acciones (ocultar, eliminar, advertir) |
| 15 | `/admin/comments` | Comentarios reportados |
| 16 | `/admin/reports` | Bandeja de moderación (cola priorizada) |
| 17 | `/admin/reports/:id` | Resolución de reporte |
| 18 | `/admin/categories` | CRUD de categorías |
| 19 | `/admin/categories/:id` | Editar categoría |
| 20 | `/admin/analytics` | Retención, embudo de activación, uso por categoría |
| 21 | `/admin/analytics/ai` | Uso y costo de Gemini por feature |
| 22 | `/admin/config` | Reglas de Aura, feature flags, versión mínima |
| 23 | `/admin/audit` | Log de acciones administrativas |
| 24 | `/admin/broadcast` | Envío de notificación masiva (segmentada) |

---

## 4. Lista completa de funcionalidades

### A. Autenticación y cuenta
- A1 Registro con email y contraseña
- A2 Login con email y contraseña
- A3 Login con Google
- A4 Login con Apple *(obligatorio para aprobación en App Store)*
- A5 Verificación de email
- A6 Recuperación de contraseña
- A7 Cierre de sesión
- A8 Sesión persistente con refresco de token
- A9 Edición de perfil (nombre, handle único, foto, bio)
- A10 Cambio de contraseña y de email
- A11 Eliminación de cuenta con borrado real de datos
- A12 Exportación de datos personales (GDPR)
- A13 Suspensión de cuenta gestionada por admin

### B. Objetivos
- B1 Crear objetivo manualmente
- B2 Crear objetivo asistido por IA
- B3 Editar objetivo
- B4 Eliminar objetivo (con cascada)
- B5 Pausar / reanudar
- B6 Completar objetivo con celebración
- B7 Archivar
- B8 Categorización
- B9 Fecha objetivo y horizonte temporal
- B10 Cálculo automático de progreso
- B11 Milestones editables
- B12 Filtro y orden por estado, categoría, progreso y fecha
- B13 Estadísticas por objetivo

### C. Misiones
- C1 Listado del día ("Hoy")
- C2 Listado por objetivo
- C3 Filtros: estado, dificultad, categoría, fecha, objetivo
- C4 Crear misión manual
- C5 Editar misión
- C6 Eliminar misión
- C7 Completar misión
- C8 Saltar misión (con motivo)
- C9 Reordenar (drag & drop)
- C10 Misiones recurrentes (diaria / semanal / días específicos)
- C11 Vencimiento automático
- C12 Dificultad → recompensa de Aura
- C13 Plantillas de misiones por categoría

### D. Evidencias
- D1 Captura con cámara
- D2 Selección desde galería
- D3 Recorte y compresión en cliente
- D4 Descripción de texto
- D5 Fecha de captura automática
- D6 Subida a Storage con progreso
- D7 Cola offline con reintento y backoff
- D8 Visualización en el historial
- D9 Eliminación de evidencia
- D10 Bonus de Aura por adjuntar evidencia

### E. Aura y gamificación
- E1 Puntos por misión según dificultad
- E2 Bonus por evidencia
- E3 Bonus por objetivo completado
- E4 Sistema de niveles con nombres
- E5 Rachas diarias
- E6 Multiplicadores por racha
- E7 Tope diario anti-farmeo
- E8 Ledger auditable
- E9 Logros desbloqueables
- E10 Estadísticas y gráficos
- E11 Ranking opcional (opt-in)
- E12 Animaciones de celebración y háptica

### F. Comunidad
- F1 Feed cronológico paginado
- F2 Pestaña "Siguiendo"
- F3 Filtro por categoría
- F4 Publicar logro (desde misión u objetivo completado)
- F5 Publicar reflexión
- F6 Like / unlike idempotente
- F7 Comentar
- F8 Responder comentario (1 nivel)
- F9 Eliminar contenido propio
- F10 Seguir / dejar de seguir
- F11 Perfil público
- F12 Reportar publicación, comentario o usuario
- F13 Bloquear usuario
- F14 Moderación automática con IA antes de publicar
- F15 Auto-ocultado con 3+ reportes

### G. Inteligencia artificial (Gemini)
- G1 Generar plan completo desde un objetivo
- G2 Generar milestones/subobjetivos
- G3 Generar misiones concretas y accionables
- G4 Mensaje motivacional personalizado
- G5 Sugerencia diaria contextual (según racha y progreso)
- G6 Replanificación al detectar atraso
- G7 Sugerencia de categoría desde el título
- G8 Moderación de contenido
- G9 Cuota diaria por usuario con aviso claro
- G10 Fallback a plantillas ante fallo o timeout
- G11 Salida estructurada validada contra JSON Schema
- G12 Registro de costo y tokens por invocación

### H. Notificaciones (FCM)
- H1 Recordatorio diario a la hora elegida
- H2 Aviso de racha en riesgo
- H3 Aviso de misión próxima a vencer
- H4 Notificación de like, comentario y nuevo seguidor (agrupadas)
- H5 Notificación de subida de nivel
- H6 Notificación de acción de moderación
- H7 Anuncios del equipo (segmentados)
- H8 Bandeja in-app con leído/no leído
- H9 Preferencias granulares por tipo
- H10 Deep link desde la notificación a la pantalla exacta
- H11 Gestión multi-dispositivo de tokens
- H12 Horario de silencio

### I. Resiliencia y UX
- I1 Estados de carga con skeletons
- I2 Estados vacíos con ilustración y llamada a la acción
- I3 Estados de error con causa y reintento
- I4 Banner offline persistente
- I5 Reintento con backoff exponencial
- I6 Sincronización automática al recuperar red
- I7 Actualización forzada por versión mínima
- I8 Modo mantenimiento por feature flag
- I9 Captura global de errores a Crashlytics
- I10 Reemplazo de la pantalla roja de Flutter
- I11 Modo oscuro completo
- I12 i18n español/inglés
- I13 Accesibilidad AA
- I14 Diseño responsive (móvil, tablet, web)

### J. Administración
- J1 Dashboard con KPIs en tiempo real
- J2 CRUD de usuarios
- J3 Asignación de roles
- J4 Suspensión y reactivación de cuentas
- J5 Explorador de objetivos
- J6 CRUD de plantillas de misiones
- J7 Moderación de publicaciones y comentarios
- J8 Bandeja de reportes con flujo de resolución
- J9 CRUD de categorías
- J10 Edición de reglas de Aura sin release
- J11 Feature flags
- J12 Analíticas y exportación CSV
- J13 Monitoreo de costos de IA
- J14 Log de auditoría de acciones administrativas
- J15 Notificaciones masivas segmentadas
