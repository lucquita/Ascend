/**
 * Siembra el catálogo de categorías en Firestore.
 *
 * ## Por qué es un script y no una Cloud Function
 *
 * `categories` es `allow write: if isAdmin()`, así que el cliente no puede
 * crearlas. Podría hacerlo una llamable, pero sembrar un catálogo es una tarea
 * de puesta en marcha que se corre una vez por entorno, no una funcionalidad
 * del producto: exponerla como endpoint sería superficie de ataque a cambio de
 * nada. El Admin SDK se salta las reglas por diseño y es la herramienta
 * correcta para esto.
 *
 * ## Idempotencia
 *
 * Usa `merge: true` y **no** toca `goalsCount`, que es una estadística que
 * mantiene el servidor. Volver a correrlo actualiza nombres e iconos sin pisar
 * los contadores acumulados.
 *
 * ## Uso
 *
 * ```bash
 * cd backend/functions
 * # Contra el emulador:
 * FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GOOGLE_CLOUD_PROJECT=ascend-dev \
 *   node scripts/seed-categories.mjs
 * # Contra el proyecto real (requiere credenciales de servicio):
 * GOOGLE_APPLICATION_CREDENTIALS=/ruta/clave.json GOOGLE_CLOUD_PROJECT=ascend-dev \
 *   node scripts/seed-categories.mjs
 * ```
 */

import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

/** Catálogo inicial. El orden es el que se ve al crear un objetivo. */
const CATEGORIES = [
  {
    id: 'fitness',
    name: { es: 'Fitness', en: 'Fitness' },
    description: {
      es: 'Moverte, entrenar y cuidar tu cuerpo',
      en: 'Move, train and take care of your body',
    },
    icon: 'fitness_center',
    colorHex: '#22C55E',
    order: 1,
  },
  {
    id: 'languages',
    name: { es: 'Idiomas', en: 'Languages' },
    description: {
      es: 'Aprender un nuevo idioma',
      en: 'Learn a new language',
    },
    icon: 'translate',
    colorHex: '#3B82F6',
    order: 2,
  },
  {
    id: 'business',
    name: { es: 'Negocios', en: 'Business' },
    description: {
      es: 'Emprender, vender y hacer crecer un proyecto',
      en: 'Start, sell and grow a project',
    },
    icon: 'work_outline',
    colorHex: '#6366F1',
    order: 3,
  },
  {
    id: 'reading',
    name: { es: 'Lectura', en: 'Reading' },
    description: {
      es: 'Leer más y mejor',
      en: 'Read more and better',
    },
    icon: 'menu_book',
    colorHex: '#A855F7',
    order: 4,
  },
  {
    id: 'finance',
    name: { es: 'Finanzas', en: 'Finance' },
    description: {
      es: 'Ordenar tus cuentas y ahorrar',
      en: 'Organise your money and save',
    },
    icon: 'savings',
    colorHex: '#14B8A6',
    order: 5,
  },
  {
    id: 'travel',
    name: { es: 'Viajes', en: 'Travel' },
    description: {
      es: 'Conocer lugares nuevos',
      en: 'Discover new places',
    },
    icon: 'flight_takeoff',
    colorHex: '#F97316',
    order: 6,
  },
  {
    id: 'mindfulness',
    name: { es: 'Bienestar', en: 'Mindfulness' },
    description: {
      es: 'Descanso, meditación y salud mental',
      en: 'Rest, meditation and mental health',
    },
    icon: 'self_improvement',
    colorHex: '#0EA5E9',
    order: 7,
  },
  {
    id: 'skills',
    name: { es: 'Habilidades', en: 'Skills' },
    description: {
      es: 'Aprender algo que no sabés hacer',
      en: 'Learn something you cannot do yet',
    },
    icon: 'school',
    colorHex: '#EAB308',
    order: 8,
  },
  {
    id: 'creativity',
    name: { es: 'Creatividad', en: 'Creativity' },
    description: {
      es: 'Escribir, dibujar, tocar, crear',
      en: 'Write, draw, play, create',
    },
    icon: 'palette',
    colorHex: '#EC4899',
    order: 9,
  },
  {
    id: 'relationships',
    name: { es: 'Vínculos', en: 'Relationships' },
    description: {
      es: 'Cuidar a la gente que te importa',
      en: 'Take care of the people who matter',
    },
    icon: 'favorite_outline',
    colorHex: '#EF4444',
    order: 10,
  },
];

async function main() {
  initializeApp();
  const db = getFirestore();
  const batch = db.batch();

  for (const category of CATEGORIES) {
    const { id, ...data } = category;
    batch.set(
      db.collection('categories').doc(id),
      {
        ...data,
        active: true,
        // `goalsCount` se omite a propósito: lo mantiene el servidor y
        // reescribirlo en cada siembra borraría la estadística acumulada.
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  await batch.commit();
  console.log(`Catálogo sembrado: ${CATEGORIES.length} categorías.`);
}

main().catch((error) => {
  console.error('Falló la siembra del catálogo:', error);
  process.exitCode = 1;
});
