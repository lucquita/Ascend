/**
 * Motor de Aura. **Lógica pura, sin Firestore.**
 *
 * Está separada del trigger a propósito: las reglas que hacen que la
 * gamificación sea justa —idempotencia, tope diario, multiplicadores, niveles—
 * son exactamente las que hay que poder testear exhaustivamente, y hacerlo
 * contra el emulador sería lento y frágil. El trigger se queda con lo único que
 * no se puede testear puro: la transacción.
 *
 * Ver ADR-003: el cliente **solo** cambia `mission.status`. Todo lo de acá
 * ocurre del lado del servidor.
 */

import type {
  AuraRules,
  Difficulty,
  LevelDefinition,
} from '../config/aura-rules';

/** Nivel alcanzado y avance dentro de él. */
export interface LevelProgress {
  readonly level: number;
  readonly levelName: string;
  readonly xpInLevel: number;
  readonly xpForNextLevel: number;
}

/** Resultado del cálculo de una recompensa. */
export interface AuraAward {
  /** Aura efectivamente otorgada, ya con tope aplicado. */
  readonly amount: number;
  /** Recompensa antes del tope, para poder explicar la diferencia. */
  readonly rawAmount: number;
  /** Multiplicador de racha aplicado. */
  readonly multiplier: number;
  /** `true` si el tope diario recortó la recompensa. */
  readonly capped: boolean;
  /** Explicación legible para el ledger. */
  readonly note: string;
}

/** Normaliza una dificultad desconocida a `medium`. */
export function normalizeDifficulty(value: unknown): Difficulty {
  return value === 'easy' || value === 'hard' ? value : 'medium';
}

/**
 * Multiplicador que corresponde a una racha.
 *
 * Devuelve el tramo más alto alcanzado. Una racha de 0 o negativa no bonifica.
 */
export function streakMultiplierFor(
  streakDays: number,
  rules: AuraRules,
): number {
  let multiplier = 1;
  for (const tier of rules.streakMultipliers) {
    if (streakDays >= tier.minDays) {
      multiplier = tier.multiplier;
    }
  }
  return multiplier;
}

/**
 * Calcula la recompensa por completar una misión.
 *
 * @param awardedToday Aura ya otorgada hoy, para aplicar el tope.
 */
export function computeMissionAward(params: {
  difficulty: unknown;
  streakDays: number;
  awardedToday: number;
  hasEvidence: boolean;
  rules: AuraRules;
}): AuraAward {
  const { streakDays, awardedToday, hasEvidence, rules } = params;
  const difficulty = normalizeDifficulty(params.difficulty);

  const base = rules.rewards.mission[difficulty];
  // La bonificación por evidencia se suma ANTES del multiplicador: documentar
  // con racha alta tiene que rendir más que documentar sin racha.
  const withEvidence = base + (hasEvidence ? rules.rewards.evidenceBonus : 0);
  const multiplier = streakMultiplierFor(streakDays, rules);
  const rawAmount = Math.floor(withEvidence * multiplier);

  const remaining = Math.max(0, rules.dailyCaps.maxAuraPerDay - awardedToday);
  const amount = Math.min(rawAmount, remaining);
  const capped = amount < rawAmount;

  return {
    amount,
    rawAmount,
    multiplier,
    capped,
    note: buildNote({
      difficulty,
      multiplier,
      streakDays,
      hasEvidence,
      capped,
    }),
  };
}

function buildNote(params: {
  difficulty: Difficulty;
  multiplier: number;
  streakDays: number;
  hasEvidence: boolean;
  capped: boolean;
}): string {
  const parts: string[] = [`Misión ${params.difficulty}`];
  if (params.hasEvidence) {
    parts.push('con evidencia');
  }
  if (params.multiplier > 1) {
    parts.push(`racha de ${params.streakDays} días ×${params.multiplier}`);
  }
  if (params.capped) {
    parts.push('recortada por el tope diario');
  }
  return parts.join(' · ');
}

/**
 * Resuelve el nivel correspondiente a un saldo.
 *
 * La tabla de niveles es **rala**: define 1, 2, 3, 5, 7, 10 y 15. Se devuelve el
 * nivel más alto cuyo `minAura` no supere el total, y el progreso se mide contra
 * el siguiente tramo definido. En el último nivel no hay siguiente, y el avance
 * se informa como completo en vez de dividir por cero.
 */
export function levelFor(total: number, rules: AuraRules): LevelProgress {
  const levels = [...rules.levels].sort((a, b) => a.minAura - b.minAura);
  const safeTotal = Math.max(0, Math.floor(total));

  let current: LevelDefinition = levels[0] ?? {
    level: 1,
    name: 'Iniciado',
    minAura: 0,
  };
  let next: LevelDefinition | undefined;

  for (const level of levels) {
    if (safeTotal >= level.minAura) {
      current = level;
    } else {
      next = level;
      break;
    }
  }

  if (!next) {
    return {
      level: current.level,
      levelName: current.name,
      xpInLevel: safeTotal - current.minAura,
      xpForNextLevel: 0,
    };
  }

  return {
    level: current.level,
    levelName: current.name,
    xpInLevel: safeTotal - current.minAura,
    xpForNextLevel: next.minAura - current.minAura,
  };
}

/**
 * Identificador determinístico de un asiento del ledger.
 *
 * **Es el mecanismo de idempotencia.** Completar dos veces la misma misión
 * produce el mismo id, así que la transacción encuentra el asiento ya escrito y
 * no otorga Aura de nuevo. Sin esto, un doble toque o un reintento del runtime
 * de Functions duplicarían la recompensa — y el ranking dejaría de significar
 * nada.
 */
export function ledgerEntryId(reason: string, refId: string): string {
  return `${reason}__${refId}`;
}

/** Clave de día (`YYYY-MM-DD`) en UTC, para agrupar el tope diario. */
export function dayKey(date: Date): string {
  const year = date.getUTCFullYear();
  const month = `${date.getUTCMonth() + 1}`.padStart(2, '0');
  const day = `${date.getUTCDate()}`.padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Decide cómo queda la racha tras una actividad.
 *
 * - Misma fecha que la última actividad: la racha no cambia (ya contó hoy).
 * - Día siguiente: suma uno.
 * - Cualquier salto mayor, o sin actividad previa: vuelve a empezar en 1.
 */
export function nextStreak(params: {
  lastActivityDay: string | null;
  today: string;
  currentStreak: number;
}): number {
  const { lastActivityDay, today, currentStreak } = params;
  if (!lastActivityDay) {
    return 1;
  }
  if (lastActivityDay === today) {
    return Math.max(1, currentStreak);
  }

  const previous = new Date(`${lastActivityDay}T00:00:00Z`);
  const current = new Date(`${today}T00:00:00Z`);
  if (Number.isNaN(previous.getTime()) || Number.isNaN(current.getTime())) {
    return 1;
  }

  const diffDays = Math.round(
    (current.getTime() - previous.getTime()) / 86_400_000,
  );
  return diffDays === 1 ? Math.max(1, currentStreak) + 1 : 1;
}

/**
 * Decide si una racha ya se perdió.
 *
 * Se rompe cuando pasaron **dos o más días** sin actividad. Un solo día de
 * diferencia es "ayer": la persona todavía está a tiempo de completar algo hoy
 * y conservarla. Romperla a las 00:01 del día siguiente sería castigar a quien
 * entrena de noche.
 */
export function shouldBreakStreak(params: {
  lastActivityDay: string | null;
  today: string;
  currentStreak: number;
}): boolean {
  const { lastActivityDay, today, currentStreak } = params;
  if (currentStreak <= 0) {
    return false;
  }
  if (!lastActivityDay) {
    return true;
  }

  const previous = new Date(`${lastActivityDay}T00:00:00Z`);
  const current = new Date(`${today}T00:00:00Z`);
  if (Number.isNaN(previous.getTime()) || Number.isNaN(current.getTime())) {
    return true;
  }

  const diffDays = Math.round(
    (current.getTime() - previous.getTime()) / 86_400_000,
  );
  return diffDays >= 2;
}
