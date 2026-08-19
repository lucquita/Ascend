/**
 * Lectura defensiva de documentos de Firestore.
 *
 * `snapshot.data()` devuelve `any`. Cada campo que se toca sin comprobar es una
 * suposición sobre datos que escribió otra versión del cliente, posiblemente
 * vieja, posiblemente rota. Estos helpers convierten esa suposición en un valor
 * con tipo y un valor por defecto explícito.
 *
 * El coste de no hacerlo es concreto: un `undefined` que se cuela en una
 * plantilla se escribe como `"undefined"` en la base y queda ahí para siempre.
 */

/** Texto, o cadena vacía si el campo falta o no es texto. */
export function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

/** Texto no vacío, o `null`. */
export function asNullableString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

/** Entero, o [fallback] si el campo falta, no es número o es `NaN`. */
export function asInt(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.floor(value)
    : fallback;
}

/** Objeto plano, o `{}` si el campo falta o no es un objeto. */
export function asMap(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}
