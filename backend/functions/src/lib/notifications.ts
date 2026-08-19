import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS } from '../config/constants';
import { asMap, asNullableString } from './firestore-values';
import {
  resolveDelivery,
  localMinutesIn,
  type NotificationPrefs,
  type NotificationType,
} from '../services/notification-service';

/** Una notificación lista para entregar. */
export interface OutgoingNotification {
  uid: string;
  type: NotificationType;
  title: string;
  body: string;
  /** `data.route` es el destino del deep link. */
  data?: Record<string, string>;
  /**
   * Id fijo: dos envíos con el mismo id se pisan en vez de duplicarse.
   *
   * Admite `undefined` explícito —y no solo la ausencia de la propiedad—
   * porque `exactOptionalPropertyTypes` las distingue, y quien la calcula
   * devuelve `null` cuando el tipo no se agrupa.
   */
  notificationId?: string | undefined;
  /** Días que sobrevive en la bandeja antes de que el TTL la borre. */
  ttlDays?: number;
}

/**
 * Entrega una notificación respetando las preferencias de quien la recibe.
 *
 * ## Bandeja primero, push después
 *
 * Siempre se escribe el documento en `users/{uid}/notifications` —salvo que el
 * tipo esté apagado— y recién después se intenta la push. El orden importa: si
 * fuera al revés y la escritura fallara, la persona recibiría un aviso que al
 * tocarlo no lleva a ninguna parte.
 *
 * En horario de silencio se escribe la bandeja y **no** se manda push. La
 * información no se pierde; simplemente no suena el teléfono a las tres de la
 * mañana.
 *
 * ## Nunca lanza
 *
 * La llaman triggers y tareas programadas. Que no se pueda avisar de un like no
 * puede tumbar el trigger que además mantiene los contadores.
 */
export async function deliver(
  notification: OutgoingNotification,
): Promise<void> {
  const db = getFirestore();

  try {
    const userSnap = await db
      .collection(COLLECTIONS.users)
      .doc(notification.uid)
      .get();
    if (!userSnap.exists) {
      return;
    }

    const settings = asMap(userSnap.get('settings'));
    const prefs = asMap(settings.notifications) as NotificationPrefs;
    const timezone =
      asNullableString(settings.timezone) ?? 'America/Argentina/Buenos_Aires';

    const delivery = resolveDelivery(
      notification.type,
      prefs,
      localMinutesIn(timezone, new Date()),
    );

    if (delivery === 'drop') {
      return;
    }

    const inbox = db
      .collection(COLLECTIONS.users)
      .doc(notification.uid)
      .collection(COLLECTIONS.notifications);

    // Con id fijo, dos entregas del mismo hecho se pisan en lugar de apilarse:
    // es lo que hace idempotente al reintento de un trigger.
    const ref = notification.notificationId
      ? inbox.doc(notification.notificationId)
      : inbox.doc();

    const ttlDays = notification.ttlDays ?? 30;
    const expiresAt = new Date();
    expiresAt.setUTCDate(expiresAt.getUTCDate() + ttlDays);

    await ref.set(
      {
        type: notification.type,
        title: notification.title,
        body: notification.body,
        data: notification.data ?? {},
        read: false,
        createdAt: FieldValue.serverTimestamp(),
        // Firestore borra sola la notificación cuando pasa esta fecha (política
        // TTL). Sin eso, la bandeja crece para siempre y se paga el almacenaje
        // de avisos que nadie va a volver a mirar.
        expiresAt,
      },
      { merge: true },
    );

    if (delivery === 'inbox_only') {
      return;
    }

    await sendPush(notification);
  } catch (error) {
    logger.error('No se pudo entregar la notificación', {
      uid: notification.uid,
      type: notification.type,
      error,
    });
  }
}

/**
 * Manda la push a todos los dispositivos registrados y limpia los muertos.
 *
 * Un token deja de valer cuando se desinstala la app o se restaura un backup.
 * Si no se borran, cada envío posterior falla y se sigue pagando el intento;
 * con el tiempo la mayoría de los envíos de una cuenta vieja son a la nada.
 */
async function sendPush(notification: OutgoingNotification): Promise<void> {
  const db = getFirestore();
  const tokensSnap = await db
    .collection(COLLECTIONS.users)
    .doc(notification.uid)
    .collection(COLLECTIONS.fcmTokens)
    .get();

  const tokens = tokensSnap.docs.map((doc) => doc.id);
  if (tokens.length === 0) {
    return;
  }

  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: notification.title, body: notification.body },
    // El payload de datos viaja siempre, incluso con la app cerrada: es lo que
    // permite abrir la pantalla exacta al tocar la push.
    data: { type: notification.type, ...(notification.data ?? {}) },
  });

  const dead: string[] = [];
  response.responses.forEach((result, index) => {
    const code = result.error?.code;
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      const token = tokens[index];
      if (token !== undefined) {
        dead.push(token);
      }
    }
  });

  if (dead.length > 0) {
    const batch = db.batch();
    for (const token of dead) {
      batch.delete(
        db
          .collection(COLLECTIONS.users)
          .doc(notification.uid)
          .collection(COLLECTIONS.fcmTokens)
          .doc(token),
      );
    }
    await batch.commit();
    logger.info('Tokens muertos eliminados', {
      uid: notification.uid,
      count: dead.length,
    });
  }
}
