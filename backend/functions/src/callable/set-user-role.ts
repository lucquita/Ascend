import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, DEFAULT_RUNTIME } from '../config/constants';
import { setUserRoleSchema } from '../lib/validation';

/**
 * Asigna el rol de una persona. Es la única vía para volverse administrador.
 *
 * ## Por qué el rol vive en un claim y no en Firestore (ADR-004)
 *
 * Si el rol fuera un campo de `users/{uid}`, las reglas tendrían que leerlo con
 * `get()`: una lectura facturada **por cada evaluación de regla**. Y como la
 * persona puede escribir su propio documento, bastaría con ponerse
 * `role: 'admin'` para tomar el panel entero. En el token, en cambio, el rol
 * solo lo firma el Admin SDK.
 *
 * El campo `users/{uid}.role` se mantiene igualmente, pero como **espejo de
 * solo lectura**: sirve para listar y filtrar en el panel sin inspeccionar
 * tokens. La autoridad es siempre el claim.
 *
 * ## Protección contra quedarse afuera
 *
 * Un administrador no puede cambiar su propio rol. Suena restrictivo hasta que
 * alguien se quita el admin por error un viernes y ya no hay forma de
 * recuperarlo desde la app: haría falta un script con credenciales de servicio.
 */
export const setUserRole = onCall(
  { ...DEFAULT_RUNTIME, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Hay que iniciar sesión.');
    }
    if (request.auth.token.role !== 'admin') {
      // Se registra: un intento de escalar privilegios no es ruido.
      logger.warn('Intento de cambiar roles sin permiso', {
        uid: request.auth.uid,
      });
      throw new HttpsError(
        'permission-denied',
        'Solo un administrador puede cambiar roles.',
      );
    }

    const parsed = setUserRoleSchema.safeParse(request.data);
    if (!parsed.success) {
      const first = parsed.error.issues[0];
      throw new HttpsError(
        'invalid-argument',
        first?.message ?? 'Los datos no son válidos.',
      );
    }

    const { targetUid, role, reason } = parsed.data;
    const actorUid = request.auth.uid;

    if (targetUid === actorUid) {
      throw new HttpsError(
        'failed-precondition',
        'No podés cambiar tu propio rol. Pedíselo a otro administrador.',
      );
    }

    const db = getFirestore();
    const userRef = db.collection(COLLECTIONS.users).doc(targetUid);

    try {
      const target = await getAuth().getUser(targetUid);
      const previousRole = (target.customClaims?.role as string) ?? 'user';
      const status = (target.customClaims?.status as string) ?? 'active';

      // Se preserva `status`: escribir los claims reemplaza el objeto entero,
      // así que omitirlo levantaría una suspensión sin querer.
      await getAuth().setCustomUserClaims(targetUid, { role, status });

      await userRef.set(
        { role, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );

      await db.collection(COLLECTIONS.auditLog).add({
        action: 'set_user_role',
        actorUid,
        targetUid,
        previousRole,
        newRole: role,
        reason: reason ?? null,
        createdAt: FieldValue.serverTimestamp(),
      });

      logger.info('Rol actualizado', { actorUid, targetUid, role });

      // El claim viejo sigue vigente en el token de esa persona hasta que
      // caduque o lo refresque: la app fuerza el refresco al arrancar.
      return { targetUid, role, previousRole, tokenRefreshRequired: true };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      if (
        typeof error === 'object' &&
        error !== null &&
        (error as { code?: string }).code === 'auth/user-not-found'
      ) {
        throw new HttpsError('not-found', 'Esa cuenta no existe.');
      }
      logger.error('Falló el cambio de rol', { actorUid, targetUid, error });
      throw new HttpsError('internal', 'No pudimos cambiar el rol.');
    }
  },
);
