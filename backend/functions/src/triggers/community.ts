import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
} from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, LIMITS, REGION } from '../config/constants';
import {
  asInt,
  asMap,
  asNullableString,
  asString,
} from '../lib/firestore-values';
import { deliver } from '../lib/notifications';
import {
  groupKeyFor,
  groupedSocialBody,
} from '../services/notification-service';

/**
 * Triggers de la comunidad.
 *
 * Todos comparten el mismo principio: **los contadores y la moderación son del
 * servidor**. Las reglas rechazan `counters`, `moderation` y `author` en las
 * escrituras del cliente; estos triggers son quienes los mantienen.
 *
 * Sin esto, cualquiera se pondría mil "me gusta" y se autoaprobaría contenido.
 */

/**
 * Completa el autor desnormalizado y actualiza el contador de publicaciones.
 *
 * El autor se copia dentro del post para que pintar el feed no cueste una
 * lectura de perfil por publicación: 20 posts serían 21 lecturas en vez de 40.
 * Se lee de `publicProfiles` y no de `users`, que tiene email y ajustes
 * privados.
 */
export const onPostCreate = onDocumentCreated(
  { document: `${COLLECTIONS.posts}/{postId}`, region: REGION },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }

    const data = snapshot.data();
    const authorId = typeof data.authorId === 'string' ? data.authorId : null;
    if (!authorId) {
      logger.warn('Publicación sin autor', { postId: event.params.postId });
      return;
    }

    const db = getFirestore();

    try {
      const profileSnap = await db
        .collection(COLLECTIONS.publicProfiles)
        .doc(authorId)
        .get();
      // `data()` devuelve `DocumentData`, cuyos valores son `any`. Se acotan a
      // `unknown` y se estrechan antes de usarlos: el linter del proyecto
      // rechaza asignaciones `any` justamente para que esto no pase inadvertido.
      const profile = (profileSnap.data() ?? {}) as Record<string, unknown>;

      await snapshot.ref.set(
        {
          author: {
            displayName: asString(profile.displayName),
            handle: asString(profile.handle),
            photoUrl: asNullableString(profile.photoUrl),
            level: asInt(profile.level, 1),
          },
          counters: { likes: 0, comments: 0, reports: 0 },
          // La moderación por IA llega en una fase posterior. Hasta entonces el
          // contenido nace visible y el sistema de reportes lo cubre: es lo
          // mismo que hace cualquier red social sin moderación previa.
          moderation: { status: 'visible', aiScore: null, reviewedBy: null },
        },
        { merge: true },
      );

      await db
        .collection(COLLECTIONS.users)
        .doc(authorId)
        .set(
          { stats: { postsCount: FieldValue.increment(1) } },
          { merge: true },
        );
    } catch (error) {
      logger.error('Falló el enriquecido de la publicación', {
        postId: event.params.postId,
        error,
      });
      throw error;
    }
  },
);

/** Mantiene `stats.postsCount` al borrar. */
export const onPostDelete = onDocumentDeleted(
  { document: `${COLLECTIONS.posts}/{postId}`, region: REGION },
  async (event) => {
    const data = (event.data?.data() ?? {}) as Record<string, unknown>;
    const authorId = data.authorId;
    if (typeof authorId !== 'string') {
      return;
    }
    await getFirestore()
      .collection(COLLECTIONS.users)
      .doc(authorId)
      .set(
        { stats: { postsCount: FieldValue.increment(-1) } },
        { merge: true },
      );
  },
);

/**
 * Mantiene el contador de "me gusta".
 *
 * Usa `onDocumentWritten` y no `onCreate`/`onDelete` separados porque el
 * documento de like tiene el uid como id: alta y baja son el mismo documento
 * apareciendo y desapareciendo, y tratarlas juntas evita que un doble toque
 * rápido descuadre el contador.
 */
export const onLikeWrite = onDocumentWritten(
  {
    document: `${COLLECTIONS.posts}/{postId}/${COLLECTIONS.likes}/{uid}`,
    region: REGION,
  },
  async (event) => {
    const existedBefore = event.data?.before.exists ?? false;
    const existsAfter = event.data?.after.exists ?? false;

    // Ni alta ni baja: una reescritura del mismo like no mueve el contador.
    if (existedBefore === existsAfter) {
      return;
    }

    const delta = existsAfter ? 1 : -1;
    await getFirestore()
      .collection(COLLECTIONS.posts)
      .doc(event.params.postId)
      .set(
        { counters: { likes: FieldValue.increment(delta) } },
        { merge: true },
      );

    // Solo se avisa al dar el like, no al quitarlo: "a alguien dejó de
    // gustarle tu publicación" no es una notificación, es una crueldad.
    if (existsAfter) {
      await notifySocial({
        type: 'new_like',
        postId: event.params.postId,
        actorUid: event.params.uid,
      });
    }
  },
);

/** Mantiene el contador de comentarios. */
export const onCommentWrite = onDocumentWritten(
  {
    document: `${COLLECTIONS.posts}/{postId}/${COLLECTIONS.comments}/{commentId}`,
    region: REGION,
  },
  async (event) => {
    const existedBefore = event.data?.before.exists ?? false;
    const existsAfter = event.data?.after.exists ?? false;
    if (existedBefore === existsAfter) {
      return;
    }

    const delta = existsAfter ? 1 : -1;
    await getFirestore()
      .collection(COLLECTIONS.posts)
      .doc(event.params.postId)
      .set(
        { counters: { comments: FieldValue.increment(delta) } },
        { merge: true },
      );

    if (existsAfter) {
      const authorUid = asNullableString(event.data?.after.get('authorId'));
      if (authorUid !== null) {
        await notifySocial({
          type: 'new_comment',
          postId: event.params.postId,
          actorUid: authorUid,
        });
      }
    }
  },
);

/**
 * Cuenta reportes y oculta el contenido de forma preventiva.
 *
 * A partir de tres reportes el post pasa a `under_review` y desaparece del
 * feed. Ocultar primero y revisar después es lo correcto: el daño de dejar
 * visible algo abusivo unas horas supera al de ocultar algo legítimo por error,
 * que se revierte desde el panel.
 *
 * El id determinístico del reporte —`{targetId}_{reporterId}`— garantiza que
 * los tres sean de **tres personas distintas**: la misma no puede reportar dos
 * veces, porque sobrescribiría su propio documento.
 */
export const onReportCreate = onDocumentCreated(
  { document: `${COLLECTIONS.reports}/{reportId}`, region: REGION },
  async (event) => {
    const data = event.data?.data();
    const target = (data?.target ?? {}) as Record<string, unknown>;
    const targetId = typeof target.id === 'string' ? target.id : null;
    const targetType = typeof target.type === 'string' ? target.type : 'post';

    if (!targetId || targetType !== 'post') {
      return;
    }

    const db = getFirestore();
    const postRef = db.collection(COLLECTIONS.posts).doc(targetId);

    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(postRef);
        if (!snap.exists) {
          return;
        }

        const counters = (snap.data()?.counters ?? {}) as Record<
          string,
          unknown
        >;
        const reports =
          (typeof counters.reports === 'number' ? counters.reports : 0) + 1;

        const moderation = (snap.data()?.moderation ?? {}) as Record<
          string,
          unknown
        >;
        const alreadyHidden = moderation.status !== 'visible';

        tx.set(
          postRef,
          {
            counters: { reports },
            ...(reports >= LIMITS.reportsToAutoHide && !alreadyHidden
              ? { moderation: { status: 'under_review' } }
              : {}),
          },
          { merge: true },
        );
      });
    } catch (error) {
      logger.error('Falló el procesamiento de un reporte', { targetId, error });
      throw error;
    }
  },
);

/**
 * Avisa al autor de una publicación, agrupando la actividad del día.
 *
 * ## Por qué se agrupa
 *
 * Cincuenta likes en la misma publicación tienen que producir **una**
 * notificación que diga "50 personas", no cincuenta. Sin agrupar, la
 * publicación que mejor funciona se convierte en un castigo para su autor — y
 * en la razón por la que apaga las notificaciones para siempre, perdiendo
 * también las que sí le servían.
 *
 * La agrupación se logra con un **id determinístico** por tipo, publicación y
 * día: la segunda entrega sobrescribe a la primera con el contador
 * actualizado, en vez de apilarse. El día forma parte de la clave para que el
 * contador no crezca indefinidamente y cada jornada vuelva a sentirse nueva.
 *
 * Nunca lanza: el contador del post ya se actualizó y no puede deshacerse
 * porque el aviso falle.
 */
async function notifySocial(input: {
  type: 'new_like' | 'new_comment';
  postId: string;
  actorUid: string;
}): Promise<void> {
  try {
    const db = getFirestore();
    const postSnap = await db
      .collection(COLLECTIONS.posts)
      .doc(input.postId)
      .get();

    const authorUid = asNullableString(postSnap.get('authorId'));
    // Nadie recibe una notificación por su propia acción.
    if (authorUid === null || authorUid === input.actorUid) {
      return;
    }

    const counters = asMap(postSnap.get('counters'));
    const count = asInt(
      input.type === 'new_like' ? counters.likes : counters.comments,
      1,
    );

    const actorSnap = await db
      .collection(COLLECTIONS.publicProfiles)
      .doc(input.actorUid)
      .get();
    const actorName = asNullableString(actorSnap.get('displayName'));

    const dayKey = new Date().toISOString().slice(0, 10);
    const groupKey = groupKeyFor(input.type, input.postId, dayKey);

    await deliver({
      uid: authorUid,
      type: input.type,
      title: input.type === 'new_like' ? 'Nuevo me gusta' : 'Nuevo comentario',
      body: groupedSocialBody(input.type, count, actorName),
      data: { route: `/community/${input.postId}`, postId: input.postId },
      notificationId: groupKey ?? undefined,
      ttlDays: 14,
    });
  } catch (error) {
    logger.warn('No se pudo avisar de la actividad social', {
      postId: input.postId,
      type: input.type,
      error,
    });
  }
}
