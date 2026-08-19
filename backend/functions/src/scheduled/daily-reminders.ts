import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, REGION } from '../config/constants';
import { deliver } from '../lib/notifications';
import { asInt, asMap, asNullableString } from '../lib/firestore-values';
import {
  dayKeyIn,
  isReminderDue,
  isStreakAtRisk,
  localMinutesIn,
  reminderBody,
  streakWarningBody,
} from '../services/notification-service';

/**
 * Recordatorio diario de misiones, a la hora local de cada persona.
 *
 * ## Por qué corre cada hora y no una vez al día
 *
 * "Las 20:00" no es un momento: es un momento **por zona horaria**. Una tarea
 * diaria a una hora UTC fija le llegaría a la mitad de la gente a media tarde y
 * a la otra mitad de madrugada. Corriendo cada hora en punto y comparando
 * contra la hora local de cada quien, el recordatorio cae en la franja correcta
 * en cualquier huso.
 *
 * La conversión se hace con `Intl` en el momento, no con un desfase guardado:
 * el desfase cambia dos veces al año con el horario de verano, y uno persistido
 * se desactualiza en silencio.
 *
 * ## Por qué no se avisa si no hay nada pendiente
 *
 * Un recordatorio que dice "no tenés nada" es exactamente el tipo de aviso que
 * hace que alguien apague las notificaciones — y cuando las apaga, se pierde
 * también el que sí servía. Solo se envía cuando queda trabajo real.
 *
 * ## Límite conocido
 *
 * Recorre a quienes tienen el recordatorio activo, filtrando por índice. A
 * escala grande convendría desnormalizar la hora UTC del recordatorio en el
 * documento del usuario para consultar solo a quienes les toca; queda anotado.
 */
export const dailyReminders = onSchedule(
  {
    // En punto de cada hora: es la granularidad que declara `isReminderDue`.
    schedule: '0 * * * *',
    timeZone: 'Etc/UTC',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 540,
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const startOfTomorrowUtc = new Date(now);
    startOfTomorrowUtc.setUTCDate(startOfTomorrowUtc.getUTCDate() + 1);

    let sent = 0;
    let scanned = 0;

    try {
      const candidates = await db
        .collection(COLLECTIONS.users)
        .where('settings.notifications.dailyReminder', '==', true)
        .limit(2000)
        .get();

      for (const userDoc of candidates.docs) {
        scanned++;
        const settings = asMap(userDoc.get('settings'));
        const prefs = asMap(settings.notifications);
        const timezone =
          asNullableString(settings.timezone) ??
          'America/Argentina/Buenos_Aires';

        const localMinutes = localMinutesIn(timezone, now);
        if (
          !isReminderDue(
            asNullableString(prefs.reminderTime) ?? '20:00',
            localMinutes,
          )
        ) {
          continue;
        }

        // Se cuenta lo que queda para hoy. `count()` en vez de traer los
        // documentos: solo interesa el número, y traerlos costaría una lectura
        // por misión y por persona en cada corrida.
        const pending = await db
          .collection(COLLECTIONS.users)
          .doc(userDoc.id)
          .collection(COLLECTIONS.missions)
          .where('status', 'in', ['pending', 'in_progress'])
          .where('dueDate', '<', Timestamp.fromDate(startOfTomorrowUtc))
          .count()
          .get();

        const pendingToday = pending.data().count;
        if (pendingToday <= 0) {
          continue;
        }

        // Con una racha viva y ningún movimiento hoy, el aviso que corresponde
        // es el de la racha: es más urgente y respeta su propio interruptor.
        // Mandar los dos sería mandar dos avisos por lo mismo.
        const stats = asMap(userDoc.get('stats'));
        const lastActivity = userDoc.get('stats.lastActivityDate') as unknown;
        const streak = asInt(stats.currentStreak, 0);
        const todayKey = dayKeyIn(timezone, now);
        const atRisk = isStreakAtRisk({
          currentStreak: streak,
          lastActivityDayKey:
            lastActivity instanceof Timestamp
              ? dayKeyIn(timezone, lastActivity.toDate())
              : null,
          todayDayKey: todayKey,
        });

        await deliver({
          uid: userDoc.id,
          type: atRisk ? 'streak_warning' : 'mission_reminder',
          title: atRisk ? 'Tu racha está en juego' : 'Tu día en Ascend',
          body: atRisk ? streakWarningBody(streak) : reminderBody(pendingToday),
          data: { route: '/today' },
          // Id por día: si la tarea se reintenta, la notificación se pisa en
          // lugar de duplicarse.
          notificationId: `reminder__${todayKey}`,
          ttlDays: 2,
        });
        sent++;
      }

      logger.info('Recordatorios diarios enviados', { scanned, sent });
    } catch (error) {
      // No se relanza: reintentar el barrido entero duplicaría los envíos ya
      // hechos en esta corrida, y la próxima hora vuelve a intentar sola.
      logger.error('Falló el barrido de recordatorios', {
        scanned,
        sent,
        error,
      });
    }
  },
);
