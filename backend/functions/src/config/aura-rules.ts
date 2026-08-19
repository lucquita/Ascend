/**
 * Reglas de gamificación.
 *
 * Los valores viven en `config/auraRules` de Firestore para poder ajustarlos sin
 * publicar una versión nueva de la app: el balance de un sistema de puntos se
 * afina con datos reales, no de antemano. Estos son los **valores por defecto**,
 * que se usan si el documento no existe todavía.
 *
 * Coinciden con §2.12 del modelo de datos.
 */

/** Dificultades reconocidas. Cualquier otra cae en `medium`. */
export type Difficulty = 'easy' | 'medium' | 'hard';

/** Tramo de bonificación por racha. */
export interface StreakMultiplier {
  readonly minDays: number;
  readonly multiplier: number;
}

/** Definición de un nivel. */
export interface LevelDefinition {
  readonly level: number;
  readonly name: string;
  readonly minAura: number;
}

/** Conjunto completo de reglas. */
export interface AuraRules {
  readonly rewards: {
    readonly mission: Record<Difficulty, number>;
    readonly goalCompleted: number;
    readonly milestone: number;
    readonly dailyLogin: number;
    readonly evidenceBonus: number;
  };
  readonly streakMultipliers: readonly StreakMultiplier[];
  readonly levels: readonly LevelDefinition[];
  readonly dailyCaps: {
    readonly maxAuraPerDay: number;
    readonly maxMissionsPerDay: number;
  };
}

export const DEFAULT_AURA_RULES: AuraRules = {
  rewards: {
    mission: { easy: 10, medium: 25, hard: 50 },
    goalCompleted: 200,
    milestone: 50,
    dailyLogin: 5,
    // Adjuntar evidencia suma un poco: premia el hábito de documentar sin
    // volverlo obligatorio.
    evidenceBonus: 5,
  },
  streakMultipliers: [
    { minDays: 3, multiplier: 1.1 },
    { minDays: 7, multiplier: 1.25 },
    { minDays: 14, multiplier: 1.5 },
    { minDays: 30, multiplier: 2.0 },
  ],
  levels: [
    { level: 1, name: 'Iniciado', minAura: 0 },
    { level: 2, name: 'Aprendiz', minAura: 100 },
    { level: 3, name: 'Disciplinado', minAura: 300 },
    { level: 5, name: 'Enfocado', minAura: 900 },
    { level: 7, name: 'Constante', minAura: 1700 },
    { level: 10, name: 'Imparable', minAura: 4000 },
    { level: 15, name: 'Ascendido', minAura: 12000 },
  ],
  dailyCaps: {
    // El tope existe para prevenir farmeo: crear 200 misiones triviales y
    // completarlas no puede dar el nivel máximo.
    maxAuraPerDay: 500,
    maxMissionsPerDay: 20,
  },
};

/**
 * Normaliza las reglas leídas de Firestore.
 *
 * Un documento a medio editar desde el panel no puede tumbar el motor de Aura:
 * cada campo ausente o con el tipo equivocado cae a su valor por defecto.
 */
export function parseAuraRules(data: unknown): AuraRules {
  if (typeof data !== 'object' || data === null) {
    return DEFAULT_AURA_RULES;
  }

  const raw = data as Record<string, unknown>;
  const rewards = asRecord(raw.rewards);
  const mission = asRecord(rewards.mission);
  const caps = asRecord(raw.dailyCaps);

  return {
    rewards: {
      mission: {
        easy: asPositiveInt(
          mission.easy,
          DEFAULT_AURA_RULES.rewards.mission.easy,
        ),
        medium: asPositiveInt(
          mission.medium,
          DEFAULT_AURA_RULES.rewards.mission.medium,
        ),
        hard: asPositiveInt(
          mission.hard,
          DEFAULT_AURA_RULES.rewards.mission.hard,
        ),
      },
      goalCompleted: asPositiveInt(
        rewards.goalCompleted,
        DEFAULT_AURA_RULES.rewards.goalCompleted,
      ),
      milestone: asPositiveInt(
        rewards.milestone,
        DEFAULT_AURA_RULES.rewards.milestone,
      ),
      dailyLogin: asPositiveInt(
        rewards.dailyLogin,
        DEFAULT_AURA_RULES.rewards.dailyLogin,
      ),
      evidenceBonus: asPositiveInt(
        rewards.evidenceBonus,
        DEFAULT_AURA_RULES.rewards.evidenceBonus,
      ),
    },
    streakMultipliers: parseStreaks(raw.streakMultipliers),
    levels: parseLevels(raw.levels),
    dailyCaps: {
      maxAuraPerDay: asPositiveInt(
        caps.maxAuraPerDay,
        DEFAULT_AURA_RULES.dailyCaps.maxAuraPerDay,
      ),
      maxMissionsPerDay: asPositiveInt(
        caps.maxMissionsPerDay,
        DEFAULT_AURA_RULES.dailyCaps.maxMissionsPerDay,
      ),
    },
  };
}

function parseStreaks(value: unknown): readonly StreakMultiplier[] {
  if (!Array.isArray(value)) {
    return DEFAULT_AURA_RULES.streakMultipliers;
  }
  const parsed = value
    .map((item) => asRecord(item))
    .filter(
      (item) =>
        typeof item.minDays === 'number' && typeof item.multiplier === 'number',
    )
    .map((item) => ({
      minDays: Math.max(0, Math.floor(item.minDays as number)),
      // Un multiplicador menor a 1 castigaría por tener racha, que es lo
      // contrario de lo que el sistema quiere premiar.
      multiplier: Math.max(1, item.multiplier as number),
    }))
    .sort((a, b) => a.minDays - b.minDays);

  return parsed.length > 0 ? parsed : DEFAULT_AURA_RULES.streakMultipliers;
}

function parseLevels(value: unknown): readonly LevelDefinition[] {
  if (!Array.isArray(value)) {
    return DEFAULT_AURA_RULES.levels;
  }
  const parsed = value
    .map((item) => asRecord(item))
    .filter(
      (item) =>
        typeof item.level === 'number' &&
        typeof item.minAura === 'number' &&
        typeof item.name === 'string',
    )
    .map((item) => ({
      level: Math.floor(item.level as number),
      name: item.name as string,
      minAura: Math.max(0, Math.floor(item.minAura as number)),
    }))
    .sort((a, b) => a.minAura - b.minAura);

  return parsed.length > 0 ? parsed : DEFAULT_AURA_RULES.levels;
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

function asPositiveInt(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0
    ? Math.floor(value)
    : fallback;
}
