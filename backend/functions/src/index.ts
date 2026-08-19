/**
 * Punto de entrada de las Cloud Functions de Ascend.
 *
 * Estructura (se completa a lo largo del roadmap):
 *
 *   triggers/    reaccionan a cambios en Firestore o en Auth
 *   callable/    las invoca el cliente con onCall + App Check
 *   scheduled/   corren por reloj vía Cloud Scheduler
 *   services/    lógica de negocio reutilizable, sin acoplar al disparador
 *
 * Responsabilidades críticas que viven acá y NO en el cliente:
 *
 *   · Otorgar Aura (ADR-003). Si el cliente pudiera escribirla, el ranking
 *     sería ficción.
 *   · Llamar a Gemini (ADR-002). La API key nunca puede viajar en el binario.
 *   · Asignar roles (ADR-004). El custom claim solo lo escribe el servidor.
 *   · Mantener contadores y proyecciones desnormalizadas.
 *
 * Cada función se exporta por nombre para que `firebase deploy --only
 * functions:nombre` funcione y no haya que redesplegar todo por un cambio.
 */

import { initializeApp } from 'firebase-admin/app';

initializeApp();

// ── Fase 1 — Ciclo de vida de la cuenta ──────────────────────────────────
// `registerProfile` reemplaza al `onUserCreate` que preveía el diseño: un
// trigger de Auth no recibe el handle elegido —Auth solo conoce email y
// displayName— y sin handle no hay transacción de unicidad posible.
export { registerProfile } from './callable/register-profile';
export { onUserUpdate } from './triggers/on-user-update';
export { deleteAccount } from './callable/delete-account';
// `setUserRole` estaba planificada para la Fase 8, pero sin ella no existe
// forma de crear un administrador: se adelanta con aprobación explícita.
export { setUserRole } from './callable/set-user-role';
// export { exportUserData } from './callable/export-user-data';

// ── Fase 2 — Objetivos y misiones ────────────────────────────────────────
// `onGoalDelete` se implementa junto con los objetivos, aunque las misiones
// lleguen en la Fase 2B: las reglas ya permiten borrar un objetivo, así que sin
// la cascada cada borrado dejaría misiones huérfanas apuntando a un goalId
// inexistente en cuanto exista la primera misión.
export { onGoalDelete } from './triggers/on-goal-delete';
// export { onGoalWrite } from './triggers/on-goal-write';
// export { expireMissions } from './scheduled/expire-missions';

// ── Fase 3 — Evidencias ──────────────────────────────────────────────────
// export { onEvidenceUploaded } from './triggers/on-evidence-uploaded';

// ── Fase 4 — Aura y gamificación ─────────────────────────────────────────
// El cliente solo escribe `mission.status`; toda la recompensa se calcula acá.
export { onMissionWrite } from './triggers/on-mission-write';
export { streakChecker } from './scheduled/streak-checker';

// ── Fase 5 — Comunidad ───────────────────────────────────────────────────
// Contadores, autor desnormalizado y auto-ocultado: todo lo que las reglas le
// prohíben escribir al cliente lo mantienen estos triggers.
export {
  onPostCreate,
  onPostDelete,
  onLikeWrite,
  onCommentWrite,
  onReportCreate,
} from './triggers/community';
// export { moderateContent } from './callable/moderate-content';

// ── Fase 6 — Inteligencia artificial (ADR-002) ───────────────────────────
// La API key vive en Secret Manager y jamás sale del servidor.
export { generateGoalPlan } from './callable/generate-goal-plan';
// export { suggestMissions } from './callable/suggest-missions';
// export { getMotivation } from './callable/get-motivation';

// ── Fase 7 — Notificaciones ──────────────────────────────────────────────
// La bandeja in-app y las push comparten decisión: `lib/notifications.ts`
// respeta el interruptor por tipo y el horario de silencio de cada persona.
export { dailyReminders } from './scheduled/daily-reminders';

// ── Fase 8 — Administración ──────────────────────────────────────────────
// setUserRole se adelantó a la Fase 1 (ver arriba).
// Las escrituras administrativas pasan por acá y no por el panel porque
// `auditLog` es inescribible desde cualquier cliente: es la única forma de
// garantizar que la acción y su registro ocurran juntos o no ocurran.
export { setUserStatus } from './callable/set-user-status';
export { moderateContent } from './callable/moderate-content';
export { aggregateStats } from './scheduled/aggregate-stats';
// export { costReport } from './scheduled/cost-report';

export { healthCheck } from './callable/health-check';
