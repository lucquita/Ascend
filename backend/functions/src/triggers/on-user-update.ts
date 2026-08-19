import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, REGION } from '../config/constants';

/** Campos del perfil que se proyectan hacia `publicProfiles`. */
interface ProjectedProfile {
  displayName: unknown;
  handle: unknown;
  photoUrl: unknown;
  bio: unknown;
  level: unknown;
  auraTotal: unknown;
  currentStreak: unknown;
  goalsCompleted: unknown;
  profileVisibility: unknown;
  status: unknown;
}

function project(data: FirebaseFirestore.DocumentData): ProjectedProfile {
  const aura = (data.aura ?? {}) as Record<string, unknown>;
  const stats = (data.stats ?? {}) as Record<string, unknown>;
  const privacy = ((data.settings ?? {}) as Record<string, unknown>).privacy as
    Record<string, unknown> | undefined;

  return {
    displayName: data.displayName ?? '',
    handle: data.handle ?? '',
    photoUrl: data.photoUrl ?? null,
    bio: data.bio ?? null,
    level: aura.level ?? 1,
    auraTotal: aura.total ?? 0,
    currentStreak: stats.currentStreak ?? 0,
    goalsCompleted: stats.goalsCompleted ?? 0,
    profileVisibility: privacy?.profileVisibility ?? 'public',
    status: data.status ?? 'active',
  };
}

/**
 * Mantiene sincronizada la proyección pública del perfil.
 *
 * `publicProfiles` existe para que el feed pueda mostrar autores sin abrir
 * permisos de lectura sobre `/users`, que contiene email, ajustes y
 * estadísticas privadas. Al ser una copia, alguien la tiene que mantener: este
 * trigger es ese alguien.
 *
 * Solo escribe cuando cambió algo proyectado. Sin esa comparación, cada
 * `lastLoginAt` —que se actualiza en cada arranque de la app— dispararía una
 * escritura extra por usuario y por sesión. A mil usuarios activos eso es
 * dinero tirado todos los días.
 */
export const onUserUpdate = onDocumentUpdated(
  { document: `${COLLECTIONS.users}/{uid}`, region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) {
      return;
    }

    const uid = event.params.uid;
    const projected = project(after);

    if (before) {
      const previous = project(before);
      const unchanged = (
        Object.keys(projected) as Array<keyof ProjectedProfile>
      ).every((key) => projected[key] === previous[key]);
      if (unchanged) {
        return;
      }
    }

    try {
      await getFirestore()
        .collection(COLLECTIONS.publicProfiles)
        .doc(uid)
        .set(
          { uid, ...projected, updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
    } catch (error) {
      // Un fallo acá degrada la frescura del feed, no la integridad de la
      // cuenta: se registra y se deja que el reintento del runtime lo resuelva.
      logger.error('No se pudo sincronizar el perfil público', { uid, error });
      throw error;
    }
  },
);
