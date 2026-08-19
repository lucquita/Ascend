import { describe, expect, it } from 'vitest';
import {
  MAX_GENERATED_MISSIONS,
  MAX_MISSION_MINUTES,
  dedupeMissions,
  extractJson,
  filterByBudget,
  parseGoalPlan,
} from '../src/services/ai-schemas';
import { checkQuota, quotaDayKey, shouldRefund } from '../src/services/ai-quota';
import { estimateCostUsd } from '../src/services/gemini-service';
import {
  GOAL_PLAN_PROMPT_VERSION,
  buildGoalPlanPrompt,
  buildSuggestMissionsPrompt,
} from '../src/config/prompts';

const validMission = {
  title: 'Ver un capítulo con subtítulos en inglés',
  difficulty: 'medium',
  budget: 'free',
  estimatedMinutes: 25,
};

function planJson(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({ missions: [validMission], ...overrides });
}

describe('extractJson — el modelo no siempre respeta el formato', () => {
  it('parsea JSON limpio', () => {
    expect(extractJson('{"a":1}')).toEqual({ a: 1 });
  });

  it('limpia las cercas de markdown', () => {
    // Gemini a veces envuelve el JSON en un bloque de código aunque se le pida
    // `application/json`. Descartar esa respuesta sería tirar una válida.
    expect(extractJson('```json\n{"a":1}\n```')).toEqual({ a: 1 });
    expect(extractJson('```\n{"a":1}\n```')).toEqual({ a: 1 });
  });

  it('devuelve null ante basura, no lanza', () => {
    expect(extractJson('lo siento, no puedo ayudarte con eso')).toBeNull();
    expect(extractJson('')).toBeNull();
  });
});

describe('parseGoalPlan — la frontera entre el modelo y los datos', () => {
  it('acepta un plan válido', () => {
    const result = parseGoalPlan(planJson());
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.plan.missions).toHaveLength(1);
    }
  });

  it('rechaza JSON malformado con un motivo utilizable', () => {
    // El motivo se registra en `aiJobs`: hay que poder saber POR QUÉ falló una
    // generación, no solo que falló.
    const result = parseGoalPlan('no soy json');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('malformed-json');
    }
  });

  it('rechaza un título vacío', () => {
    // Pasaría el schema de tipos del proveedor: es string. Pero una misión sin
    // título es basura que terminaría en la lista de alguien.
    const result = parseGoalPlan(
      JSON.stringify({ missions: [{ ...validMission, title: '   ' }] })
    );
    expect(result.ok).toBe(false);
  });

  it('rechaza una duración imposible', () => {
    const larga = parseGoalPlan(
      JSON.stringify({
        missions: [{ ...validMission, estimatedMinutes: MAX_MISSION_MINUTES + 1 }],
      })
    );
    expect(larga.ok).toBe(false);

    const cero = parseGoalPlan(
      JSON.stringify({ missions: [{ ...validMission, estimatedMinutes: 0 }] })
    );
    expect(cero.ok).toBe(false);
  });

  it('rechaza una dificultad o presupuesto inventados', () => {
    expect(
      parseGoalPlan(
        JSON.stringify({ missions: [{ ...validMission, difficulty: 'épica' }] })
      ).ok
    ).toBe(false);

    expect(
      parseGoalPlan(
        JSON.stringify({ missions: [{ ...validMission, budget: 'carísimo' }] })
      ).ok
    ).toBe(false);
  });

  it('rechaza un plan vacío', () => {
    // Un plan sin misiones no es un plan: la persona vería una pantalla de
    // revisión sin nada que revisar.
    expect(parseGoalPlan(JSON.stringify({ missions: [] })).ok).toBe(false);
  });

  it('rechaza un plan desmesurado', () => {
    const missions = Array.from(
      { length: MAX_GENERATED_MISSIONS + 1 },
      (_, i) => ({ ...validMission, title: `Misión ${i}` })
    );
    expect(parseGoalPlan(JSON.stringify({ missions })).ok).toBe(false);
  });

  it('los hitos son opcionales', () => {
    expect(parseGoalPlan(planJson()).ok).toBe(true);
    expect(
      parseGoalPlan(planJson({ milestones: [{ title: 'Primer hito' }] })).ok
    ).toBe(true);
  });

  it('recorta los espacios de los títulos', () => {
    const result = parseGoalPlan(
      JSON.stringify({ missions: [{ ...validMission, title: '  Correr  ' }] })
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.plan.missions[0]?.title).toBe('Correr');
    }
  });
});

describe('dedupeMissions', () => {
  it('descarta títulos repetidos ignorando mayúsculas y espacios', () => {
    // El modelo devuelve la misma acción dos veces con otras palabras más
    // seguido de lo que uno esperaría.
    const result = dedupeMissions([
      validMission as never,
      { ...validMission, title: 'ver un capítulo   CON subtítulos en inglés' } as never,
      { ...validMission, title: 'Salir a correr' } as never,
    ]);

    expect(result).toHaveLength(2);
  });

  it('conserva el orden de aparición', () => {
    const result = dedupeMissions([
      { ...validMission, title: 'Primera' } as never,
      { ...validMission, title: 'Segunda' } as never,
    ]);
    expect(result.map((m) => m.title)).toEqual(['Primera', 'Segunda']);
  });
});

describe('filterByBudget — el modelo no siempre obedece el prompt', () => {
  const missions = [
    { ...validMission, title: 'Gratis', budget: 'free' },
    { ...validMission, title: 'Baja', budget: 'low' },
    { ...validMission, title: 'Alta', budget: 'high' },
  ] as never[];

  it('con presupuesto gratis solo deja las gratuitas', () => {
    // Devolverle a alguien que dijo "gratis" una misión que cuesta plata es
    // peor que devolverle una misión menos.
    const result = filterByBudget(missions, 'free');
    expect(result.map((m) => m.title)).toEqual(['Gratis']);
  });

  it('el tope es inclusivo y acumulativo', () => {
    expect(filterByBudget(missions, 'low')).toHaveLength(2);
    expect(filterByBudget(missions, 'high')).toHaveLength(3);
  });
});

describe('checkQuota — el tope que protege la factura', () => {
  it('permite mientras quede saldo', () => {
    const decision = checkQuota({ used: 3, limit: 20 });
    expect(decision.allowed).toBe(true);
    expect(decision.remaining).toBe(17);
  });

  it('bloquea al llegar al límite', () => {
    const decision = checkQuota({ used: 20, limit: 20 });
    expect(decision.allowed).toBe(false);
    expect(decision.reason).toBe('daily-limit-reached');
  });

  it('un contador corrupto por encima del límite no da saldo negativo', () => {
    const decision = checkQuota({ used: 999, limit: 20 });
    expect(decision.allowed).toBe(false);
    expect(decision.remaining).toBe(0);
  });
});

describe('shouldRefund — un fallo nuestro no consume la cuota de nadie', () => {
  it('solo el éxito consume cuota', () => {
    expect(shouldRefund('success')).toBe(false);
  });

  it('cualquier fallo la devuelve', () => {
    // La persona no recibió nada: cobrarle el intento sería castigarla por un
    // problema nuestro o del proveedor.
    for (const outcome of [
      'failed',
      'rate_limited',
      'invalid_output',
      'blocked',
    ] as const) {
      expect(shouldRefund(outcome)).toBe(true);
    }
  });
});

describe('quotaDayKey', () => {
  it('usa UTC para que la cuota no dependa del huso', () => {
    expect(quotaDayKey(new Date('2026-08-14T23:59:59Z'))).toBe('2026-08-14');
    expect(quotaDayKey(new Date('2026-08-15T00:00:01Z'))).toBe('2026-08-15');
  });
});

describe('estimateCostUsd', () => {
  it('calcula el costo y no devuelve cero para uso real', () => {
    // Sin esto no se puede responder cuánto cuesta la IA por usuario activo.
    const cost = estimateCostUsd({ promptTokens: 1000, outputTokens: 2000 });
    expect(cost).toBeGreaterThan(0);
  });

  it('sin tokens no hay costo', () => {
    expect(estimateCostUsd({ promptTokens: 0, outputTokens: 0 })).toBe(0);
  });
});

describe('Prompts', () => {
  it('el prompt de plan incluye lo que el modelo necesita', () => {
    const prompt = buildGoalPlanPrompt({
      goalTitle: 'Aprender inglés',
      categoryId: 'languages',
      horizonDays: 90,
      missionCount: 6,
      budget: 'free',
    });

    expect(prompt).toContain('Aprender inglés');
    expect(prompt).toContain('90 días');
    expect(prompt).toContain('exactamente 6 misiones');
    expect(prompt).toContain('free');
  });

  it('el prompt de sugerencias pide no repetir lo que ya existe', () => {
    // Sin esta parte, la segunda tanda de sugerencias repite la primera.
    const prompt = buildSuggestMissionsPrompt({
      goalTitle: 'Correr 5k',
      categoryId: 'fitness',
      existingTitles: ['Trotar 20 minutos'],
      missionCount: 3,
      budget: 'free',
    });

    expect(prompt).toContain('NO las repitas');
    expect(prompt).toContain('Trotar 20 minutos');
  });

  it('la versión del prompt está fijada para poder auditarla', () => {
    // Se guarda en `aiJobs`: sin versión, un cambio de prompt es imposible de
    // correlacionar con un cambio de calidad.
    expect(GOAL_PLAN_PROMPT_VERSION).toMatch(/^goal_plan_v\d+$/);
  });
});
