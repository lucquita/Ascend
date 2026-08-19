import { describe, expect, it } from 'vitest';
import { DEFAULT_AURA_RULES, parseAuraRules } from '../src/config/aura-rules';
import {
  computeMissionAward,
  dayKey,
  ledgerEntryId,
  levelFor,
  nextStreak,
  normalizeDifficulty,
  shouldBreakStreak,
  streakMultiplierFor,
} from '../src/services/aura-service';

const rules = DEFAULT_AURA_RULES;

describe('computeMissionAward — la recompensa que el cliente no puede fijar', () => {
  it('paga según la dificultad', () => {
    for (const [difficulty, expected] of [
      ['easy', 10],
      ['medium', 25],
      ['hard', 50],
    ] as const) {
      const award = computeMissionAward({
        difficulty,
        streakDays: 0,
        awardedToday: 0,
        hasEvidence: false,
        rules,
      });
      expect(award.amount).toBe(expected);
    }
  });

  it('una dificultad desconocida se paga como media, no como máxima', () => {
    // Si un valor corrupto pagara como `hard`, alguien podría escribir
    // basura en el campo para cobrar de más.
    const award = computeMissionAward({
      difficulty: 'imposible',
      streakDays: 0,
      awardedToday: 0,
      hasEvidence: false,
      rules,
    });
    expect(award.amount).toBe(25);
  });

  it('la evidencia suma antes del multiplicador', () => {
    // Documentar con racha alta tiene que rendir más que documentar sin racha.
    const sinRacha = computeMissionAward({
      difficulty: 'medium',
      streakDays: 0,
      awardedToday: 0,
      hasEvidence: true,
      rules,
    });
    expect(sinRacha.amount).toBe(30); // 25 + 5

    const conRacha = computeMissionAward({
      difficulty: 'medium',
      streakDays: 14,
      awardedToday: 0,
      hasEvidence: true,
      rules,
    });
    expect(conRacha.amount).toBe(45); // (25 + 5) × 1.5
  });

  it('aplica el multiplicador de racha del tramo alcanzado', () => {
    const award = computeMissionAward({
      difficulty: 'hard',
      streakDays: 30,
      awardedToday: 0,
      hasEvidence: false,
      rules,
    });

    expect(award.multiplier).toBe(2);
    expect(award.amount).toBe(100);
    expect(award.note).toContain('×2');
  });

  it('el tope diario recorta la recompensa', () => {
    // Es la defensa contra el farmeo: crear 200 misiones triviales y
    // completarlas no puede dar el nivel máximo.
    const award = computeMissionAward({
      difficulty: 'hard',
      streakDays: 0,
      awardedToday: 480,
      hasEvidence: false,
      rules,
    });

    expect(award.rawAmount).toBe(50);
    expect(award.amount).toBe(20); // solo quedaban 20 del tope de 500
    expect(award.capped).toBe(true);
    expect(award.note).toContain('tope diario');
  });

  it('con el tope ya agotado la recompensa es cero, no negativa', () => {
    const award = computeMissionAward({
      difficulty: 'hard',
      streakDays: 30,
      awardedToday: 500,
      hasEvidence: true,
      rules,
    });

    expect(award.amount).toBe(0);
    expect(award.capped).toBe(true);
  });

  it('la recompensa siempre es entera', () => {
    // 25 × 1.1 = 27.5. Un saldo con decimales rompería el ledger.
    const award = computeMissionAward({
      difficulty: 'medium',
      streakDays: 3,
      awardedToday: 0,
      hasEvidence: false,
      rules,
    });

    expect(Number.isInteger(award.amount)).toBe(true);
    expect(award.amount).toBe(27);
  });
});

describe('streakMultiplierFor', () => {
  it('sin racha no bonifica', () => {
    expect(streakMultiplierFor(0, rules)).toBe(1);
    expect(streakMultiplierFor(2, rules)).toBe(1);
    expect(streakMultiplierFor(-5, rules)).toBe(1);
  });

  it('devuelve el tramo más alto alcanzado', () => {
    expect(streakMultiplierFor(3, rules)).toBe(1.1);
    expect(streakMultiplierFor(6, rules)).toBe(1.1);
    expect(streakMultiplierFor(7, rules)).toBe(1.25);
    expect(streakMultiplierFor(29, rules)).toBe(1.5);
    expect(streakMultiplierFor(365, rules)).toBe(2);
  });
});

describe('levelFor — tabla rala de niveles', () => {
  it('una cuenta nueva arranca en el nivel 1', () => {
    const progress = levelFor(0, rules);
    expect(progress.level).toBe(1);
    expect(progress.levelName).toBe('Iniciado');
    expect(progress.xpForNextLevel).toBe(100);
  });

  it('mide el avance contra el siguiente tramo definido', () => {
    // La tabla salta de 3 (300) a 5 (900): con 500 se está en el nivel 3 y
    // faltan 400 para el siguiente tramo.
    const progress = levelFor(500, rules);
    expect(progress.level).toBe(3);
    expect(progress.levelName).toBe('Disciplinado');
    expect(progress.xpInLevel).toBe(200);
    expect(progress.xpForNextLevel).toBe(600);
  });

  it('en el último nivel no divide por cero', () => {
    const progress = levelFor(999_999, rules);
    expect(progress.level).toBe(15);
    expect(progress.xpForNextLevel).toBe(0);
  });

  it('un total negativo se trata como cero', () => {
    expect(levelFor(-100, rules).level).toBe(1);
  });

  it('justo en el umbral ya cuenta el nivel nuevo', () => {
    expect(levelFor(100, rules).level).toBe(2);
    expect(levelFor(99, rules).level).toBe(1);
  });
});

describe('ledgerEntryId — el mecanismo de idempotencia', () => {
  it('la misma misión produce siempre el mismo id', () => {
    // Es lo que impide que un doble toque, o un reintento del runtime de
    // Functions, otorgue el Aura dos veces.
    expect(ledgerEntryId('mission_completed', 'm1')).toBe(
      ledgerEntryId('mission_completed', 'm1')
    );
  });

  it('misiones distintas producen ids distintos', () => {
    expect(ledgerEntryId('mission_completed', 'm1')).not.toBe(
      ledgerEntryId('mission_completed', 'm2')
    );
  });
});

describe('nextStreak', () => {
  it('sin actividad previa arranca en 1', () => {
    expect(
      nextStreak({ lastActivityDay: null, today: '2026-08-14', currentStreak: 0 })
    ).toBe(1);
  });

  it('completar otra misión el mismo día no infla la racha', () => {
    // Si cada misión sumara un día, diez misiones en una tarde darían una
    // racha de diez días.
    expect(
      nextStreak({
        lastActivityDay: '2026-08-14',
        today: '2026-08-14',
        currentStreak: 5,
      })
    ).toBe(5);
  });

  it('el día siguiente suma uno', () => {
    expect(
      nextStreak({
        lastActivityDay: '2026-08-13',
        today: '2026-08-14',
        currentStreak: 5,
      })
    ).toBe(6);
  });

  it('saltarse un día reinicia la racha', () => {
    expect(
      nextStreak({
        lastActivityDay: '2026-08-11',
        today: '2026-08-14',
        currentStreak: 30,
      })
    ).toBe(1);
  });

  it('funciona cruzando meses', () => {
    expect(
      nextStreak({
        lastActivityDay: '2026-07-31',
        today: '2026-08-01',
        currentStreak: 3,
      })
    ).toBe(4);
  });

  it('una fecha corrupta no rompe: reinicia', () => {
    expect(
      nextStreak({
        lastActivityDay: 'ayer',
        today: '2026-08-14',
        currentStreak: 9,
      })
    ).toBe(1);
  });
});

describe('dayKey', () => {
  it('usa UTC para que el tope no dependa del huso del dispositivo', () => {
    expect(dayKey(new Date('2026-08-14T23:59:59Z'))).toBe('2026-08-14');
    expect(dayKey(new Date('2026-08-15T00:00:01Z'))).toBe('2026-08-15');
  });

  it('rellena mes y día con cero', () => {
    expect(dayKey(new Date('2026-01-05T12:00:00Z'))).toBe('2026-01-05');
  });
});

describe('parseAuraRules — un documento roto no puede tumbar el motor', () => {
  it('sin documento usa los valores por defecto', () => {
    expect(parseAuraRules(undefined)).toEqual(DEFAULT_AURA_RULES);
    expect(parseAuraRules(null)).toEqual(DEFAULT_AURA_RULES);
    expect(parseAuraRules('no soy un objeto')).toEqual(DEFAULT_AURA_RULES);
  });

  it('completa los campos que falten', () => {
    const parsed = parseAuraRules({ rewards: { mission: { easy: 15 } } });

    expect(parsed.rewards.mission.easy).toBe(15);
    expect(parsed.rewards.mission.hard).toBe(50); // del default
    expect(parsed.dailyCaps.maxAuraPerDay).toBe(500);
  });

  it('descarta valores con el tipo equivocado', () => {
    const parsed = parseAuraRules({
      rewards: { mission: { easy: 'mucho', medium: -5 } },
      dailyCaps: { maxAuraPerDay: null },
    });

    expect(parsed.rewards.mission.easy).toBe(10);
    expect(parsed.rewards.mission.medium).toBe(25);
    expect(parsed.dailyCaps.maxAuraPerDay).toBe(500);
  });

  it('un multiplicador menor a 1 se eleva a 1', () => {
    // Bonificar con 0.5 castigaría por tener racha, que es lo contrario de lo
    // que el sistema premia.
    const parsed = parseAuraRules({
      streakMultipliers: [{ minDays: 3, multiplier: 0.5 }],
    });

    expect(parsed.streakMultipliers[0]?.multiplier).toBe(1);
  });

  it('ordena los tramos y los niveles aunque vengan desordenados', () => {
    const parsed = parseAuraRules({
      levels: [
        { level: 3, name: 'Tercero', minAura: 300 },
        { level: 1, name: 'Primero', minAura: 0 },
      ],
    });

    expect(parsed.levels.map((l) => l.level)).toEqual([1, 3]);
  });
});

describe('normalizeDifficulty', () => {
  it('solo acepta los tres valores conocidos', () => {
    expect(normalizeDifficulty('easy')).toBe('easy');
    expect(normalizeDifficulty('hard')).toBe('hard');
    expect(normalizeDifficulty('medium')).toBe('medium');
    expect(normalizeDifficulty(null)).toBe('medium');
    expect(normalizeDifficulty(42)).toBe('medium');
  });
});

describe('shouldBreakStreak — la racha se pierde por inacción', () => {
  it('no rompe si la última actividad fue hoy', () => {
    expect(
      shouldBreakStreak({
        lastActivityDay: '2026-08-14',
        today: '2026-08-14',
        currentStreak: 5,
      })
    ).toBe(false);
  });

  it('no rompe si la última actividad fue ayer', () => {
    // Todavía está a tiempo de completar algo hoy. Romperla a las 00:01
    // castigaría a quien entrena de noche.
    expect(
      shouldBreakStreak({
        lastActivityDay: '2026-08-13',
        today: '2026-08-14',
        currentStreak: 5,
      })
    ).toBe(false);
  });

  it('rompe a partir de dos días sin actividad', () => {
    expect(
      shouldBreakStreak({
        lastActivityDay: '2026-08-12',
        today: '2026-08-14',
        currentStreak: 5,
      })
    ).toBe(true);
  });

  it('sin racha activa no hay nada que romper', () => {
    // Evita escrituras inútiles sobre cuentas que ya están en cero.
    expect(
      shouldBreakStreak({
        lastActivityDay: null,
        today: '2026-08-14',
        currentStreak: 0,
      })
    ).toBe(false);
  });

  it('con racha pero sin fecha de actividad, rompe', () => {
    // Dato inconsistente: es más seguro reiniciar que sostener una racha que
    // no se puede justificar.
    expect(
      shouldBreakStreak({
        lastActivityDay: null,
        today: '2026-08-14',
        currentStreak: 9,
      })
    ).toBe(true);
  });

  it('una fecha corrupta rompe la racha', () => {
    expect(
      shouldBreakStreak({
        lastActivityDay: 'anteayer',
        today: '2026-08-14',
        currentStreak: 9,
      })
    ).toBe(true);
  });
});
