import { z } from 'zod';

/**
 * Validación estricta de lo que devuelve el modelo. **Lógica pura.**
 *
 * ## Por qué se revalida si ya se pidió `responseSchema`
 *
 * El schema del proveedor reduce la tasa de error; no la elimina. Un modelo
 * puede devolver un título vacío, una duración de 10.000 minutos o una
 * dificultad inventada, y todo eso pasaría el schema de tipos.
 *
 * Lo que llega de acá se escribe en Firestore como misiones de una persona: si
 * no se valida, la basura del modelo se vuelve datos del producto. Esta es la
 * frontera.
 */

const difficulty = z.enum(['easy', 'medium', 'hard']);
const budget = z.enum(['free', 'low', 'medium', 'high']);

/** Duración máxima aceptada, en minutos. Coincide con el límite del dominio. */
export const MAX_MISSION_MINUTES = 480;

/** Cuántas misiones puede generar una sola llamada. */
export const MAX_GENERATED_MISSIONS = 12;

/** Cuántos hitos puede generar. Coincide con el techo del objetivo. */
export const MAX_GENERATED_MILESTONES = 8;

const generatedMission = z.object({
  title: z.string().trim().min(1).max(80),
  description: z.string().trim().max(300).optional(),
  difficulty,
  budget,
  // Una misión de 0 minutos no es una misión; una de más de 8 horas es otro
  // objetivo disfrazado. Los dos extremos se rechazan.
  estimatedMinutes: z.number().int().min(1).max(MAX_MISSION_MINUTES),
});

const generatedMilestone = z.object({
  title: z.string().trim().min(1).max(80),
});

export const goalPlanSchema = z.object({
  missions: z.array(generatedMission).min(1).max(MAX_GENERATED_MISSIONS),
  milestones: z
    .array(generatedMilestone)
    .max(MAX_GENERATED_MILESTONES)
    .optional(),
});

/** Plan ya validado y listo para escribir. */
export type GoalPlan = z.infer<typeof goalPlanSchema>;

/** Misión generada y validada. */
export type GeneratedMission = z.infer<typeof generatedMission>;

/**
 * Extrae el JSON de la respuesta del modelo.
 *
 * Gemini a veces envuelve el JSON en un bloque de código markdown aunque se le
 * pida `application/json`. Limpiar las cercas antes de parsear evita descartar
 * una respuesta que en realidad era válida.
 */
export function extractJson(raw: string): unknown {
  const trimmed = raw.trim();
  const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/.exec(trimmed);
  const candidate = fenced?.[1] ?? trimmed;

  try {
    return JSON.parse(candidate);
  } catch {
    return null;
  }
}

/** Resultado de validar una respuesta del modelo. */
export type ParseResult =
  | { readonly ok: true; readonly plan: GoalPlan }
  | { readonly ok: false; readonly reason: string };

/**
 * Parsea y valida un plan.
 *
 * Nunca lanza: devuelve el motivo del rechazo para poder registrarlo en
 * `aiJobs` y saber **por qué** falló una generación, no solo que falló.
 */
export function parseGoalPlan(raw: string): ParseResult {
  const json = extractJson(raw);
  if (json === null) {
    return { ok: false, reason: 'malformed-json' };
  }

  const parsed = goalPlanSchema.safeParse(json);
  if (!parsed.success) {
    const first = parsed.error.issues[0];
    return {
      ok: false,
      reason: first
        ? `${first.path.join('.')}: ${first.message}`
        : 'invalid-shape',
    };
  }

  return { ok: true, plan: parsed.data };
}

/**
 * Descarta misiones repetidas dentro de una misma generación.
 *
 * El modelo a veces devuelve la misma acción dos veces con otras palabras. La
 * comparación es por título normalizado: no atrapa todos los casos, pero sí el
 * duplicado literal, que es el frecuente.
 */
export function dedupeMissions(
  missions: readonly GeneratedMission[],
): GeneratedMission[] {
  const seen = new Set<string>();
  const result: GeneratedMission[] = [];

  for (const mission of missions) {
    const key = mission.title.toLowerCase().replace(/\s+/g, ' ').trim();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(mission);
  }

  return result;
}

/**
 * Quita las misiones que superan el presupuesto pedido.
 *
 * El prompt lo pide, pero el modelo no siempre obedece. Devolverle a alguien
 * que dijo "gratis" una misión que cuesta plata es peor que devolverle una
 * misión menos.
 */
export function filterByBudget(
  missions: readonly GeneratedMission[],
  maxBudget: z.infer<typeof budget>,
): GeneratedMission[] {
  const order = ['free', 'low', 'medium', 'high'] as const;
  const ceiling = order.indexOf(maxBudget);
  return missions.filter((m) => order.indexOf(m.budget) <= ceiling);
}
