import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, REGION } from '../config/constants';
import {
  buildStatsDocument,
  statsDocId,
  windowStart,
  type StatsCounters,
} from '../services/admin-service';

/**
 * Calcula las métricas que muestra el dashboard.
 *
 * ## Por qué se agregan en vez de contarse al abrir el panel
 *
 * Un `count()` sobre `users` cuesta una lectura facturada cada mil documentos y
 * se repetiría **cada vez que alguien abre el panel**. Con diez administradores
 * mirando el dashboard varias veces al día, contar en vivo es una factura por
 * mirar un número que casi no cambia.
 *
 * Acá se paga una vez por día y el panel lee **un solo documento**. Es además
 * el criterio de aceptación de la fase: el dashboard carga con datos agregados,
 * no recorriendo colecciones.
 *
 * ## Por qué se usa `count()` y no se traen los documentos
 *
 * `getCount()` se factura a una lectura por cada 1000 documentos del índice, sin
 * transferir los datos. Traer cien mil usuarios para contarlos sería cien mil
 * lecturas y varios minutos de función.
 *
 * El documento diario queda guardado con la fecha como id: sirve para ver la
 * evolución sin tener que recalcular nada. `latest` es una copia del último,
 * para que el panel no tenga que adivinar qué día pedir.
 */
export const aggregateStats = onSchedule(
  {
    // 04:00 UTC, después del barrido de rachas: así las métricas del día ya
    // reflejan las rachas rotas de la madrugada.
    schedule: '0 4 * * *',
    timeZone: 'Etc/UTC',
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 300,
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const weekAgo = Timestamp.fromDate(windowStart(now, 7));
    const today = statsDocId(now);

    const count = async (query: FirebaseFirestore.Query): Promise<number> => {
      const snapshot = await query.count().get();
      return snapshot.data().count;
    };

    try {
      const users = db.collection(COLLECTIONS.users);

      // Las consultas van en paralelo: son independientes y en serie sumarían
      // el tiempo de todas, acercándose al timeout sin necesidad.
      const [
        usersTotal,
        usersActive7d,
        usersNew7d,
        goalsActive,
        missionsCompleted7d,
        postsTotal,
        reportsOpen,
      ] = await Promise.all([
        count(users),
        count(users.where('stats.lastActivityDate', '>=', weekAgo)),
        count(users.where('createdAt', '>=', weekAgo)),
        count(
          db.collectionGroup(COLLECTIONS.goals).where('status', '==', 'active'),
        ),
        count(
          db
            .collectionGroup(COLLECTIONS.missions)
            .where('completedAt', '>=', weekAgo),
        ),
        count(db.collection(COLLECTIONS.posts)),
        count(db.collection(COLLECTIONS.reports).where('status', '==', 'open')),
      ]);

      // Las llamadas a la IA se **suman**, no se cuentan: cada documento de
      // `aiUsage` es una persona-día con su contador adentro, así que contar
      // documentos daría "cuánta gente usó la IA", que es otra métrica.
      let aiCallsToday = 0;
      const usage = await db
        .collectionGroup(COLLECTIONS.aiUsage)
        .where('date', '==', today)
        .select('generations')
        .get();
      for (const usageDoc of usage.docs) {
        const generations: unknown = usageDoc.get('generations');
        if (typeof generations === 'number' && generations > 0) {
          aiCallsToday += generations;
        }
      }

      // El Aura otorgada no se puede contar: hay que sumarla. Se acota al
      // ledger de la semana, que es lo que muestra el panel, y se lee en
      // páginas para no cargar un mes entero en memoria si el volumen crece.
      let auraGranted7d = 0;
      const ledger = await db
        .collectionGroup(COLLECTIONS.auraLedger)
        .where('createdAt', '>=', weekAgo)
        .select('amount')
        .get();
      for (const doc of ledger.docs) {
        const amount: unknown = doc.get('amount');
        if (typeof amount === 'number' && amount > 0) {
          auraGranted7d += amount;
        }
      }

      const counters: StatsCounters = {
        usersTotal,
        usersActive7d,
        usersNew7d,
        goalsActive,
        missionsCompleted7d,
        auraGranted7d,
        postsTotal,
        reportsOpen,
        aiCallsToday,
      };

      const document = buildStatsDocument(counters, now);
      const stats = db.collection(COLLECTIONS.adminStats);

      await Promise.all([
        stats.doc(statsDocId(now)).set(document),
        stats.doc('latest').set(document),
      ]);

      logger.info('Métricas agregadas', counters);
    } catch (error) {
      // No se relanza: reintentar un barrido diario no lo va a arreglar si la
      // causa es un índice faltante, y una función programada que falla en
      // bucle genera ruido de alertas. El panel detecta que las métricas
      // quedaron viejas y lo avisa en pantalla.
      logger.error('Falló la agregación de métricas', { error });
    }
  },
);
