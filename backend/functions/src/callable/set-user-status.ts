import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, DEFAULT_RUNTIME } from '../config/constants';
import { invalidArgument, requireAdmin } from '../lib/admin-guard';
import { setUserStatusSchema } from '../lib/validation';

/**
 * Suspende o reactiva una cuenta.
 *
 * La suspensión vive en un **custom claim**, igual que el rol, porque las
 * reglas de Firestore la comprueban en cada escritura (`isActive()`). Si viviera
 * solo en el documento del usuario, la persona suspendida podría reactivarse
 * editando su propio perfil.
 *
 * Se espeja además en `users/{uid}.status` para que el panel pueda listar y
 * filtrar sin inspeccionar tokens, pero la autoridad es el claim.
 *
 * ## Por qué el motivo es obligatorio
 *
 * Suspender es la acción más grave del panel. Sin motivo escrito, un mes
 * después nadie —ni quien la aplicó— puede explicar por qué esa cuenta está
 * bloqueada, y la única salida es levantarla a ciegas.
 */
export const setUserStatus = onCall(
  { ...DEFAULT_RUNTIME, enforceAppCheck: true },
  async (request) => {
    const actorUid = requireAdmin(request, 'set_user_status');

    const parsed = setUserStatusSchema.safeParse(request.data);
    if (!parsed.success) {
      throw invalidArgument(parsed.error.issues[0]?.message);
    }

    const { targetUid, status, reason } = parsed.data;

    if (targetUid === actorUid) {
      throw new HttpsError(
        'failed-precondition',
        'No podés suspender tu propia cuenta.',
      );
    }
    if (status === 'suspended' && (reason ?? '').trim().length < 5) {
      throw new HttpsError(
        'invalid-argument',
        'Escribí el motivo de la suspensión.',
      );
    }

    const db = getFirestore();

    try {
      const target = await getAuth().getUser(targetUid);
      const previousStatus =
        (target.customClaims?.status as string | undefined) ?? 'active';
      const role = (target.customClaims?.role as string | undefined) ?? 'user';

      if (previousStatus === status) {
        // No es un error, pero tampoco hay que registrar una acción que no
        // cambió nada: ensuciaría la auditoría con ruido.
        return { targetUid, status, changed: false };
      }

      // Se preserva `role`: escribir los claims reemplaza el objeto entero, así
      // que omitirlo degradaría a un administrador sin querer.
      await getAuth().setCustomUserClaims(targetUid, { role, status });

      await db
        .collection(COLLECTIONS.users)
        .doc(targetUid)
        .set(
          { status, updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );

      await db.collection(COLLECTIONS.auditLog).add({
        action: 'set_user_status',
        actorUid,
        targetUid,
        previousStatus,
        newStatus: status,
        reason: reason ?? null,
        createdAt: FieldValue.serverTimestamp(),
      });

      // Suspender no cierra la sesión abierta: el token sigue siendo válido
      // hasta que caduque. Se revocan los tokens para que el bloqueo sea
      // inmediato, que es lo que espera quien moderó.
      if (status === 'suspended') {
        await getAuth().revokeRefreshTokens(targetUid);
      }

      logger.info('Estado de cuenta actualizado', {
        actorUid,
        targetUid,
        status,
      });

      return { targetUid, status, previousStatus, changed: true };
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
      logger.error('Falló el cambio de estado', { actorUid, targetUid, error });
      throw new HttpsError('internal', 'No pudimos cambiar el estado.');
    }
  },
);
