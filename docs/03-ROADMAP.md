# ASCEND — Roadmap de Desarrollo

> 10 fases. **No se avanza a la siguiente sin tu aprobación explícita.**
> Cada fase tiene entregables verificables y criterios de aceptación cerrados.

---

## Resumen

| Fase | Nombre | Entregable central | Duración est. |
|------|--------|--------------------|---------------|
| 0 | Fundaciones | Monorepo compilando, DS, tema, Firebase, CI | 3–5 días |
| 1 | Autenticación y perfil | Ciclo de vida completo de la cuenta | 4–6 días |
| 2 | Objetivos y misiones | Núcleo funcional del producto | 6–8 días |
| 3 | Evidencias y Storage | Foto + offline + cola de subida | 3–4 días |
| 4 | Aura y gamificación | Motor de puntos servidor-autoritativo | 4–5 días |
| 5 | IA (Gemini) | Wizard de plan con IA + fallback | 5–7 días |
| 6 | Comunidad | Feed, likes, comentarios, reportes | 6–8 días |
| 7 | Notificaciones (FCM) | Recordatorios y push social | 3–4 días |
| 8 | Panel Admin | Dashboard, CRUDs, moderación | 7–9 días |
| 9 | Hardening y lanzamiento | Tests, performance, tiendas | 5–7 días |

**Total estimado: 46–63 días de trabajo efectivo.**
Orden pensado para que exista una app **usable de punta a punta al final de la Fase 4** — el resto suma valor sobre una base que ya funciona.

---

## FASE 0 — Fundaciones

**Objetivo:** que un desarrollador nuevo clone, ejecute un comando y tenga la app corriendo contra Firebase de desarrollo.

**Entregables**
1. Monorepo Melos con los 6 paquetes creados y compilando (`ascend_core`, `ascend_domain`, `ascend_data`, `ascend_ui`, `ascend_l10n` + 2 apps).
2. `analysis_options.yaml` estricto compartido (`very_good_analysis` + reglas propias de dependencia entre capas).
3. Proyectos Firebase **dev** / **stg** / **prod** con `flavors` y `firebase_options` por entorno.
4. Design System: tokens de color validados por contraste, tema claro/oscuro, tipografía Poppins, escala de espaciado, componentes atómicos.
5. `AsyncStateBuilder`, `ErrorStateView`, `EmptyStateView`, `OfflineBanner`, `AscendSkeleton`.
6. `Result<T>`, `Failure` sellado y `ErrorMapper` con la tabla completa de códigos de Firebase.
7. `bootstrap.dart` con `runZonedGuarded`, `FlutterError.onError`, `ErrorWidget.builder` y Crashlytics.
8. GoRouter con shell, guards y rutas placeholder de todas las pantallas.
9. `firestore.rules` completas + suite de tests con el emulador.
10. `backend/functions` inicializado en TypeScript con linter y despliegue funcionando.
11. GitHub Actions: análisis, tests, build Android/iOS/Web en cada PR.
12. Widgetbook con el catálogo de componentes.

**Criterios de aceptación**
- `melos bootstrap && melos run analyze && melos run test` en verde.
- La app arranca en Android, iOS y Web con pantallas vacías navegables.
- Un `throw` provocado a propósito muestra la pantalla de error de Ascend, **nunca la roja de Flutter**.
- Los tests de reglas de Firestore pasan contra el emulador.

---

## FASE 1 — Autenticación y perfil

**Entregables**
- `AuthRepository` + casos de uso: registro, login, Google, Apple, logout, reset, verificación, cambio de email/contraseña, baja de cuenta.
- Pantallas 3–9 y 45–46 (onboarding, login, registro, recuperación, verificación, perfil, edición).
- Validación de handle único en transacción con la colección `handles`.
- Subida de avatar con recorte y compresión.
- Function `onUserCreate`: crea perfil, perfil público, asigna claim `user`.
- Function `deleteAccount`: borrado real y anonimización.
- Guards de router: sesión, onboarding, email verificado, cuenta suspendida.
- Onboarding de 4 pasos con selección de intereses.

**Criterios de aceptación**
- Ciclo completo registro → verificación → login → editar → logout → recuperar → borrar cuenta.
- Handle duplicado rechazado tanto en cliente como en servidor.
- Sesión persiste tras cerrar la app; token se refresca solo.
- Sin conexión, la pantalla de login informa el estado en vez de fallar.
- Tests: 90% de cobertura en casos de uso de auth.

---

## FASE 2 — Objetivos y misiones

**Entregables**
- `GoalRepository` y `MissionRepository` con todos los casos de uso.
- Pantallas 10–12, 15–16, 19–30 (Hoy, objetivos, detalle, edición, misiones, historial).
- CRUD completo de objetivos con cascada al borrar.
- CRUD completo de misiones, filtros, orden, recurrencia, reordenamiento drag & drop.
- Categorías cargadas desde Firestore con caché local.
- Function `onGoalWrite` / `onMissionWrite` para progreso.
- Function `expireMissions` programada.
- Persistencia offline verificada.

**Criterios de aceptación**
- Crear objetivo → agregar misiones → completar → el progreso se actualiza solo.
- Borrar un objetivo elimina sus misiones (verificado en el emulador).
- La pantalla "Hoy" resuelve en **una sola query**.
- En modo avión: crear y completar misiones funciona y sincroniza al volver la red.
- Todos los listados tienen estado vacío, de carga y de error.

---

## FASE 3 — Evidencias y Storage

**Entregables**
- Captura con cámara y galería, recorte, compresión (máx 1080px, JPEG q80).
- Subida con barra de progreso real y cancelación.
- Outbox en Hive: cola persistente con reintento y backoff exponencial.
- Function generadora de thumbnails.
- Reglas de Storage con validación de tipo y tamaño.
- Historial de evidencias con visor.

**Criterios de aceptación**
- Foto tomada sin conexión: la misión se completa y la imagen sube sola al recuperar red.
- Cerrar la app durante una subida no pierde la evidencia.
- Un archivo de 15MB es rechazado con un mensaje claro, no con un crash.
- Un usuario no puede leer la evidencia de otro (test de reglas).

---

## FASE 4 — Aura y gamificación

**Entregables**
- `auraService` en Cloud Functions: transacción atómica ledger + saldo.
- Cálculo de rachas con zona horaria del usuario (`streakChecker`).
- Multiplicadores, topes diarios, logros.
- Pantallas 31–35 (Aura, historial, estadísticas, logros, ranking).
- Animaciones de celebración con háptica.
- `config/auraRules` editable.

**Criterios de aceptación**
- Un intento de escribir `users/{uid}.aura` desde el cliente es **rechazado** (test de reglas).
- Completar la misma misión dos veces otorga Aura **una sola vez** (idempotencia).
- El saldo recalculado desde el ledger coincide siempre con `users.aura`.
- La racha se rompe correctamente cruzando zonas horarias.
- El tope diario impide farmear.

> **Al terminar esta fase la app ya es un producto usable de punta a punta.** Buen momento para una beta cerrada.

---

## FASE 5 — Inteligencia artificial (Gemini)

**Entregables**
- Functions `generateGoalPlan`, `suggestMissions`, `getMotivation` con App Check.
- Prompts versionados en `functions/src/config/prompts/`.
- Structured output con JSON Schema y validación estricta de la respuesta.
- Cuota diaria por usuario (`users/{uid}/aiUsage/{fecha}`).
- Registro de tokens y costo en `aiJobs`.
- Wizard completo (pantallas 16–18) con revisión editable obligatoria.
- Biblioteca de plantillas por categoría como fallback.
- Sugerencia diaria contextual.

**Criterios de aceptación**
- La API key **no aparece en ningún artefacto de cliente** (verificado descompilando el APK).
- Con Gemini caído, el wizard ofrece plantillas y el usuario termina su objetivo igual.
- Un JSON malformado del modelo no rompe nada: se reintenta una vez y luego cae al fallback.
- Superada la cuota, el mensaje es claro y ofrece el camino manual.
- El costo por generación queda registrado y es consultable.

---

## FASE 6 — Comunidad

**Entregables**
- `PostRepository`, `CommentRepository`, `ReportRepository`.
- Pantallas 36–44.
- Feed paginado con cursores e infinite scroll.
- Likes idempotentes (doc id = uid) con contador por trigger.
- Comentarios con un nivel de respuestas.
- Seguir / dejar de seguir con contadores.
- Reportes con auto-ocultado a partir de 3.
- Moderación IA previa a la publicación.
- Bloqueo de usuarios.
- Publicación desde un logro con vista previa.

**Criterios de aceptación**
- Cargar el feed cuesta **≤ 21 lecturas** por página de 20 posts (autor desnormalizado, sin N+1).
- Doble tap rápido en like no descuadra el contador.
- Contenido ofensivo es marcado antes de aparecer en el feed.
- Un post reportado 3 veces desaparece del feed automáticamente.
- Un usuario bloqueado no aparece en tu feed.

---

## FASE 7 — Notificaciones (FCM)

**Entregables**
- Registro de tokens multi-dispositivo con limpieza de tokens muertos.
- Permisos con explicación previa (pre-permission prompt).
- `dailyReminders` por zona horaria, `streakChecker` con aviso previo.
- Notificaciones sociales agrupadas (evitar spam).
- Deep links desde push a la pantalla exacta.
- Bandeja in-app con TTL.
- Preferencias granulares y horario de silencio.
- Manejo en foreground, background y app cerrada.

**Criterios de aceptación**
- El recordatorio llega a la hora local correcta en 3 zonas horarias distintas.
- Tocar una push abre exactamente la misión correspondiente, incluso con la app cerrada.
- Desactivar un tipo de notificación en ajustes lo detiene de verdad.
- 50 likes seguidos generan **una** notificación agrupada, no 50.

---

## FASE 8 — Panel de administración

**Entregables**
- App `ascend_admin` con shell responsive y guard de rol.
- 24 pantallas de §3.2.
- Tablas con búsqueda, filtros, orden, paginación y exportación CSV.
- Bandeja de moderación priorizada.
- Function `setUserRole` protegida + log de auditoría.
- `aggregateStats` diaria y dashboard de KPIs.
- Panel de costos de IA.
- Editor de reglas de Aura y feature flags.
- Notificaciones masivas segmentadas.

**Criterios de aceptación**
- Un usuario sin claim `admin` no puede entrar **ni leer datos** aunque manipule el cliente (test de reglas).
- Toda acción administrativa queda registrada en `auditLog`.
- El dashboard carga en < 3s con datos agregados, no recorriendo colecciones.
- El panel es usable en 1280px y en tablet.

---

## FASE 9 — Hardening y lanzamiento

**Entregables**
- Cobertura: ≥90% domain, ≥70% data, tests de widget en componentes del DS.
- Tests E2E con Patrol de los 5 flujos críticos.
- Auditoría de performance: arranque < 2s, jank < 1%, APK < 40MB.
- Auditoría de seguridad: revisión completa de reglas, App Check en producción, rotación de secretos.
- Alertas de presupuesto en Firebase y umbrales de costo.
- i18n completo es/en revisado.
- Accesibilidad AA verificada con TalkBack y VoiceOver.
- Política de privacidad, términos y formularios de datos de las tiendas.
- Assets de tienda, capturas, textos ASO.
- Firma, App Bundle, TestFlight y despliegue del admin en Firebase Hosting.
- Runbook de incidentes y guía de contribución.

**Criterios de aceptación**
- Build de release en verde para Android, iOS y Web.
- Cero errores no manejados en 72h de beta.
- Crash-free users > 99.5%.
- Aprobación en ambas tiendas.

---

## Post-MVP (backlog priorizado)

| Prioridad | Funcionalidad |
|-----------|---------------|
| Alta | Fan-out del feed (ADR-006) cuando se supere el umbral |
| Alta | Grupos y desafíos entre amigos |
| Alta | Widgets de pantalla de inicio (iOS/Android) |
| Media | Integración con Google Fit / Apple Health para objetivos de fitness |
| Media | Suscripción premium (IA ilimitada, estadísticas avanzadas) |
| Media | Mentores y comunidades por categoría |
| Baja | Web app pública para usuarios finales |
| Baja | Exportación de progreso a PDF |
