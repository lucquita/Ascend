import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, REGION } from '../config/constants';
import { dayKey, shouldBreakStreak } from '../services/aura-service';

/**
 * Rompe las rachas que ya se perdieron.
 *
 * ## Por qué hace falta una tarea programada
 *
 * Una racha se pierde por **inacción**, y la inacción no dispara ningún trigger.
 * Sin esto, alguien que dejó de usar la app durante un mes seguiría viendo su
 * racha de 30 días intacta hasta que volviera a completar una misión — y la
 * gamificación perdería el único mecanismo que empuja a volver todos los días.
 *
 * ## Por qué corre una vez al día y no por usuario
 *
 * Programar una tarea por persona sería caro y frágil. Un barrido diario sobre
 * los usuarios con racha activa es más simple y suficiente: la racha se rompe
 * como máximo unas horas después de perderse, y nadie percibe la diferencia.
 *
 * Solo toca a quien tenga `currentStreak > 0`, así que el costo crece con los
 * usuarios activos, no con el total registrado.
 */
export const streakChecker = onSchedule(
  {
    // 03:00 UTC: madrugada en América, de modo que el barrido no cae en el
    // horario de mayor uso.
    schedule: '0 3 * * *',
    timeZone: 'Etc/UTC',
    region: REGION,
    memory: '256MiB',
  },
  async () => {
    const db = getFirestore();
    const today = dayKey(new Date());

    const candidates = await db
      .collection(COLLECTIONS.users)
      .where('stats.currentStreak', '>', 0)
      .get();

    if (candidates.empty) {
      logger.info('Sin rachas activas que revisar');
      return;
    }

    const writer = db.bulkWriter();
    let broken = 0;

    for (const doc of candidates.docs) {
      const stats = (doc.data().stats ?? {}) as Record<string, unknown>;
      const lastActivityDay =
        typeof stats.lastActivityDate === 'string'
          ? stats.lastActivityDate
          : null;
      const currentStreak =
        typeof stats.currentStreak === 'number' ? stats.currentStreak : 0;

      if (!shouldBreakStreak({ lastActivityDay, today, currentStreak })) {
        continue;
      }

      // `longestStreak` NO se toca: es el récord histórico, y perder la racha
      // actual no borra lo que la persona ya logró.
      void writer.set(
        doc.ref,
        {
          stats: { currentStreak: 0 },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      broken++;
    }

    await writer.close();
    logger.info('Rachas revisadas', { revisadas: candidates.size, broken });
  },
);
