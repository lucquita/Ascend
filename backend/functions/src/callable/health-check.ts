import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { DEFAULT_RUNTIME } from '../config/constants';

/**
 * Comprobación de salud del backend.
 *
 * Sirve para tres cosas concretas:
 *  1. Verificar en la Fase 0 que el despliegue y los emuladores funcionan.
 *  2. Comprobar desde la app que App Check y la autenticación están bien
 *     configurados, antes de que falle una función que sí importa.
 *  3. Darle a la app un modo de detectar mantenimiento programado.
 *
 * Exige autenticación y App Check a propósito: un endpoint abierto es un
 * endpoint que alguien va a usar para medir si el backend está vivo antes de
 * atacarlo.
 */
export const healthCheck = onCall(
  { ...DEFAULT_RUNTIME, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'Hay que iniciar sesión para consultar el estado.',
      );
    }

    const db = getFirestore();

    try {
      const configSnapshot = await db.doc('config/app').get();
      // `data()` devuelve `DocumentData`, cuyos campos son `any`. Acotarlo a
      // `unknown` obliga a comprobar el tipo antes de usarlo, que es lo que
      // corresponde con datos que edita una persona desde el panel.
      const config: Record<string, unknown> = configSnapshot.data() ?? {};
      const minimumVersion = config.minimumSupportedVersion;
      const role: unknown = request.auth.token.role;

      return {
        status: 'ok',
        serverTime: new Date().toISOString(),
        uid: request.auth.uid,
        // `DecodedIdToken` tiene índice abierto: los claims propios entran
        // como `any` y hay que estrecharlos antes de devolverlos.
        role: typeof role === 'string' ? role : 'user',
        maintenanceMode: config.maintenanceMode === true,
        minimumSupportedVersion:
          typeof minimumVersion === 'string' ? minimumVersion : '0.0.0',
      };
    } catch (error) {
      // Nunca se filtra el detalle del error al cliente: solo el código.
      throw new HttpsError(
        'internal',
        'No pudimos consultar el estado del servicio.',
        { cause: error instanceof Error ? error.name : 'unknown' },
      );
    }
  },
);
