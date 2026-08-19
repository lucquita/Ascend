import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, DEFAULT_RUNTIME } from '../config/constants';
import { invalidArgument, requireAdmin } from '../lib/admin-guard';
import { asMap, asNullableString, asString } from '../lib/firestore-values';
import { moderateContentSchema } from '../lib/validation';
import {
  checkModeration,
  hidesContent,
  resolvedStatus,
} from '../services/admin-service';

/**
 * Resuelve un reporte de la bandeja de moderación.
 *
 * ## Por qué es una función y no una escritura del panel
 *
 * Las reglas le permitirían al administrador actualizar el reporte y ocultar la
 * publicación directamente desde el cliente. Pero `auditLog` es **inescribible
 * desde cualquier cliente**, y el requisito es que toda acción administrativa
 * quede registrada. Con dos escrituras separadas —una del panel, otra del
 * servidor— siempre existe el caso en que la primera funciona y la segunda no:
 * queda una publicación oculta sin rastro de quién la ocultó.
 *
 * Acá las tres escrituras —reporte, contenido y auditoría— van en un solo
 * `batch`: o quedan las tres o no queda ninguna.
 */
export const moderateContent = onCall(
  { ...DEFAULT_RUNTIME, enforceAppCheck: true },
  async (request) => {
    const actorUid = requireAdmin(request, 'moderate_content');

    const parsed = moderateContentSchema.safeParse(request.data);
    if (!parsed.success) {
      throw invalidArgument(parsed.error.issues[0]?.message);
    }

    const { reportId, action, note } = parsed.data;
    const db = getFirestore();
    const reportRef = db.collection(COLLECTIONS.reports).doc(reportId);

    try {
      const snapshot = await reportRef.get();
      if (!snapshot.exists) {
        throw new HttpsError('not-found', 'Ese reporte no existe.');
      }

      const report = asMap(snapshot.data());
      const target = asMap(report.target);
      const targetType = asString(target.type);
      const targetId = asString(target.id);
      const targetOwnerId = asNullableString(target.ownerId);

      const check = checkModeration({
        action,
        note,
        targetType,
        reportStatus: asString(report.status, 'open'),
      });
      if (!check.ok) {
        throw new HttpsError(
          check.code === 'already-closed'
            ? 'failed-precondition'
            : 'invalid-argument',
          {
            'already-closed': 'Ese reporte ya estaba resuelto.',
            'unknown-target': 'No sabemos moderar ese tipo de contenido.',
            'note-required': 'Escribí el motivo de la suspensión.',
          }[check.code],
        );
      }

      if (action === 'suspend_author' && targetOwnerId === actorUid) {
        throw new HttpsError(
          'failed-precondition',
          'No podés suspender tu propia cuenta.',
        );
      }

      const batch = db.batch();

      batch.update(reportRef, {
        status: resolvedStatus(action),
        resolvedBy: actorUid,
        resolvedAt: FieldValue.serverTimestamp(),
        resolution: action,
        note: note ?? null,
      });

      if (hidesContent(action)) {
        const collection =
          targetType === 'post' ? COLLECTIONS.posts : COLLECTIONS.comments;
        // Los comentarios cuelgan de una publicación, así que solo se pueden
        // direccionar por `collectionGroup`. Se resuelve abajo para no
        // adivinar la ruta del padre.
        if (targetType === 'post') {
          batch.set(
            db.collection(collection).doc(targetId),
            {
              moderation: {
                status: 'hidden',
                reviewedBy: actorUid,
                reviewedAt: FieldValue.serverTimestamp(),
              },
            },
            { merge: true },
          );
        } else {
          const comment = await db
            .collectionGroup(COLLECTIONS.comments)
            .where('id', '==', targetId)
            .limit(1)
            .get();
          const found = comment.docs[0];
          if (found) {
            batch.set(
              found.ref,
              {
                moderation: {
                  status: 'hidden',
                  reviewedBy: actorUid,
                  reviewedAt: FieldValue.serverTimestamp(),
                },
              },
              { merge: true },
            );
          } else {
            // El contenido ya no existe: el reporte igual se cierra, porque
            // dejarlo abierto haría que alguien vuelva a revisarlo para nada.
            logger.warn('Contenido reportado inexistente', {
              targetType,
              targetId,
            });
          }
        }
      }

      batch.set(db.collection(COLLECTIONS.auditLog).doc(), {
        action: 'resolve_report',
        actorUid,
        targetId,
        targetUid: targetOwnerId,
        resolution: action,
        note: note ?? null,
        createdAt: FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // La suspensión va después del batch y no dentro: toca Auth, que no
      // participa de una transacción de Firestore. Si fallara, el reporte
      // queda resuelto y el contenido oculto —el efecto principal— y la
      // suspensión se puede reintentar desde la ficha de la persona.
      if (action === 'suspend_author' && targetOwnerId !== null) {
        const user = await getAuth().getUser(targetOwnerId);
        const role = (user.customClaims?.role as string | undefined) ?? 'user';
        await getAuth().setCustomUserClaims(targetOwnerId, {
          role,
          status: 'suspended',
        });
        await getAuth().revokeRefreshTokens(targetOwnerId);
        await db.collection(COLLECTIONS.users).doc(targetOwnerId).set(
          {
            status: 'suspended',
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      logger.info('Reporte resuelto', { actorUid, reportId, action });
      return { reportId, action, status: resolvedStatus(action) };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error('Falló la moderación', { actorUid, reportId, error });
      throw new HttpsError('internal', 'No pudimos resolver el reporte.');
    }
  },
);
