import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { z } from 'zod';
import { AI_RUNTIME, COLLECTIONS, LIMITS } from '../config/constants';
import {
  GOAL_PLAN_PROMPT_VERSION,
  GOAL_PLAN_RESPONSE_SCHEMA,
  buildGoalPlanPrompt,
} from '../config/prompts';
import {
  DEFAULT_MODEL,
  GeminiError,
  estimateCostUsd,
  generateStructured,
} from '../services/gemini-service';
import {
  MAX_GENERATED_MISSIONS,
  dedupeMissions,
  filterByBudget,
  parseGoalPlan,
} from '../services/ai-schemas';
import {
  type AiOutcome,
  checkQuota,
  quotaDayKey,
  shouldRefund,
} from '../services/ai-quota';

const requestSchema = z.object({
  goalTitle: z.string().trim().min(1).max(80),
  categoryId: z.string().trim().min(1).max(40),
  description: z.string().trim().max(500).optional(),
  horizonDays: z.number().int().min(7).max(365).default(90),
  missionCount: z.number().int().min(3).max(MAX_GENERATED_MISSIONS).default(6),
  budget: z.enum(['free', 'low', 'medium', 'high']).default('free'),
});

/**
 * Convierte un objetivo general en un plan de misiones concretas.
 *
 * Es el corazón del ADR-002: el cliente manda el objetivo, el servidor llama a
 * Gemini con la key de Secret Manager y devuelve un plan ya validado. La key
 * nunca sale de acá.
 *
 * ## Qué hace además de generar
 *
 * 1. **Reserva cuota antes de llamar.** Si se contara después, diez peticiones
 *    simultáneas verían cuota libre y se ejecutarían las diez.
 * 2. **Revalida la respuesta** contra un schema propio. Lo que devuelve el
 *    modelo se convierte en misiones de una persona: si no se valida, la basura
 *    del modelo se vuelve datos del producto.
 * 3. **Registra costo y tokens** en `aiJobs`. Sin eso no se puede responder
 *    cuánto cuesta la IA por usuario activo.
 * 4. **Devuelve la cuota si falló.** La persona no recibió nada; cobrarle el
 *    intento sería castigarla por un problema nuestro.
 *
 * **No escribe el objetivo.** Devuelve el plan para que la app lo muestre en una
 * pantalla de revisión editable: la persona confirma o corrige antes de que algo
 * se guarde. Un plan generado que se escribe solo es un plan que nadie leyó.
 */
export const generateGoalPlan = onCall(
  { ...AI_RUNTIME, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Necesitás una sesión activa.');
    }

    const parsed = requestSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError(
        'invalid-argument',
        parsed.error.issues[0]?.message ?? 'Los datos no son válidos.',
      );
    }

    const { uid } = request.auth;
    const input = parsed.data;
    const db = getFirestore();
    const today = quotaDayKey(new Date());
    const usageRef = db
      .collection(COLLECTIONS.users)
      .doc(uid)
      .collection(COLLECTIONS.aiUsage)
      .doc(today);

    // ── 1. Reservar cuota ──────────────────────────────────────────────
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(usageRef);
      const used = asInt(snap.data()?.generations);

      const decision = checkQuota({
        used,
        limit: LIMITS.aiGenerationsPerDay,
      });
      if (!decision.allowed) {
        throw new HttpsError(
          'resource-exhausted',
          `Llegaste a las ${LIMITS.aiGenerationsPerDay} generaciones de hoy.`,
        );
      }

      tx.set(
        usageRef,
        {
          generations: used + 1,
          // El día también va como campo, no solo como id del documento: la
          // agregación diaria consulta por `collectionGroup`, donde el id del
          // documento no se puede filtrar de forma razonable. Sin este campo
          // el panel de costos mostraría cero para siempre.
          date: today,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });

    let outcome: AiOutcome = 'failed';
    let tokensIn = 0;
    let tokensOut = 0;
    let latencyMs = 0;
    let error: string | null = null;

    try {
      // ── 2. Generar ───────────────────────────────────────────────────
      const generation = await generateStructured({
        apiKey: process.env.GEMINI_API_KEY,
        prompt: buildGoalPlanPrompt(input),
        responseSchema: GOAL_PLAN_RESPONSE_SCHEMA,
      });

      tokensIn = generation.usage.promptTokens;
      tokensOut = generation.usage.outputTokens;
      latencyMs = generation.latencyMs;

      // ── 3. Validar ───────────────────────────────────────────────────
      const result = parseGoalPlan(generation.text);
      if (!result.ok) {
        outcome = 'invalid_output';
        error = result.reason;
        throw new HttpsError(
          'internal',
          'El plan generado no era válido. Probá de nuevo.',
        );
      }

      // El presupuesto y los duplicados se corrigen del lado nuestro: el prompt
      // los pide, pero el modelo no siempre obedece.
      const missions = filterByBudget(
        dedupeMissions(result.plan.missions),
        input.budget,
      );

      if (missions.length === 0) {
        outcome = 'invalid_output';
        error = 'todas las misiones excedían el presupuesto';
        throw new HttpsError(
          'internal',
          'El plan generado no respetaba tu presupuesto. Probá de nuevo.',
        );
      }

      outcome = 'success';

      return {
        missions,
        milestones: result.plan.milestones ?? [],
        promptVersion: GOAL_PLAN_PROMPT_VERSION,
        model: DEFAULT_MODEL,
      };
    } catch (caught) {
      if (caught instanceof GeminiError) {
        outcome =
          caught.reason === 'rate-limited'
            ? 'rate_limited'
            : caught.reason === 'blocked'
              ? 'blocked'
              : 'failed';
        error = caught.reason;

        // Cada motivo tiene una salida distinta para la persona. Un genérico
        // "algo salió mal" no le dice si conviene reintentar o escribir el plan
        // a mano.
        throw new HttpsError(
          caught.reason === 'rate-limited'
            ? 'resource-exhausted'
            : 'unavailable',
          caught.reason === 'blocked'
            ? 'No pudimos generar un plan para ese objetivo. Probá reformularlo.'
            : 'La generación no está disponible ahora. Podés armar el plan a mano.',
        );
      }
      if (caught instanceof HttpsError) {
        throw caught;
      }
      error = 'unknown';
      throw new HttpsError('internal', 'No pudimos generar el plan.');
    } finally {
      // ── 4. Auditar y, si hizo falta, devolver la cuota ────────────────
      if (shouldRefund(outcome)) {
        await usageRef
          .set({ generations: FieldValue.increment(-1) }, { merge: true })
          .catch((e: unknown) =>
            logger.error('No se pudo devolver la cuota de IA', { uid, e }),
          );
      }

      await db
        .collection(COLLECTIONS.aiJobs)
        .add({
          uid,
          type: 'goal_plan',
          model: DEFAULT_MODEL,
          promptVersion: GOAL_PLAN_PROMPT_VERSION,
          // Se guarda el input para poder correlacionar calidad con el pedido,
          // no la respuesta completa: sería duplicar lo que ya está en las
          // misiones y multiplicaría el costo de almacenamiento.
          input: {
            goalTitle: input.goalTitle,
            categoryId: input.categoryId,
            horizonDays: input.horizonDays,
          },
          status: outcome,
          tokensIn,
          tokensOut,
          estimatedCostUsd: estimateCostUsd({
            promptTokens: tokensIn,
            outputTokens: tokensOut,
          }),
          latencyMs,
          error,
          createdAt: FieldValue.serverTimestamp(),
        })
        .catch((e: unknown) =>
          logger.error('No se pudo registrar el trabajo de IA', { uid, e }),
        );
    }
  },
);

function asInt(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.floor(value)
    : 0;
}
