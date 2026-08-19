/**
 * Prompts versionados.
 *
 * ## Por qué están versionados
 *
 * La calidad de una respuesta depende del prompt tanto como del modelo. Si el
 * prompt cambia sin dejar rastro, es imposible correlacionar "los planes
 * salieron peor esta semana" con nada. Cada generación guarda su
 * `promptVersion` en `aiJobs`, así que un cambio se puede medir contra el
 * anterior.
 *
 * ## Por qué viven en el servidor
 *
 * Un prompt en el cliente se puede leer y manipular: alguien reemplazaría las
 * instrucciones para hacer que el modelo devuelva lo que quiera, y el costo lo
 * pagaríamos nosotros. Además, cambiar un prompt no debería exigir publicar una
 * versión nueva de la app.
 */

/** Versión del prompt de generación de planes. */
export const GOAL_PLAN_PROMPT_VERSION = 'goal_plan_v1';

/** Versión del prompt de sugerencia de misiones sueltas. */
export const SUGGEST_MISSIONS_PROMPT_VERSION = 'suggest_missions_v1';

/**
 * Instrucción de sistema compartida.
 *
 * Fija tres cosas que el producto necesita y el modelo no adivina: que las
 * misiones sean **acciones concretas y verificables**, que quepan en el tiempo
 * real de una persona, y que no prometa resultados que dependen de terceros.
 */
export const SYSTEM_INSTRUCTION = `
Sos el asistente de Ascend, una app de crecimiento personal.
Tu tarea es convertir objetivos generales en acciones concretas.

Reglas que NO podés romper:
1. Cada misión es una acción concreta, verificable y que se hace de una sentada.
   "Estudiar inglés" no sirve. "Ver un capítulo con subtítulos en inglés y
   anotar 5 palabras nuevas" sí.
2. Ninguna misión puede durar más de 8 horas. La mayoría deberían durar entre
   15 y 45 minutos: las misiones largas se postergan y rompen la racha.
3. No prometas resultados que dependen de otras personas o del azar
   ("conseguir un ascenso", "que te respondan"). Proponé lo que la persona
   controla.
4. No des consejo médico, legal ni financiero específico. Si el objetivo entra
   en ese terreno, proponé acciones de informarse y consultar a un profesional.
5. Escribí en español rioplatense, en segunda persona, sin signos de admiración
   de más y sin motivación vacía.
6. Respetá el presupuesto indicado. Si la persona dijo "gratis", ninguna misión
   puede costar dinero.
`.trim();

/** Arma el prompt de generación de un plan completo. */
export function buildGoalPlanPrompt(input: {
  goalTitle: string;
  categoryId: string;
  horizonDays: number;
  missionCount: number;
  budget: string;
  // `| undefined` explícito: el proyecto compila con `exactOptionalPropertyTypes`,
  // así que un opcional no acepta `undefined` a menos que se declare.
  description?: string | undefined;
}): string {
  return `
Objetivo: ${input.goalTitle}
Categoría: ${input.categoryId}
${input.description ? `Contexto: ${input.description}` : ''}
Horizonte: ${input.horizonDays} días
Presupuesto máximo por misión: ${input.budget}

Generá exactamente ${input.missionCount} misiones que, hechas en orden, acerquen
a la persona a ese objetivo. Ordenalas de la más simple a la más exigente.
Sumá entre 2 y 4 hitos que marquen el avance.
`.trim();
}

/** Arma el prompt de sugerencia de misiones para un objetivo que ya existe. */
export function buildSuggestMissionsPrompt(input: {
  goalTitle: string;
  categoryId: string;
  existingTitles: readonly string[];
  missionCount: number;
  budget: string;
}): string {
  const existing = input.existingTitles.length
    ? `\nLa persona ya tiene estas misiones, NO las repitas ni propongas
variantes casi idénticas:\n${input.existingTitles.map((t) => `- ${t}`).join('\n')}`
    : '';

  return `
Objetivo: ${input.goalTitle}
Categoría: ${input.categoryId}
Presupuesto máximo por misión: ${input.budget}${existing}

Proponé exactamente ${input.missionCount} misiones nuevas para este objetivo.
`.trim();
}

/**
 * Esquema de salida que se le exige al modelo.
 *
 * Se manda como `responseSchema` para que Gemini devuelva JSON estructurado en
 * vez de texto libre. Pedir "respondé en JSON" en el prompt no alcanza: el
 * modelo lo rompe cada tanto, y ese "cada tanto" a escala es un error diario.
 * Igual se revalida la respuesta del lado nuestro (ver `ai-schemas.ts`): el
 * schema del proveedor reduce la tasa de error, no la elimina.
 */
export const GOAL_PLAN_RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    missions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          description: { type: 'string' },
          difficulty: { type: 'string', enum: ['easy', 'medium', 'hard'] },
          budget: { type: 'string', enum: ['free', 'low', 'medium', 'high'] },
          estimatedMinutes: { type: 'integer' },
        },
        required: ['title', 'difficulty', 'budget', 'estimatedMinutes'],
      },
    },
    milestones: {
      type: 'array',
      items: {
        type: 'object',
        properties: { title: { type: 'string' } },
        required: ['title'],
      },
    },
  },
  required: ['missions'],
} as const;
