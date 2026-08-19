import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, DEFAULT_RUNTIME } from '../config/constants';

/**
 * Elimina una cuenta y todos sus datos.
 *
 * Google Play y la App Store exigen que la baja se pueda pedir **desde dentro
 * de la app** y que borre de verdad, no que marque un campo. Una app que no lo
 * cumple no pasa revisión.
 *
 * ## Orden de las operaciones
 *
 * Primero los datos, después la cuenta de Auth. Al revés, si el borrado de
 * Firestore fallara a mitad de camino, quedarían documentos huérfanos sin
 * ninguna cuenta desde la cual reintentar la limpieza.
 *
 * El handle se libera para que vuelva a estar disponible. El documento de Auth
 * se borra al final: mientras exista, la persona podría seguir con sesión
 * abierta en otro dispositivo.
 *
 * ## Reautenticación
 *
 * La exige el cliente antes de llamar acá (`reauthenticateWithCredential`). El
 * Admin SDK no la pide, y ese es justamente el riesgo: un token robado no
 * debería alcanzar para borrarle la cuenta a alguien.
 */
export const deleteAccount = onCall(
  { ...DEFAULT_RUNTIME, timeoutSeconds: 300, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Hay que iniciar sesión.');
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    const userRef = db.collection(COLLECTIONS.users).doc(uid);

    try {
      const snapshot = await userRef.get();
      const handle = snapshot.data()?.handle as string | undefined;

      // `recursiveDelete` limpia el documento y todas sus subcolecciones
      // (goals, missions, auraLedger, notificaciones, tokens, seguidores…).
      // Hacerlo a mano implicaría enumerar cada subcolección y olvidarse de
      // una el día que se agregue otra.
      await db.recursiveDelete(userRef);

      const cleanup: Array<Promise<unknown>> = [
        db.collection(COLLECTIONS.publicProfiles).doc(uid).delete(),
      ];
      if (handle) {
        cleanup.push(db.collection(COLLECTIONS.handles).doc(handle).delete());
      }
      await Promise.all(cleanup);

      // Los archivos no se borran solos al borrar los documentos que los
      // referencian: Storage es un sistema aparte.
      try {
        const bucket = getStorage().bucket();
        await Promise.all([
          bucket.deleteFiles({ prefix: `avatars/${uid}/` }),
          bucket.deleteFiles({ prefix: `evidence/${uid}/` }),
          bucket.deleteFiles({ prefix: `posts/${uid}/` }),
        ]);
      } catch (storageError) {
        // Un archivo huérfano cuesta centavos; dejar viva la cuenta de Auth
        // después de que la persona pidió la baja es un incumplimiento legal.
        // Por eso esto no aborta el proceso.
        logger.error('No se pudieron borrar los archivos', {
          uid,
          storageError,
        });
      }

      await getAuth().deleteUser(uid);

      logger.info('Cuenta eliminada', { uid });
      return { deleted: true };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error('Falló la eliminación de la cuenta', { uid, error });
      throw new HttpsError(
        'internal',
        'No pudimos eliminar tu cuenta. Escribinos y lo resolvemos.',
      );
    }
  },
);
