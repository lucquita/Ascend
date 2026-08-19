/**
 * Lógica pura de la administración.
 *
 * Todo lo que se pueda decidir sin tocar Firestore vive acá para poder probarlo
 * sin emuladores. Las funciones llamables quedan como cableado: validan, llaman
 * a esto y escriben.
 */

import type { ModerateContentInput } from '../lib/validation';

/** Colecciones cuyos documentos puede ocultar la moderación. */
export const MODERATABLE_TYPES = ['post', 'comment'] as const;

/** Tipo de contenido reportado. */
export type ModeratableType = (typeof MODERATABLE_TYPES)[number];

/** Resultado de comprobar si una acción de moderación es aplicable. */
export type ModerationCheck =
  | { ok: true }
  | { ok: false; code: 'note-required' | 'unknown-target' | 'already-closed' };

/**
 * Comprueba una decisión de moderación antes de aplicarla.
 *
 * Las tres condiciones existen por motivos distintos:
 *
 * - **Nota obligatoria al suspender.** Suspender una cuenta es la acción más
 *   grave del panel y la más difícil de revertir socialmente: quien la sufre
 *   pregunta por qué. Sin nota, ni siquiera quien la aplicó se acuerda un mes
 *   después.
 * - **Tipo conocido.** Ocultar un documento de una colección que no
 *   contemplamos escribiría un campo `moderation` en cualquier lado.
 * - **Reporte abierto.** Resolver dos veces el mismo reporte duplicaría la
 *   entrada de auditoría y podría suspender a alguien dos veces por lo mismo.
 */
export function checkModeration(input: {
  action: ModerateContentInput['action'];
  note?: string | undefined;
  targetType: string;
  reportStatus: string;
}): ModerationCheck {
  if (input.reportStatus !== 'open' && input.reportStatus !== 'reviewing') {
    return { ok: false, code: 'already-closed' };
  }
  if (!MODERATABLE_TYPES.includes(input.targetType as ModeratableType)) {
    return { ok: false, code: 'unknown-target' };
  }
  if (
    input.action === 'suspend_author' &&
    (input.note ?? '').trim().length < 5
  ) {
    return { ok: false, code: 'note-required' };
  }
  return { ok: true };
}

/** `true` si la acción implica esconder el contenido del feed. */
export function hidesContent(action: ModerateContentInput['action']): boolean {
  return action === 'hide_content' || action === 'suspend_author';
}

/** Estado en que queda el reporte tras la decisión. */
export function resolvedStatus(
  action: ModerateContentInput['action'],
): 'resolved' | 'dismissed' {
  return action === 'dismiss' ? 'dismissed' : 'resolved';
}

/**
 * Comienzo de la ventana móvil de N días, en UTC y a medianoche.
 *
 * Se normaliza a medianoche para que dos ejecuciones el mismo día cuenten
 * exactamente lo mismo. Sin esto, la métrica de "activos en 7 días" cambiaría
 * según la hora a la que corrió la agregación, y nadie podría comparar dos días
 * seguidos.
 */
export function windowStart(now: Date, days: number): Date {
  const start = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
  start.setUTCDate(start.getUTCDate() - days);
  return start;
}

/** Identificador del documento diario de métricas (`2026-08-17`). */
export function statsDocId(now: Date): string {
  return now.toISOString().slice(0, 10);
}

/** Contadores crudos que produce la agregación. */
export interface StatsCounters {
  usersTotal: number;
  usersActive7d: number;
  usersNew7d: number;
  goalsActive: number;
  missionsCompleted7d: number;
  auraGranted7d: number;
  postsTotal: number;
  reportsOpen: number;
  aiCallsToday: number;
}

/**
 * Costo estimado por llamada a Gemini Flash, en dólares.
 *
 * Es una estimación deliberadamente **conservadora** (por lo alto): un panel de
 * costos que subestima es peor que no tenerlo, porque da tranquilidad falsa. El
 * número exacto sale de la factura; este sirve para detectar un salto raro
 * antes de que llegue.
 */
export const AI_COST_PER_CALL_USD = 0.0004;

/** Arma el documento de métricas que lee el panel. */
export function buildStatsDocument(
  counters: StatsCounters,
  now: Date,
): Record<string, unknown> {
  return {
    ...counters,
    aiCostUsdToday: Number(
      (counters.aiCallsToday * AI_COST_PER_CALL_USD).toFixed(4),
    ),
    generatedAt: now.toISOString(),
  };
}
