/**
 * Constantes compartidas por todas las funciones.
 *
 * La región se fija explícitamente y coincide con la que usa el cliente
 * (`firebaseFunctionsProvider`). Un desajuste acá provoca un `not-found` que
 * cuesta horas de diagnosticar porque el error no dice nada útil.
 */
export const REGION = 'southamerica-east1';

/** Configuración por defecto de las funciones v2. */
export const DEFAULT_RUNTIME = {
  region: REGION,
  memory: '256MiB',
  timeoutSeconds: 60,
  maxInstances: 10,
} as const;

/** Configuración de las funciones que llaman a Gemini: más lentas y pesadas. */
export const AI_RUNTIME = {
  region: REGION,
  memory: '512MiB' as const,
  timeoutSeconds: 120,
  maxInstances: 5,
  // El secreto vive en Secret Manager, jamás en el código ni en el cliente.
  // `secrets` NO lleva `as const`: la firma de `onCall` espera un array
  // mutable y un `readonly` no le sirve.
  secrets: ['GEMINI_API_KEY'],
};

/** Límites que protegen el sistema de abusos y de costos. */
export const LIMITS = {
  /** Generaciones de IA por persona y por día. */
  aiGenerationsPerDay: 20,
  /** Tope diario de Aura: evita farmear con misiones triviales. */
  maxAuraPerDay: 500,
  /** Misiones que se pueden completar por día. */
  maxMissionsPerDay: 20,
  /** Reportes necesarios para ocultar un contenido de forma preventiva. */
  reportsToAutoHide: 3,
  /** Longitud máxima del texto de una publicación. */
  maxPostLength: 500,
  /** Longitud máxima de un comentario. */
  maxCommentLength: 300,
} as const;

/** Nombres de las colecciones, en un solo lugar para no tipearlos mal. */
export const COLLECTIONS = {
  users: 'users',
  goals: 'goals',
  missions: 'missions',
  auraLedger: 'auraLedger',
  achievements: 'achievements',
  notifications: 'notifications',
  fcmTokens: 'fcmTokens',
  aiUsage: 'aiUsage',
  following: 'following',
  followers: 'followers',
  publicProfiles: 'publicProfiles',
  handles: 'handles',
  posts: 'posts',
  likes: 'likes',
  comments: 'comments',
  reports: 'reports',
  categories: 'categories',
  missionTemplates: 'missionTemplates',
  config: 'config',
  aiJobs: 'aiJobs',
  adminStats: 'adminStats',
  auditLog: 'auditLog',
} as const;
