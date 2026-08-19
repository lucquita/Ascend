/**
 * Cuota diaria de IA. **Lógica pura.**
 *
 * ## Por qué existe
 *
 * Cada generación cuesta dinero real. Sin tope, una sola persona —o un script
 * con su token— puede generar diez mil planes en una tarde y la factura la
 * pagamos nosotros. El límite es de producto además de económico: veinte planes
 * por día es mucho más de lo que cualquiera usa de verdad.
 *
 * ## Por qué se cuenta antes de llamar
 *
 * Reservar la cuota **antes** de la generación y no después: si se contara al
 * terminar, diez peticiones simultáneas verían todas cuota disponible y se
 * ejecutarían las diez.
 */

/** Estado de la cuota de una persona en un día. */
export interface QuotaState {
  readonly used: number;
  readonly limit: number;
}

/** Decisión sobre si una generación puede seguir adelante. */
export interface QuotaDecision {
  readonly allowed: boolean;
  readonly remaining: number;
  readonly reason?: 'daily-limit-reached';
}

/** Evalúa si queda cuota. */
export function checkQuota(state: QuotaState): QuotaDecision {
  const remaining = Math.max(0, state.limit - state.used);
  if (remaining <= 0) {
    return { allowed: false, remaining: 0, reason: 'daily-limit-reached' };
  }
  return { allowed: true, remaining };
}

/**
 * Cuántas generaciones devolver al saldo cuando la llamada falla.
 *
 * Un fallo del proveedor —timeout, 500, respuesta malformada— **no** debe
 * consumir cuota: la persona no recibió nada. Un bloqueo por seguridad del
 * modelo tampoco: no es culpa suya.
 *
 * Se devuelve el crédito en todos los casos salvo el éxito, porque el único
 * escenario en que la cuota se justifica es aquel en el que hubo un plan.
 */
export function shouldRefund(outcome: AiOutcome): boolean {
  return outcome !== 'success';
}

/** Cómo terminó una generación. Se guarda tal cual en `aiJobs`. */
export type AiOutcome =
  'success' | 'failed' | 'rate_limited' | 'invalid_output' | 'blocked';

/** Clave de día (`YYYY-MM-DD`) en UTC. */
export function quotaDayKey(date: Date): string {
  const year = date.getUTCFullYear();
  const month = `${date.getUTCMonth() + 1}`.padStart(2, '0');
  const day = `${date.getUTCDate()}`.padStart(2, '0');
  return `${year}-${month}-${day}`;
}
