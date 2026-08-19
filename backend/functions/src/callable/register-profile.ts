import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { COLLECTIONS, DEFAULT_RUNTIME } from '../config/constants';
import { registerProfileSchema } from '../lib/validation';

/**
 * Crea el perfil de una cuenta recién registrada.
 *
 * ## Por qué esto NO lo hace el cliente
 *
 * Firestore no tiene índices únicos. La única forma de garantizar que dos
 * personas no se queden con el mismo `@handle` es una transacción que lea
 * `handles/{handle}` y lo escriba en el mismo commit. Y `handles` es
 * `write: if false` para el cliente justamente porque, si pudiera escribirlo,
 * podría reservar handles ajenos a voluntad.
 *
 * Además, el rol vive en un custom claim (ADR-004) y un claim solo lo puede
 * asignar el Admin SDK. O sea: el registro necesita un paso de servidor sí o
 * sí. Concentrarlo todo en una única función lo vuelve atómico y auditable.
 *
 * ## Idempotencia
 *
 * El cliente crea la cuenta en Auth y después llama acá. Si el proceso se corta
 * en el medio —se cerró la app, se cayó la red— queda una cuenta de Auth sin
 * perfil. Por eso esta función es idempotente: llamarla de nuevo con el mismo
 * handle completa lo que falte en lugar de fallar. Sin esto, esa persona
 * quedaría con una cuenta inutilizable y sin forma de arreglarla.
 */
export const registerProfile = onCall(
  { ...DEFAULT_RUNTIME, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'Hay que tener una cuenta creada antes de completar el perfil.',
      );
    }

    const { uid, token } = request.auth;

    const parsed = registerProfileSchema.safeParse(request.data);
    if (!parsed.success) {
      const first = parsed.error.issues[0];
      throw new HttpsError(
        'invalid-argument',
        first?.message ?? 'Los datos del perfil no son válidos.',
      );
    }

    const { displayName, handle, locale, timezone } = parsed.data;
    const db = getFirestore();
    const userRef = db.collection(COLLECTIONS.users).doc(uid);
    const handleRef = db.collection(COLLECTIONS.handles).doc(handle);
    const publicRef = db.collection(COLLECTIONS.publicProfiles).doc(uid);

    const email = token.email ?? '';

    try {
      await db.runTransaction(async (tx) => {
        const [handleSnap, userSnap] = await Promise.all([
          tx.get(handleRef),
          tx.get(userRef),
        ]);

        // El handle ya es de otra persona: es el caso que toda esta función
        // existe para frenar.
        if (handleSnap.exists && handleSnap.data()?.uid !== uid) {
          throw new HttpsError(
            'already-exists',
            'Ese nombre de usuario ya está en uso.',
          );
        }

        // Reintento del mismo registro: no se pisa el perfil existente, solo
        // se completa lo que falte. Pisar borraría aura y estadísticas.
        if (userSnap.exists) {
          const existingHandle = userSnap.data()?.handle as string | undefined;
          if (existingHandle && existingHandle !== handle) {
            throw new HttpsError(
              'failed-precondition',
              'Esta cuenta ya tiene un nombre de usuario asignado.',
            );
          }
          if (!handleSnap.exists) {
            tx.set(handleRef, { uid, createdAt: FieldValue.serverTimestamp() });
          }
          return;
        }

        tx.set(handleRef, { uid, createdAt: FieldValue.serverTimestamp() });

        tx.set(userRef, {
          uid,
          email,
          displayName,
          handle,
          photoUrl: null,
          bio: null,
          // Espejo del claim, de solo lectura para el cliente. Existe para
          // poder listar roles en el panel sin leer tokens.
          role: 'user',
          status: 'active',
          locale: locale ?? 'es',
          // Aura y estadísticas nacen en cero y solo las toca el servidor.
          aura: {
            total: 0,
            level: 1,
            levelName: 'Iniciado',
            xpInLevel: 0,
            xpForNextLevel: 100,
          },
          stats: {
            goalsActive: 0,
            goalsCompleted: 0,
            missionsCompleted: 0,
            currentStreak: 0,
            longestStreak: 0,
            postsCount: 0,
            followersCount: 0,
            followingCount: 0,
            lastActivityDate: null,
          },
          settings: {
            themeMode: 'system',
            timezone: timezone ?? 'America/Argentina/Buenos_Aires',
            notifications: {
              dailyReminder: true,
              reminderTime: '20:00',
              streakAlerts: true,
              socialActivity: true,
              aiSuggestions: true,
            },
            privacy: {
              profileVisibility: 'public',
              autoPublishAchievements: false,
              showInLeaderboard: true,
            },
          },
          onboarding: { completed: false, interests: [] },
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          lastLoginAt: FieldValue.serverTimestamp(),
          deletedAt: null,
        });

        // Proyección pública: el feed lee de acá y nunca de /users, que tiene
        // email y ajustes privados.
        tx.set(publicRef, {
          uid,
          displayName,
          handle,
          photoUrl: null,
          bio: null,
          level: 1,
          auraTotal: 0,
          currentStreak: 0,
          goalsCompleted: 0,
          profileVisibility: 'public',
          status: 'active',
          updatedAt: FieldValue.serverTimestamp(),
        });
      });

      // Los claims van fuera de la transacción: Auth no participa de un commit
      // de Firestore. Se aplican siempre —también en el reintento— porque este
      // es justamente el paso que puede haber quedado a medias.
      await getAuth().setCustomUserClaims(uid, {
        role: 'user',
        status: 'active',
      });

      logger.info('Perfil creado', { uid, handle });

      // El cliente tiene que refrescar su token para ver el claim: hasta que no
      // lo haga, su rol sigue sin estar en el token que usan las reglas.
      return { uid, handle, displayName, tokenRefreshRequired: true };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error('Falló la creación del perfil', { uid, handle, error });
      throw new HttpsError(
        'internal',
        'No pudimos crear tu perfil. Probá de nuevo.',
      );
    }
  },
);
