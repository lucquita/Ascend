import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

/**
 * Exige que quien llama sea administrador, y devuelve su uid.
 *
 * El rol se lee del **claim del token**, no de Firestore. Un campo en el
 * documento del usuario lo puede escribir esa misma persona; el claim solo lo
 * firma el Admin SDK (ADR-004).
 *
 * Existe como helper porque el chequeo se repite en cada función de
 * administración, y un guard copiado es un guard que alguna vez se copia mal.
 * El intento fallido se registra siempre: alguien probando si puede escalar
 * privilegios no es ruido, es la primera señal de un ataque.
 */
export function requireAdmin(
  request: CallableRequest<unknown>,
  action: string,
): string {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Hay que iniciar sesión.');
  }
  // Rol Y cuenta activa. Suspender a un administrador tiene que quitarle el
  // poder de verdad: si solo se mirara el rol, seguiría moderando y cambiando
  // roles hasta que su token caducara —y la suspensión es precisamente la
  // herramienta para frenar a un administrador que hace daño—.
  const suspended = request.auth.token.status === 'suspended';
  if (request.auth.token.role !== 'admin' || suspended) {
    logger.warn('Acción de administración sin permiso', {
      uid: request.auth.uid,
      action,
      suspended,
    });
    throw new HttpsError(
      'permission-denied',
      'Solo un administrador con la cuenta activa puede hacer esto.',
    );
  }
  return request.auth.uid;
}

/**
 * Traduce un fallo de Zod al error que espera el cliente.
 *
 * Devuelve el primer mensaje y no todos: una llamable no es un formulario, y
 * concatenar cinco mensajes produce un texto que nadie lee.
 */
export function invalidArgument(message: string | undefined): HttpsError {
  return new HttpsError(
    'invalid-argument',
    message ?? 'Los datos no son válidos.',
  );
}
