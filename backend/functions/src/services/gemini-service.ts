import { logger } from 'firebase-functions/v2';
import { SYSTEM_INSTRUCTION } from '../config/prompts';

/**
 * Cliente de la API de Gemini. **ADR-002: solo el servidor la llama.**
 *
 * La API key se lee de Secret Manager y jamás sale de acá. Si el cliente Flutter
 * la invocara directo, la key viajaría dentro del binario: un APK se descompila
 * en cinco minutos, y en web está literalmente en el JS servido. El modo de
 * fallo típico es una factura de miles de dólares en 48 horas.
 *
 * Se usa `fetch` contra la API REST en lugar del SDK oficial para no sumar una
 * dependencia por una sola llamada HTTP. Node 20 trae `fetch` global.
 */

/** Modelo por defecto. Se puede cambiar sin publicar una versión de la app. */
export const DEFAULT_MODEL = 'gemini-2.0-flash';

/** Cuánto se espera antes de abandonar la generación. */
export const GENERATION_TIMEOUT_MS = 45_000;

/** Uso de tokens de una llamada, para poder auditar el costo. */
export interface TokenUsage {
  readonly promptTokens: number;
  readonly outputTokens: number;
}

/** Respuesta cruda del modelo, ya desempaquetada. */
export interface GenerationResult {
  readonly text: string;
  readonly usage: TokenUsage;
  readonly latencyMs: number;
}

/** Error tipado de la llamada al modelo. */
export class GeminiError extends Error {
  constructor(
    readonly reason:
      | 'no-api-key'
      | 'timeout'
      | 'rate-limited'
      | 'blocked'
      | 'empty-response'
      | 'http-error',
    message: string,
  ) {
    super(message);
    this.name = 'GeminiError';
  }
}

/**
 * Genera contenido estructurado.
 *
 * @param apiKey Clave leída de Secret Manager. Nunca se registra en logs.
 */
export async function generateStructured(params: {
  apiKey: string | undefined;
  prompt: string;
  responseSchema: unknown;
  model?: string;
  timeoutMs?: number;
}): Promise<GenerationResult> {
  const { apiKey, prompt, responseSchema } = params;
  const model = params.model ?? DEFAULT_MODEL;
  const timeoutMs = params.timeoutMs ?? GENERATION_TIMEOUT_MS;

  // Sin key no se intenta la llamada: fallar rápido y con un motivo claro
  // permite que la app ofrezca las plantillas de reserva en vez de esperar un
  // timeout de 45 segundos para terminar mostrando "algo salió mal".
  if (!apiKey) {
    throw new GeminiError(
      'no-api-key',
      'GEMINI_API_KEY no está configurada en Secret Manager.',
    );
  }

  const started = Date.now();
  // Un `AbortController` acota la espera: sin esto, una llamada colgada
  // consumiría los 120 s de la función y la persona miraría un spinner hasta
  // que el runtime la mate.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          // En el header, no en la URL: una key en el query string queda en los
          // logs de acceso de cualquier proxy intermedio.
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: {
            responseMimeType: 'application/json',
            responseSchema,
            temperature: 0.7,
          },
        }),
      },
    );

    if (!response.ok) {
      const reason = response.status === 429 ? 'rate-limited' : 'http-error';
      // El cuerpo del error NO se registra completo: puede incluir el prompt y,
      // en algunos formatos de error, fragmentos de la petición.
      throw new GeminiError(reason, `Gemini respondió ${response.status}`);
    }

    const body = (await response.json()) as GeminiResponse;
    const candidate = body.candidates?.[0];

    // `SAFETY` significa que el modelo se negó por sus filtros. No es un error
    // técnico y no tiene sentido reintentarlo.
    if (candidate?.finishReason === 'SAFETY') {
      throw new GeminiError('blocked', 'El modelo bloqueó la respuesta.');
    }

    const text = candidate?.content?.parts?.[0]?.text;
    if (!text) {
      throw new GeminiError(
        'empty-response',
        'Gemini devolvió una respuesta vacía.',
      );
    }

    return {
      text,
      usage: {
        promptTokens: body.usageMetadata?.promptTokenCount ?? 0,
        outputTokens: body.usageMetadata?.candidatesTokenCount ?? 0,
      },
      latencyMs: Date.now() - started,
    };
  } catch (error) {
    if (error instanceof GeminiError) {
      throw error;
    }
    if (error instanceof Error && error.name === 'AbortError') {
      throw new GeminiError(
        'timeout',
        `Gemini no respondió en ${timeoutMs} ms.`,
      );
    }
    logger.error('Falló la llamada a Gemini', { model });
    throw new GeminiError('http-error', 'No se pudo contactar a Gemini.');
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Costo estimado en dólares de una generación.
 *
 * Los precios cambian; la constante está acá para poder ajustarla en un solo
 * lugar. Lo que importa es que **quede registrado por generación**: sin esto no
 * se puede responder cuánto cuesta la IA por usuario activo.
 */
export function estimateCostUsd(usage: TokenUsage): number {
  const inputPerMillion = 0.1;
  const outputPerMillion = 0.4;
  return (
    (usage.promptTokens / 1_000_000) * inputPerMillion +
    (usage.outputTokens / 1_000_000) * outputPerMillion
  );
}

interface GeminiResponse {
  readonly candidates?: readonly {
    readonly finishReason?: string;
    readonly content?: {
      readonly parts?: readonly { readonly text?: string }[];
    };
  }[];
  readonly usageMetadata?: {
    readonly promptTokenCount?: number;
    readonly candidatesTokenCount?: number;
  };
}
