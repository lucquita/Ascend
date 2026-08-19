import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, REGION } from '../config/constants';
import { DEFAULT_AURA_RULES, parseAuraRules } from '../config/aura-rules';
import {
  computeMissionAward,
  dayKey,
  ledgerEntryId,
  levelFor,
  nextStreak,
} from '../services/aura-service';

/**
 * Otorga Aura cuando una misión pasa a completada. **Corazón del ADR-003.**
 *
 * El cliente solo escribe `mission.status = 'completed'`; las reglas le impiden
 * tocar `auraReward`, `users.aura` y `auraLedger`. Todo el valor del sistema de
 * gamificación se calcula acá.
 *
 * ## Por qué una transacción
 *
 * Hay que leer el saldo, el asiento previo y el consumo del día, y escribir tres
 * documentos de forma consistente. Sin transacción, dos misiones completadas al
 * mismo tiempo leerían el mismo saldo y una pisaría a la otra: el Aura de una de
 * las dos desaparecería.
 *
 * ## Por qué es idempotente
 *
 * El id del asiento es determinístico (`mission_completed__{missionId}`). Si el
 * asiento ya existe, la transacción no hace nada. Eso cubre los dos casos
 * reales: un doble toque en la interfaz, y el reintento automático del runtime
 * de Functions cuando una ejecución falla a mitad de camino.
 */
export const onMissionWrite = onDocumentUpdated(
  {
    document: `${COLLECTIONS.users}/{uid}/${COLLECTIONS.missions}/{missionId}`,
    region: REGION,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) {
      return;
    }

    // Solo interesa la transición hacia completada. Cualquier otra escritura
    // —editar el título, reordenar— no otorga nada.
    const justCompleted =
      before.status !== 'completed' && after.status === 'completed';
    if (!justCompleted) {
      return;
    }

    const { uid, missionId } = event.params;
    const db = getFirestore();

    const userRef = db.collection(COLLECTIONS.users).doc(uid);
    const entryId = ledgerEntryId('mission_completed', missionId);
    const ledgerRef = userRef.collection(COLLECTIONS.auraLedger).doc(entryId);
    const rulesRef = db.collection(COLLECTIONS.config).doc('auraRules');
    const today = dayKey(new Date());
    const usageRef = userRef.collection('auraUsage').doc(today);

    try {
      await db.runTransaction(async (tx) => {
        const [ledgerSnap, userSnap, rulesSnap, usageSnap] = await Promise.all([
          tx.get(ledgerRef),
          tx.get(userRef),
          tx.get(rulesRef),
          tx.get(usageRef),
        ]);

        // Ya se otorgó por esta misión: no se cobra dos veces.
        if (ledgerSnap.exists) {
          logger.info('Aura ya otorgada por esta misión; se ignora', {
            uid,
            missionId,
          });
          return;
        }

        if (!userSnap.exists) {
          logger.warn('Misión completada de un usuario inexistente', { uid });
          return;
        }

        const rules = rulesSnap.exists
          ? parseAuraRules(rulesSnap.data())
          : DEFAULT_AURA_RULES;

        const userData = userSnap.data() ?? {};
        const aura = (userData.aura ?? {}) as Record<string, unknown>;
        const stats = (userData.stats ?? {}) as Record<string, unknown>;
        const currentTotal = asInt(aura.total);
        const awardedToday = asInt(usageSnap.data()?.awarded);

        const streak = nextStreak({
          lastActivityDay: asNullableString(stats.lastActivityDate),
          today,
          currentStreak: asInt(stats.currentStreak),
        });

        const evidence = after.evidence as Record<string, unknown> | null;
        const hasEvidence =
          !!evidence &&
          (typeof evidence.photoUrl === 'string' ||
            typeof evidence.localPath === 'string');

        const award = computeMissionAward({
          difficulty: after.difficulty,
          streakDays: streak,
          awardedToday,
          hasEvidence,
          rules,
        });

        const newTotal = currentTotal + award.amount;
        const progress = levelFor(newTotal, rules);

        // El asiento se escribe SIEMPRE, incluso con recompensa 0 por tope
        // diario: es lo que vuelve idempotente la operación y deja rastro de
        // que la misión ya se contabilizó.
        tx.set(ledgerRef, {
          id: entryId,
          amount: award.amount,
          balanceAfter: newTotal,
          reason: 'mission_completed',
          ref: { type: 'mission', id: missionId },
          multiplier: award.multiplier,
          note: award.note,
          createdAt: FieldValue.serverTimestamp(),
          createdBy: 'system',
        });

        tx.set(
          usageRef,
          {
            awarded: awardedToday + award.amount,
            missions: FieldValue.increment(1),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        tx.set(
          userRef,
          {
            aura: {
              total: newTotal,
              level: progress.level,
              levelName: progress.levelName,
              xpInLevel: progress.xpInLevel,
              xpForNextLevel: progress.xpForNextLevel,
            },
            stats: {
              missionsCompleted: FieldValue.increment(1),
              currentStreak: streak,
              longestStreak: Math.max(streak, asInt(stats.longestStreak)),
              lastActivityDate: today,
            },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        // La recompensa queda registrada en la propia misión para que la app
        // pueda mostrarla sin leer el ledger.
        tx.set(
          event.data!.after.ref,
          { auraReward: award.amount },
          { merge: true },
        );
      });

      logger.info('Aura otorgada', { uid, missionId });
    } catch (error) {
      // Se relanza para que el runtime reintente: la idempotencia hace que
      // reintentar sea seguro, y perder el Aura de alguien no lo es.
      logger.error('Falló el otorgamiento de Aura', { uid, missionId, error });
      throw error;
    }
  },
);

function asInt(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.floor(value)
    : 0;
}

function asNullableString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}
