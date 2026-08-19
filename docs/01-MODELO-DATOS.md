# ASCEND — Modelo de Datos, Relaciones, Roles y Seguridad

> Firestore no es SQL. Modelamos por **consulta**, no por normalización.
> Regla de oro aplicada: *"si dos datos se leen juntos, viven juntos"*.

---

## 1. Mapa de colecciones

```
📁 users/{uid}                                   ← perfil (privado, dueño + admin)
   ├─ 📁 goals/{goalId}                          ← objetivos
   ├─ 📁 missions/{missionId}                    ← misiones (PLANAS, ver ADR-005)
   ├─ 📁 auraLedger/{entryId}                    ← libro mayor de Aura (append-only, servidor)
   ├─ 📁 achievements/{achievementId}            ← logros desbloqueados
   ├─ 📁 notifications/{notificationId}          ← bandeja in-app
   ├─ 📁 fcmTokens/{token}                       ← dispositivos registrados
   ├─ 📁 following/{targetUid}                   ← a quién sigue
   ├─ 📁 followers/{followerUid}                 ← quién lo sigue
   └─ 📁 aiUsage/{yyyy-MM-dd}                    ← cuota diaria de IA

📁 publicProfiles/{uid}                          ← proyección pública del perfil
📁 posts/{postId}                                ← feed global
   ├─ 📁 likes/{uid}
   └─ 📁 comments/{commentId}
        └─ 📁 likes/{uid}
📁 reports/{reportId}                            ← moderación
📁 categories/{categoryId}                       ← catálogo (lectura pública)
📁 missionTemplates/{templateId}                 ← biblioteca curada por admin
📁 config/{docId}                                ← app · auraRules · featureFlags
📁 aiJobs/{jobId}                                ← auditoría de uso de Gemini (solo servidor)
📁 adminStats/{yyyy-MM-dd}                       ← agregados diarios (solo servidor)
📁 auditLog/{logId}                              ← acciones administrativas
```

---

## 2. Esquemas

### 2.1 `users/{uid}` — Usuario

```jsonc
{
  "uid": "abc123",
  "email": "santino@example.com",
  "displayName": "Santino",
  "handle": "santino",                    // único, minúsculas, [a-z0-9_] 3-20
  "photoUrl": "https://.../avatar.jpg",
  "bio": "Aprendiendo inglés y corriendo 5k",
  "role": "user",                         // ESPEJO del custom claim — SOLO LECTURA
  "locale": "es",

  "aura": {                               // 🔒 SOLO SERVIDOR
    "total": 1840,
    "level": 7,
    "levelName": "Constante",
    "xpInLevel": 140,
    "xpForNextLevel": 400
  },

  "stats": {                              // 🔒 SOLO SERVIDOR
    "goalsActive": 3,
    "goalsCompleted": 5,
    "missionsCompleted": 128,
    "currentStreak": 12,
    "longestStreak": 31,
    "lastActivityDate": "2026-08-07",     // string YYYY-MM-DD en zona del usuario
    "postsCount": 9,
    "followersCount": 42,
    "followingCount": 37
  },

  "settings": {                           // ✏️ escribible por el dueño
    "themeMode": "system",                // system | light | dark
    "timezone": "America/Argentina/Buenos_Aires",
    "notifications": {
      "dailyReminder": true,
      "reminderTime": "20:00",
      "streakAlerts": true,
      "socialActivity": true,
      "aiSuggestions": true
    },
    "privacy": {
      "profileVisibility": "public",      // public | followers | private
      "autoPublishAchievements": false,
      "showInLeaderboard": true
    }
  },

  "onboarding": { "completed": true, "interests": ["fitness", "languages"] },

  "status": "active",                     // 🔒 active | suspended | deleted
  "suspendedUntil": null,
  "createdAt": "<serverTimestamp>",
  "updatedAt": "<serverTimestamp>",
  "lastLoginAt": "<serverTimestamp>",
  "deletedAt": null
}
```

**Unicidad del handle:** se resuelve con la colección `handles/{handle} → {uid}`, escrita en una transacción junto al perfil. Firestore no tiene índices únicos; esta es la única forma correcta.

---

### 2.2 `publicProfiles/{uid}` — Proyección pública ⚠️ mejora

`users/{uid}` contiene email, ajustes y estadísticas privadas. Si el feed necesitara leerlo para mostrar un autor, tendríamos que abrir permisos de lectura sobre datos sensibles.

**Solución:** una proyección pública mantenida por trigger, con solo lo que se muestra a terceros.

```jsonc
{
  "uid": "abc123",
  "displayName": "Santino",
  "handle": "santino",
  "photoUrl": "...",
  "bio": "...",
  "level": 7,
  "auraTotal": 1840,
  "currentStreak": 12,
  "goalsCompleted": 5,
  "profileVisibility": "public",
  "status": "active",
  "updatedAt": "<serverTimestamp>"
}
```

Lectura: cualquier usuario autenticado. Escritura: solo servidor.

---

### 2.3 `users/{uid}/goals/{goalId}` — Objetivo

```jsonc
{
  "id": "goal_01",
  "ownerId": "abc123",
  "title": "Aprender inglés a nivel conversacional",
  "description": "Poder mantener una charla de 20 minutos",
  "categoryId": "languages",
  "status": "active",                     // draft | active | paused | completed | archived
  "icon": "language",
  "colorHex": "#3B82F6",

  "progress": {                           // 🔒 SOLO SERVIDOR
    "missionsTotal": 24,
    "missionsCompleted": 9,
    "percent": 37.5
  },

  "auraEarned": 450,                      // 🔒
  "difficulty": "medium",
  "startDate": "<timestamp>",
  "targetDate": "<timestamp>",
  "completedAt": null,

  "ai": {
    "generated": true,
    "model": "gemini-2.x",
    "promptVersion": "goal_plan_v3",
    "jobId": "job_998",
    "generatedAt": "<timestamp>"
  },

  "milestones": [                         // subobjetivos generados por IA (embebidos)
    { "id": "m1", "title": "Vocabulario base 500 palabras", "done": true,  "order": 0 },
    { "id": "m2", "title": "Primeras 10 conversaciones",    "done": false, "order": 1 }
  ],

  "createdAt": "<serverTimestamp>",
  "updatedAt": "<serverTimestamp>",
  "deletedAt": null
}
```

**Por qué los milestones van embebidos:** son pocos (3–8), siempre se leen junto al objetivo y nunca se consultan por separado. Una subcolección costaría una lectura extra por cada uno.

---

### 2.4 `users/{uid}/missions/{missionId}` — Misión

```jsonc
{
  "id": "mis_042",
  "ownerId": "abc123",
  "goalId": "goal_01",                    // indexado
  "goalTitle": "Aprender inglés",         // desnormalizado para listas "Hoy"
  "categoryId": "languages",

  "title": "Ver un capítulo en inglés con subtítulos en inglés",
  "description": "20-25 minutos, anotar 5 palabras nuevas",
  "status": "pending",                    // pending | in_progress | completed | skipped | expired
  "difficulty": "easy",                   // easy | medium | hard
  "auraReward": 25,                       // 🔒 calculado por servidor desde config
  "estimatedMinutes": 25,

  "dueDate": "<timestamp>",               // indexado
  "scheduledFor": "2026-08-07",
  "recurrence": { "type": "weekly", "days": ["mon","wed","fri"] },  // o null
  "order": 3,

  "requiresEvidence": true,
  "evidence": {                           // embebida — 1 por misión en MVP
    "photoUrl": "gs://.../evidence/abc123/mis_042.jpg",
    "thumbUrl": "...",
    "note": "Terminé el capítulo 3",
    "capturedAt": "<timestamp>",
    "uploadStatus": "uploaded"            // pending | uploading | uploaded | failed
  },

  "completedAt": null,
  "ai": { "generated": true, "jobId": "job_998" },
  "createdAt": "<serverTimestamp>",
  "updatedAt": "<serverTimestamp>",
  "deletedAt": null
}
```

**Sobre las evidencias:** el usuario pidió "Foto, Descripción, Fecha" — exactamente los tres campos. Embebida en la misión porque es 1:1 y siempre se lee con ella. Si en v2 se permiten varias, migra a `missions/{id}/evidences/{evidenceId}` sin romper el contrato del repositorio.

---

### 2.5 `users/{uid}/auraLedger/{entryId}` — Libro mayor 🔒

Append-only. **Ninguna escritura de cliente.**

```jsonc
{
  "id": "led_9981",
  "amount": 25,                           // positivo o negativo
  "balanceAfter": 1840,
  "reason": "mission_completed",          // mission_completed | goal_completed | streak_bonus
                                          // achievement | daily_login | penalty | admin_adjustment
  "ref": { "type": "mission", "id": "mis_042" },
  "multiplier": 1.5,                      // p.ej. bonus de racha
  "note": "Racha de 12 días ×1.5",
  "createdAt": "<serverTimestamp>",
  "createdBy": "system"                   // system | admin:{uid}
}
```

**Por qué un ledger y no solo un total:** trazabilidad, gráficos de evolución, y capacidad de **recalcular el saldo desde cero** si se detecta un exploit. Es contabilidad, y la contabilidad se lleva por asientos.

---

### 2.6 `posts/{postId}` — Publicación

```jsonc
{
  "id": "post_555",
  "authorId": "abc123",
  "author": {                             // 🔒 desnormalizado por trigger
    "displayName": "Santino",
    "handle": "santino",
    "photoUrl": "...",
    "level": 7
  },

  "type": "mission_completed",            // mission_completed | goal_completed | milestone | reflection
  "text": "Primera semana completa de inglés diario 🔥",
  "mediaUrl": "https://.../posts/post_555.jpg",
  "thumbUrl": "...",
  "aspectRatio": 1.33,

  "source": {                             // NUNCA expone datos privados: solo títulos
    "goalId": "goal_01",
    "goalTitle": "Aprender inglés",
    "missionId": "mis_042",
    "missionTitle": "Ver un capítulo en inglés",
    "auraEarned": 25
  },

  "categoryId": "languages",
  "visibility": "public",                 // public | followers

  "counters": {                           // 🔒 SOLO SERVIDOR
    "likes": 34, "comments": 5, "reports": 0
  },

  "moderation": {                         // 🔒 SOLO SERVIDOR
    "status": "visible",                  // visible | under_review | hidden | removed
    "aiScore": 0.02,
    "reviewedBy": null,
    "reviewedAt": null,
    "reason": null
  },

  "createdAt": "<serverTimestamp>",       // indexado desc
  "updatedAt": "<serverTimestamp>",
  "deletedAt": null
}
```

**Regla de producto codificada en el modelo:** un post **debe** referenciar un logro real (`source` obligatorio para `mission_completed` y `goal_completed`). Esto materializa la premisa "el feed solo muestra logros reales" a nivel de datos y de reglas de seguridad, no solo de UI.

---

### 2.7 `posts/{postId}/likes/{uid}` — Like

```jsonc
{ "uid": "xyz789", "createdAt": "<serverTimestamp>" }
```

**El ID del documento ES el uid.** Consecuencias: idempotencia gratis (no se puede dar like dos veces), regla de seguridad de una línea (`request.auth.uid == uid`), y saber si yo di like cuesta una lectura por ID en vez de un query.

---

### 2.8 `posts/{postId}/comments/{commentId}` — Comentario

```jsonc
{
  "id": "cmt_77",
  "postId": "post_555",
  "authorId": "xyz789",
  "author": { "displayName": "Ana", "handle": "ana", "photoUrl": "...", "level": 4 },
  "text": "¡Grande! ¿Qué serie estás viendo?",
  "parentId": null,                       // 1 nivel de respuestas
  "counters": { "likes": 2, "reports": 0 },
  "moderation": { "status": "visible", "aiScore": 0.01 },
  "createdAt": "<serverTimestamp>",
  "deletedAt": null
}
```

---

### 2.9 `reports/{reportId}` — Reporte

```jsonc
{
  "id": "rep_12",
  "reporterId": "xyz789",
  "target": { "type": "post", "id": "post_555", "ownerId": "abc123" },
  "reason": "spam",                       // spam | harassment | nsfw | fake_achievement | violence | other
  "details": "Publicación repetida 5 veces",
  "status": "open",                       // open | reviewing | resolved | dismissed
  "resolution": null,                     // content_removed | user_warned | user_suspended | no_action
  "handledBy": null,
  "handledAt": null,
  "createdAt": "<serverTimestamp>"
}
```

Permisos: el usuario **crea** (uno por target, ID determinístico `{targetId}_{reporterId}` para evitar spam de reportes). Solo el admin lee y actualiza.

---

### 2.10 `categories/{categoryId}` — Categoría

```jsonc
{
  "id": "languages",
  "name": { "es": "Idiomas", "en": "Languages" },
  "description": { "es": "Aprender un nuevo idioma", "en": "Learn a new language" },
  "icon": "translate",
  "colorHex": "#3B82F6",
  "order": 2,
  "active": true,
  "goalsCount": 1284,                     // 🔒 estadística
  "createdAt": "<serverTimestamp>"
}
```

Semilla inicial: `fitness`, `languages`, `business`, `reading`, `finance`, `travel`, `mindfulness`, `skills`, `creativity`, `relationships`.

---

### 2.11 `users/{uid}/notifications/{notificationId}` — Notificación

```jsonc
{
  "id": "not_31",
  "type": "mission_reminder",             // mission_reminder | streak_warning | aura_gained
                                          // level_up | new_like | new_comment | new_follower
                                          // ai_suggestion | moderation_action | system
  "title": "Te queda 1 misión para hoy",
  "body": "Completala y mantené tu racha de 12 días 🔥",
  "data": { "route": "/missions/mis_042" },
  "imageUrl": null,
  "read": false,
  "createdAt": "<serverTimestamp>",
  "expiresAt": "<timestamp>"              // TTL de Firestore → borrado automático
}
```

Se usa la **política TTL nativa de Firestore** sobre `expiresAt` para purgar notificaciones viejas sin costo de escritura.

---

### 2.12 `config/auraRules` — Reglas de gamificación (editable sin release)

```jsonc
{
  "rewards": {
    "mission": { "easy": 10, "medium": 25, "hard": 50 },
    "goalCompleted": 200,
    "milestone": 50,
    "dailyLogin": 5,
    "evidenceBonus": 5
  },
  "streakMultipliers": [
    { "minDays": 3,  "multiplier": 1.1 },
    { "minDays": 7,  "multiplier": 1.25 },
    { "minDays": 14, "multiplier": 1.5 },
    { "minDays": 30, "multiplier": 2.0 }
  ],
  "levels": [
    { "level": 1,  "name": "Iniciado",   "minAura": 0 },
    { "level": 2,  "name": "Aprendiz",   "minAura": 100 },
    { "level": 3,  "name": "Disciplinado","minAura": 300 },
    { "level": 5,  "name": "Enfocado",   "minAura": 900 },
    { "level": 7,  "name": "Constante",  "minAura": 1700 },
    { "level": 10, "name": "Imparable",  "minAura": 4000 },
    { "level": 15, "name": "Ascendido",  "minAura": 12000 }
  ],
  "dailyCaps": { "maxAuraPerDay": 500, "maxMissionsPerDay": 20 }
}
```

**El tope diario existe para prevenir farmeo**: crear 200 misiones triviales y completarlas no debe darte el nivel máximo.

---

### 2.13 `aiJobs/{jobId}` — Auditoría de IA 🔒

```jsonc
{
  "uid": "abc123",
  "type": "goal_plan",                    // goal_plan | mission_suggestions | motivation | moderation
  "model": "gemini-2.x",
  "promptVersion": "goal_plan_v3",
  "input": { "goalTitle": "...", "categoryId": "...", "horizonDays": 90 },
  "status": "success",                    // success | failed | rate_limited | invalid_output
  "tokensIn": 420, "tokensOut": 1180,
  "estimatedCostUsd": 0.0021,
  "latencyMs": 3400,
  "error": null,
  "createdAt": "<serverTimestamp>"
}
```

Esto permite responder, en la reunión con inversores, **exactamente cuánto cuesta la IA por usuario activo**.

---

## 3. Relaciones entre colecciones

```
                            ┌──────────────────┐
                            │   categories     │  (catálogo global, lectura pública)
                            └────────┬─────────┘
                                     │ categoryId (referencia lógica)
        ┌────────────────────────────┼────────────────────────────┐
        │                            │                            │
┌───────▼────────┐          ┌────────▼────────┐          ┌────────▼────────┐
│  users/{uid}   │  1───N   │      goals      │  1───N   │    missions     │
│   (perfil)     ├─────────►│  (subcolección) │◄─────────┤  (subcol. plana │
└───┬────────┬───┘          └────────┬────────┘  goalId  │   con goalId)   │
    │        │                       │                    └────────┬────────┘
    │        │                       │ genera post                 │ genera post
    │        │                       └────────────┬────────────────┘
    │        │                                    │
    │        │ 1───N                     ┌────────▼────────┐
    │        └──────────────────────────►│   posts (global)│
    │          auraLedger                │  author{} desnorm│
    │          notifications             └───┬──────────┬───┘
    │          achievements                  │ 1───N    │ 1───N
    │          fcmTokens                ┌────▼────┐ ┌───▼─────┐
    │          following / followers    │  likes  │ │comments │
    │                                   │ (id=uid)│ └───┬─────┘
    │                                   └─────────┘     │
    │ 1───1 (proyección por trigger)                    │
┌───▼──────────────┐                              ┌─────▼──────┐
│ publicProfiles   │◄─────────────────────────────┤  reports   │
│  (lectura auth)  │        target.ownerId        │  (admin)   │
└──────────────────┘                              └────────────┘
```

### Reglas de integridad (implementadas en Cloud Functions)

| Evento | Efecto en cascada |
|--------|-------------------|
| `mission.status → completed` | +Aura al ledger, actualiza `users.aura`, recalcula `goal.progress`, actualiza racha, evalúa logros, opcionalmente crea post |
| `goal.status → completed` | +200 Aura, `stats.goalsCompleted++`, logro, notificación de celebración |
| Borrado de `goal` | `bulkWriter` borra sus misiones y las evidencias en Storage |
| Escritura en `users` (nombre/foto/nivel) | Actualiza `publicProfiles` y propaga a los últimos N posts del autor |
| Alta/baja en `posts/{id}/likes` | `posts.counters.likes ±1` + notificación al autor (agrupada) |
| Alta en `comments` | `posts.counters.comments++` + notificación |
| Alta en `reports` | `counters.reports++`; si `reports ≥ 3` → `moderation.status = under_review` (auto-ocultado preventivo) |
| Baja de cuenta | Borra Auth, subcolecciones, archivos; anonimiza posts/comentarios a "Usuario eliminado" |

---

## 4. Índices compuestos requeridos

| Colección | Campos | Consulta que lo necesita |
|-----------|--------|--------------------------|
| `missions` | `status ASC, dueDate ASC` | Misiones de hoy |
| `missions` | `goalId ASC, order ASC` | Misiones de un objetivo |
| `missions` | `status ASC, completedAt DESC` | Historial |
| `goals` | `status ASC, updatedAt DESC` | Lista de objetivos activos |
| `goals` | `categoryId ASC, status ASC` | Filtro por categoría |
| `posts` | `moderation.status ASC, createdAt DESC` | Feed principal |
| `posts` | `moderation.status ASC, categoryId ASC, createdAt DESC` | Feed por categoría |
| `posts` | `authorId ASC, createdAt DESC` | Perfil de usuario |
| `posts` | `moderation.status ASC, counters.likes DESC, createdAt DESC` | Destacados |
| `comments` | `moderation.status ASC, createdAt ASC` | Hilo de comentarios |
| `reports` | `status ASC, createdAt DESC` | Bandeja de moderación |
| `auraLedger` | `createdAt DESC` | Historial de Aura |
| `notifications` | `read ASC, createdAt DESC` | Bandeja in-app |
| `users` (admin) | `status ASC, createdAt DESC` | Tabla de usuarios |

Todos se declaran en `firestore.indexes.json` y se despliegan con `firebase deploy --only firestore:indexes`.

---

## 5. Roles y permisos

### 5.1 Definición

| Rol | Claim | Quién lo obtiene | Alcance |
|-----|-------|------------------|---------|
| **user** | `role: "user"` | Todos al registrarse (asignado por `onUserCreate`) | Sus propios datos + lectura del contenido público |
| **admin** | `role: "admin"` | Asignado manualmente por otro admin vía Function | Lectura total, moderación, CRUD de catálogos, configuración |

> **Nota de escalabilidad:** el sistema de claims soporta añadir `moderator` (moderación sin acceso a datos de usuarios ni configuración) sin tocar el modelo. Se documenta como extensión de Fase 8, no del MVP.

### 5.2 Matriz de permisos

| Recurso | Anónimo | Usuario (propio) | Usuario (ajeno) | Admin |
|---------|:-------:|:----------------:|:---------------:|:-----:|
| `users/{uid}` | — | Leer / Editar campos permitidos | — | Leer / Editar estado |
| `users.aura` · `stats` · `role` | — | Leer | — | Leer (ajuste solo vía Function) |
| `publicProfiles/{uid}` | — | Leer | Leer | Leer |
| `goals` · `missions` | — | CRUD completo | — | Leer |
| `auraLedger` | — | Leer | — | Leer |
| `posts` | — | Crear / Editar texto / Borrar el propio | Leer | Leer / Ocultar / Borrar |
| `posts/{id}/likes/{uid}` | — | Crear / Borrar el propio | Leer | Leer |
| `comments` | — | Crear / Borrar el propio | Leer | Leer / Ocultar / Borrar |
| `reports` | — | Crear | — | Leer / Resolver |
| `categories` | — | Leer | Leer | CRUD |
| `missionTemplates` | — | Leer | Leer | CRUD |
| `config/*` | — | Leer | Leer | Editar |
| `aiJobs` · `adminStats` · `auditLog` | — | — | — | Leer |

---

## 6. Reglas de seguridad — estructura

> Se entregan completas en Fase 0 junto con su **suite de tests** (`@firebase/rules-unit-testing`). Aquí queda fijado el diseño.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ───── Helpers ─────
    function isSignedIn()       { return request.auth != null; }
    function isOwner(uid)       { return isSignedIn() && request.auth.uid == uid; }
    function isAdmin()          { return isSignedIn() && request.auth.token.role == 'admin'; }
    function isActive()         { return request.auth.token.status != 'suspended'; }
    function unchanged(field)   { return !(field in request.resource.data) ||
                                        request.resource.data[field] == resource.data[field]; }
    function onlyFields(allowed){ return request.resource.data.diff(resource.data)
                                        .affectedKeys().hasOnly(allowed); }

    // ───── DENEGAR TODO POR DEFECTO ─────
    match /{document=**} { allow read, write: if false; }

    // ───── Usuario ─────
    match /users/{uid} {
      allow get         : if isOwner(uid) || isAdmin();
      allow list        : if isAdmin();
      allow create      : if isOwner(uid)
                          && request.resource.data.role == 'user'
                          && !('aura' in request.resource.data)
                          && !('stats' in request.resource.data);
      // El dueño SOLO puede tocar campos de presentación y ajustes.
      allow update      : if isOwner(uid)
                          && onlyFields(['displayName','bio','photoUrl','settings',
                                         'locale','onboarding','updatedAt']);
      allow delete      : if false;       // baja de cuenta solo vía Cloud Function

      match /goals/{goalId} {
        allow read      : if isOwner(uid) || isAdmin();
        allow create    : if isOwner(uid) && isActive()
                          && request.resource.data.ownerId == uid
                          && !('progress' in request.resource.data)
                          && !('auraEarned' in request.resource.data);
        allow update    : if isOwner(uid) && unchanged('progress') && unchanged('auraEarned');
        allow delete    : if isOwner(uid);
      }

      match /missions/{missionId} {
        allow read      : if isOwner(uid) || isAdmin();
        allow create    : if isOwner(uid) && isActive()
                          && !('auraReward' in request.resource.data);   // lo pone el servidor
        // El cliente puede cambiar estado y evidencia; jamás la recompensa.
        allow update    : if isOwner(uid) && unchanged('auraReward') && unchanged('ownerId');
        allow delete    : if isOwner(uid);
      }

      match /auraLedger/{entryId}   { allow read: if isOwner(uid) || isAdmin();
                                      allow write: if false; }        // 🔒 solo Admin SDK
      match /achievements/{id}      { allow read: if isOwner(uid) || isAdmin();
                                      allow write: if false; }
      match /notifications/{id}     { allow read: if isOwner(uid);
                                      allow update: if isOwner(uid) && onlyFields(['read']);
                                      allow create, delete: if false; }
      match /fcmTokens/{token}      { allow read, write: if isOwner(uid); }
      match /aiUsage/{day}          { allow read: if isOwner(uid); allow write: if false; }
      match /following/{targetUid}  { allow read: if isSignedIn();
                                      allow write: if isOwner(uid); }
      match /followers/{followerUid}{ allow read: if isSignedIn(); allow write: if false; }
    }

    // ───── Perfil público ─────
    match /publicProfiles/{uid} {
      allow read  : if isSignedIn();
      allow write : if false;             // 🔒 proyección mantenida por trigger
    }

    // ───── Feed ─────
    match /posts/{postId} {
      allow read   : if isSignedIn()
                     && (resource.data.moderation.status == 'visible'
                         || resource.data.authorId == request.auth.uid
                         || isAdmin());
      allow create : if isSignedIn() && isActive()
                     && request.resource.data.authorId == request.auth.uid
                     && !('counters'   in request.resource.data)
                     && !('moderation' in request.resource.data)
                     && !('author'     in request.resource.data)      // lo pone el trigger
                     && request.resource.data.text.size() <= 500
                     // regla de producto: los logros deben referenciar algo real
                     && (request.resource.data.type == 'reflection'
                         || 'source' in request.resource.data);
      allow update : if (isOwner(resource.data.authorId)
                         && onlyFields(['text','updatedAt']))
                     || isAdmin();
      allow delete : if isOwner(resource.data.authorId) || isAdmin();

      match /likes/{likeUid} {
        allow read   : if isSignedIn();
        allow create : if isOwner(likeUid) && isActive();
        allow delete : if isOwner(likeUid);
        allow update : if false;
      }

      match /comments/{commentId} {
        allow read   : if isSignedIn();
        allow create : if isSignedIn() && isActive()
                       && request.resource.data.authorId == request.auth.uid
                       && request.resource.data.text.size() <= 300
                       && !('counters' in request.resource.data)
                       && !('moderation' in request.resource.data);
        allow update : if isAdmin();
        allow delete : if isOwner(resource.data.authorId) || isAdmin();
      }
    }

    // ───── Moderación ─────
    match /reports/{reportId} {
      allow create : if isSignedIn()
                     && request.resource.data.reporterId == request.auth.uid
                     && request.resource.data.status == 'open';
      allow read, update : if isAdmin();
      allow delete : if false;
    }

    // ───── Catálogos ─────
    match /categories/{id}        { allow read: if isSignedIn(); allow write: if isAdmin(); }
    match /missionTemplates/{id}  { allow read: if isSignedIn(); allow write: if isAdmin(); }
    match /config/{id}            { allow read: if isSignedIn(); allow write: if isAdmin(); }
    match /handles/{handle}       { allow read: if isSignedIn(); allow write: if false; }

    // ───── Solo servidor / admin ─────
    match /aiJobs/{id}      { allow read: if isAdmin(); allow write: if false; }
    match /adminStats/{id}  { allow read: if isAdmin(); allow write: if false; }
    match /auditLog/{id}    { allow read: if isAdmin(); allow write: if false; }
  }
}
```

### 6.1 Reglas de Storage

```javascript
service firebase.storage {
  match /b/{bucket}/o {
    function isOwner(uid) { return request.auth != null && request.auth.uid == uid; }
    function isImage()    { return request.resource.contentType.matches('image/.*'); }
    function maxSize(mb)  { return request.resource.size < mb * 1024 * 1024; }

    match /{allPaths=**} { allow read, write: if false; }

    match /avatars/{uid}/{file} {
      allow read  : if request.auth != null;
      allow write : if isOwner(uid) && isImage() && maxSize(5);
    }
    match /evidence/{uid}/{file} {
      allow read  : if isOwner(uid) || request.auth.token.role == 'admin';
      allow write : if isOwner(uid) && isImage() && maxSize(10);
    }
    match /posts/{uid}/{file} {
      allow read  : if request.auth != null;
      allow write : if isOwner(uid) && isImage() && maxSize(10);
    }
    match /public/{file} { allow read: if true; allow write: if false; }
  }
}
```

**Nota importante:** las evidencias son **privadas por defecto** (solo el dueño). Cuando el usuario decide publicar un logro, la Function copia la imagen a `posts/{uid}/` — lo privado nunca se vuelve público por accidente.

---

## 7. Cloud Functions previstas

### Triggers de Firestore
| Función | Disparador | Responsabilidad |
|---------|-----------|-----------------|
| `onUserCreate` | Auth create | Crea `users/{uid}`, `publicProfiles/{uid}`, asigna claim `user`, reserva handle |
| `onUserUpdate` | `users/{uid}` update | Sincroniza `publicProfiles`, propaga a posts recientes |
| `onMissionWrite` | `missions/{id}` update | Otorga Aura, escribe ledger, actualiza progreso, racha y logros |
| `onGoalWrite` | `goals/{id}` write | Recalcula progreso, gestiona finalización |
| `onGoalDelete` | `goals/{id}` delete | Cascada: misiones + evidencias en Storage |
| `onPostWrite` | `posts/{id}` create | Moderación IA, thumbnail, `stats.postsCount` |
| `onLikeWrite` | `likes/{uid}` write | Contador + notificación agrupada |
| `onCommentWrite` | `comments/{id}` write | Contador + notificación + moderación |
| `onReportCreate` | `reports/{id}` create | Contador, auto-ocultado con ≥3 reportes, alerta al admin |

### Callables (`onCall` + App Check)
`generateGoalPlan` · `suggestMissions` · `getMotivation` · `setUserRole` · `moderateContent` · `deleteAccount` · `exportUserData` · `publishAchievement`

### Programadas (Cloud Scheduler)
| Función | Frecuencia | Responsabilidad |
|---------|-----------|-----------------|
| `dailyReminders` | cada hora | Envía push a usuarios cuya hora local coincide con su `reminderTime` |
| `streakChecker` | 00:05 por zona | Rompe rachas inactivas, avisa antes de perderlas |
| `expireMissions` | diaria | Marca misiones vencidas |
| `aggregateStats` | diaria | Escribe `adminStats/{fecha}` para el dashboard |
| `costReport` | semanal | Resumen de costos de Gemini/Firebase al equipo |

**Nota sobre recordatorios y zonas horarias:** ejecutar cada hora y filtrar por `settings.timezone` + `reminderTime` es más simple y barato que programar una tarea por usuario, y funciona correctamente en todo el mundo.
