import { getFirestore } from 'firebase-admin/firestore';
import { onDocumentDeleted } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, REGION } from '../config/constants';

/**
 * Borra en cascada las misiones de un objetivo eliminado.
 *
 * ## Por qué esto NO lo hace el cliente
 *
 * Las reglas permiten al cliente borrar su propio objetivo, pero no pueden
 * obligarlo a borrar también sus misiones. Si lo hiciera la app, bastaría con
 * que se corte la red a mitad del recorrido —o que alguien cierre la pantalla—
 * para que queden misiones apuntando a un `goalId` que ya no existe.
 *
 * Esas misiones huérfanas no son basura inofensiva: la pantalla "Hoy" consulta
 * `users/{uid}/missions` sin filtrar por objetivo (ADR-005), así que seguirían
 * apareciendo como tareas de un objetivo borrado, sin forma de abrirlas ni de
 * eliminarlas.
 *
 * ## Por qué BulkWriter y no una transacción
 *
 * Una transacción de Firestore admite hasta 500 operaciones y exige conocer de
 * antemano todo lo que va a tocar. Un objetivo puede tener cientos de misiones
 * —sobre todo si fueron generadas por IA—. `BulkWriter` procesa por lotes, en
 * paralelo y con reintentos propios.
 *
 * ## Idempotencia
 *
 * Si el trigger se reintenta, las misiones ya borradas simplemente no aparecen
 * en la consulta. Borrar dos veces no es un error.
 */
export const onGoalDelete = onDocumentDeleted(
  {
    document: `${COLLECTIONS.users}/{uid}/${COLLECTIONS.goals}/{goalId}`,
    region: REGION,
  },
  async (event) => {
    const { uid, goalId } = event.params;
    const db = getFirestore();

    const missions = db
      .collection(COLLECTIONS.users)
      .doc(uid)
      .collection(COLLECTIONS.missions)
      .where('goalId', '==', goalId);

    try {
      const snapshot = await missions.get();
      if (snapshot.empty) {
        return;
      }

      const writer = db.bulkWriter();
      for (const doc of snapshot.docs) {
        void writer.delete(doc.ref);
      }
      await writer.close();

      logger.info('Misiones borradas en cascada', {
        uid,
        goalId,
        deleted: snapshot.size,
      });
    } catch (error) {
      // Se relanza para que el runtime reintente: dejar misiones huérfanas es
      // peor que ejecutar el borrado dos veces, que es inofensivo.
      logger.error('Falló el borrado en cascada de un objetivo', {
        uid,
        goalId,
        error,
      });
      throw error;
    }
  },
);
