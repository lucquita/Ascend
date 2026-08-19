import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

/**
 * Tests de las reglas de seguridad de Firestore.
 *
 * Estos tests valen más que cualquier test de la app: las reglas son la única
 * frontera de seguridad real. Una regresión acá no rompe una pantalla, expone
 * los datos de todo el mundo.
 *
 * Cada bloque describe un ataque concreto que las reglas deben frenar.
 */

let testEnv;

const ALICE = 'alice';
const BOB = 'bob';
const ADMIN = 'root';

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'ascend-test',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  // Datos base escritos sin reglas, como haría el Admin SDK.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), {
      uid: ALICE,
      email: 'alice@ascend.app',
      displayName: 'Alice',
      handle: 'alice',
      role: 'user',
      status: 'active',
      aura: { total: 1840, level: 7 },
      stats: { missionsCompleted: 128, currentStreak: 12 },
    });
    // Cuenta suspendida: existe para verificar que no puede reactivarse sola.
    await setDoc(doc(db, 'users/bob'), {
      uid: BOB,
      email: 'bob@ascend.app',
      displayName: 'Bob',
      handle: 'bob',
      role: 'user',
      status: 'suspended',
    });
    await setDoc(doc(db, 'users/alice/missions/m1'), {
      ownerId: ALICE,
      goalId: 'g1',
      title: 'Leer 20 páginas',
      status: 'pending',
      auraReward: 25,
    });
    await setDoc(doc(db, 'users/alice/auraLedger/l1'), {
      amount: 25,
      balanceAfter: 1840,
      reason: 'mission_completed',
    });
    await setDoc(doc(db, 'publicProfiles/alice'), {
      uid: ALICE,
      displayName: 'Alice',
      handle: 'alice',
      level: 7,
    });
    await setDoc(doc(db, 'posts/p1'), {
      authorId: ALICE,
      type: 'mission_completed',
      text: 'Primera semana completa',
      source: { goalId: 'g1', goalTitle: 'Leer más' },
      author: { displayName: 'Alice', handle: 'alice', level: 7 },
      counters: { likes: 0, comments: 0, reports: 0 },
      moderation: { status: 'visible' },
    });
    await setDoc(doc(db, 'posts/p_hidden'), {
      authorId: BOB,
      type: 'reflection',
      text: 'contenido retirado',
      counters: { likes: 0, comments: 0, reports: 3 },
      moderation: { status: 'hidden' },
    });
  });
});

const alice = () => testEnv.authenticatedContext(ALICE).firestore();
const bob = () => testEnv.authenticatedContext(BOB).firestore();
const admin = () =>
  testEnv.authenticatedContext(ADMIN, { role: 'admin' }).firestore();
const suspended = () =>
  testEnv.authenticatedContext(BOB, { status: 'suspended' }).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

describe('Aislamiento entre usuarios', () => {
  it('cada persona lee su propio perfil', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'users/alice')));
  });

  it('NADIE puede leer el perfil de otra persona', async () => {
    // Contiene email y ajustes: para mostrar autores está publicProfiles.
    await assertFails(getDoc(doc(bob(), 'users/alice')));
  });

  it('nadie puede leer las misiones de otra persona', async () => {
    await assertFails(getDoc(doc(bob(), 'users/alice/missions/m1')));
  });

  it('un anónimo no lee absolutamente nada', async () => {
    await assertFails(getDoc(doc(anon(), 'users/alice')));
    await assertFails(getDoc(doc(anon(), 'posts/p1')));
    await assertFails(getDoc(doc(anon(), 'publicProfiles/alice')));
  });

  it('el admin sí puede leer cualquier perfil', async () => {
    await assertSucceeds(getDoc(doc(admin(), 'users/alice')));
  });
});

describe('Integridad del sistema de Aura', () => {
  it('RECHAZA que el cliente se escriba Aura', async () => {
    // El ataque más obvio: ponerse un millón de puntos.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice'), {
        aura: { total: 1000000, level: 99 },
      })
    );
  });

  it('RECHAZA que el cliente altere sus estadísticas', async () => {
    await assertFails(
      updateDoc(doc(alice(), 'users/alice'), {
        stats: { currentStreak: 999 },
      })
    );
  });

  it('RECHAZA que el cliente se promueva a administrador', async () => {
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { role: 'admin' }));
  });

  it('RECHAZA que una cuenta suspendida se levante la suspensión', async () => {
    // El ataque real es que quien está suspendido se devuelva a 'active'.
    // Ojo: escribir el MISMO valor que ya tiene el documento no es un ataque
    // —diff() no lo registra como cambio y no hay nada que frenar—, así que
    // el intento tiene que partir de una cuenta efectivamente suspendida.
    await assertFails(
      updateDoc(doc(suspended(), 'users/bob'), { status: 'active' })
    );

    // Y tampoco escondiendo el campo prohibido entre campos permitidos.
    await assertFails(
      updateDoc(doc(suspended(), 'users/bob'), {
        displayName: 'Bob otra vez',
        status: 'active',
      })
    );
  });

  it('el ledger de Aura es de solo lectura, incluso para su dueño', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'users/alice/auraLedger/l1')));
    await assertFails(
      setDoc(doc(alice(), 'users/alice/auraLedger/falso'), {
        amount: 999999,
        reason: 'mission_completed',
      })
    );
  });

  it('RECHAZA crear una misión con recompensa elegida por el cliente', async () => {
    await assertFails(
      setDoc(doc(alice(), 'users/alice/missions/m2'), {
        ownerId: ALICE,
        goalId: 'g1',
        title: 'Misión trucha',
        status: 'pending',
        auraReward: 99999,
      })
    );
  });

  it('PERMITE crear una misión sin recompensa (la pone el servidor)', async () => {
    await assertSucceeds(
      setDoc(doc(alice(), 'users/alice/missions/m3'), {
        ownerId: ALICE,
        goalId: 'g1',
        title: 'Salir a correr',
        status: 'pending',
      })
    );
  });

  it('PERMITE completar una misión sin tocar su recompensa', async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), { status: 'completed' })
    );
  });

  it('RECHAZA subir la recompensa al completar', async () => {
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), {
        status: 'completed',
        auraReward: 5000,
      })
    );
  });
});

describe('Perfil editable', () => {
  it('PERMITE cambiar nombre y biografía', async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice'), {
        displayName: 'Alice A.',
        bio: 'Corriendo mi primer 10k',
      })
    );
  });

  it('RECHAZA cambiar el handle por fuera de la transacción del servidor', async () => {
    await assertFails(
      updateDoc(doc(alice(), 'users/alice'), { handle: 'otro_handle' })
    );
  });

  it('RECHAZA el borrado directo de la cuenta', async () => {
    // La baja pasa por una Function que además limpia Storage y anonimiza.
    await assertFails(deleteDoc(doc(alice(), 'users/alice')));
  });
});

describe('Feed y moderación', () => {
  it('cualquier persona autenticada lee un post visible', async () => {
    await assertSucceeds(getDoc(doc(bob(), 'posts/p1')));
  });

  it('un post oculto por moderación no lo ve nadie salvo su autor y el admin', async () => {
    await assertFails(getDoc(doc(alice(), 'posts/p_hidden')));
    await assertSucceeds(getDoc(doc(bob(), 'posts/p_hidden')));
    await assertSucceeds(getDoc(doc(admin(), 'posts/p_hidden')));
  });

  it('RECHAZA publicar un logro sin referencia a algo real', async () => {
    // La premisa del producto, aplicada del lado del servidor.
    await assertFails(
      setDoc(doc(bob(), 'posts/p2'), {
        authorId: BOB,
        type: 'mission_completed',
        text: 'Logré todo, créanme',
      })
    );
  });

  it('PERMITE publicar una reflexión sin referencia', async () => {
    await assertSucceeds(
      setDoc(doc(bob(), 'posts/p3'), {
        authorId: BOB,
        type: 'reflection',
        text: 'Hoy costó, pero salió.',
      })
    );
  });

  it('RECHAZA publicar en nombre de otra persona', async () => {
    await assertFails(
      setDoc(doc(bob(), 'posts/p4'), {
        authorId: ALICE,
        type: 'reflection',
        text: 'suplantación',
      })
    );
  });

  it('RECHAZA inventarse contadores al publicar', async () => {
    await assertFails(
      setDoc(doc(bob(), 'posts/p5'), {
        authorId: BOB,
        type: 'reflection',
        text: 'hola',
        counters: { likes: 9999, comments: 0, reports: 0 },
      })
    );
  });

  it('RECHAZA autodeclararse contenido visible', async () => {
    await assertFails(
      setDoc(doc(bob(), 'posts/p6'), {
        authorId: BOB,
        type: 'reflection',
        text: 'saltarse la moderación',
        moderation: { status: 'visible' },
      })
    );
  });

  it('RECHAZA texto por encima del límite', async () => {
    await assertFails(
      setDoc(doc(bob(), 'posts/p7'), {
        authorId: BOB,
        type: 'reflection',
        text: 'x'.repeat(501),
      })
    );
  });

  it('el autor puede corregir el texto pero no el logro asociado', async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), 'posts/p1'), { text: 'Primera semana ✅' })
    );
    await assertFails(
      updateDoc(doc(alice(), 'posts/p1'), {
        source: { goalId: 'inventado', goalTitle: 'otro' },
      })
    );
  });

  it('nadie puede modificar el post de otra persona', async () => {
    await assertFails(updateDoc(doc(bob(), 'posts/p1'), { text: 'hackeado' }));
  });

  it('el admin puede ocultar cualquier post', async () => {
    await assertSucceeds(
      updateDoc(doc(admin(), 'posts/p1'), {
        moderation: { status: 'hidden' },
      })
    );
  });
});

describe('Likes idempotentes', () => {
  it('PERMITE dar like con el propio uid como ID del documento', async () => {
    await assertSucceeds(
      setDoc(doc(bob(), 'posts/p1/likes/bob'), { uid: BOB })
    );
  });

  it('RECHAZA dar like en nombre de otra persona', async () => {
    // El ID del documento es el uid: no hay forma de falsificarlo.
    await assertFails(
      setDoc(doc(bob(), 'posts/p1/likes/alice'), { uid: ALICE })
    );
  });

  it('RECHAZA actualizar un like (solo crear o borrar)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'posts/p1/likes/bob'), { uid: BOB });
    });
    await assertFails(
      updateDoc(doc(bob(), 'posts/p1/likes/bob'), { uid: BOB, extra: 1 })
    );
  });
});

describe('Cuentas suspendidas', () => {
  it('una cuenta suspendida NO puede publicar', async () => {
    await assertFails(
      setDoc(doc(suspended(), 'posts/p8'), {
        authorId: BOB,
        type: 'reflection',
        text: 'sigo acá',
      })
    );
  });

  it('una cuenta suspendida NO puede comentar ni dar like', async () => {
    await assertFails(
      setDoc(doc(suspended(), 'posts/p1/comments/c1'), {
        authorId: BOB,
        text: 'hola',
      })
    );
    await assertFails(
      setDoc(doc(suspended(), 'posts/p1/likes/bob'), { uid: BOB })
    );
  });

  it('pero SÍ puede seguir leyendo el feed', async () => {
    await assertSucceeds(getDoc(doc(suspended(), 'posts/p1')));
  });
});

describe('Reportes', () => {
  it('PERMITE reportar con ID determinístico', async () => {
    await assertSucceeds(
      setDoc(doc(bob(), 'reports/p1_bob'), {
        reporterId: BOB,
        target: { type: 'post', id: 'p1', ownerId: ALICE },
        reason: 'spam',
        status: 'open',
      })
    );
  });

  it('RECHAZA reportar con un ID arbitrario (evita spam de reportes)', async () => {
    await assertFails(
      setDoc(doc(bob(), 'reports/reporte_numero_47'), {
        reporterId: BOB,
        target: { type: 'post', id: 'p1', ownerId: ALICE },
        reason: 'spam',
        status: 'open',
      })
    );
  });

  it('RECHAZA crear un reporte ya resuelto', async () => {
    await assertFails(
      setDoc(doc(bob(), 'reports/p1_bob'), {
        reporterId: BOB,
        target: { type: 'post', id: 'p1', ownerId: ALICE },
        reason: 'spam',
        status: 'resolved',
      })
    );
  });

  it('quien reporta NO puede leer la cola de moderación', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reports/p1_bob'), {
        reporterId: BOB,
        status: 'open',
      });
    });
    await assertFails(getDoc(doc(bob(), 'reports/p1_bob')));
    await assertSucceeds(getDoc(doc(admin(), 'reports/p1_bob')));
  });
});

describe('Catálogos y configuración', () => {
  it('cualquier persona autenticada lee las categorías', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'categories/fitness'), {
        names: { es: 'Fitness' },
      });
    });
    await assertSucceeds(getDoc(doc(alice(), 'categories/fitness')));
  });

  it('solo el admin edita el catálogo', async () => {
    await assertFails(
      setDoc(doc(alice(), 'categories/inventada'), { names: { es: 'X' } })
    );
    await assertSucceeds(
      setDoc(doc(admin(), 'categories/inventada'), { names: { es: 'X' } })
    );
  });

  it('solo el admin cambia las reglas de Aura', async () => {
    await assertFails(
      setDoc(doc(alice(), 'config/auraRules'), {
        rewards: { mission: { easy: 100000 } },
      })
    );
    await assertSucceeds(
      setDoc(doc(admin(), 'config/auraRules'), {
        rewards: { mission: { easy: 10 } },
      })
    );
  });
});

describe('Ciclo de vida de la cuenta (Fase 1)', () => {
  it('RECHAZA crear el perfil propio con rol de administrador', async () => {
    // El registro real pasa por la Function, pero la regla es la última
    // frontera: alguien con el SDK podría intentar crearse el documento.
    await assertFails(
      setDoc(doc(bob(), 'users/bob2'), {
        uid: 'bob2',
        displayName: 'Bob',
        handle: 'bob2',
        role: 'admin',
        status: 'active',
      })
    );
  });

  it('RECHAZA crear el perfil ya con Aura o estadísticas', async () => {
    await assertFails(
      setDoc(doc(bob(), 'users/bob3'), {
        uid: 'bob3',
        displayName: 'Bob',
        handle: 'bob3',
        role: 'user',
        status: 'active',
        aura: { total: 999999, level: 99 },
      })
    );
  });

  it('RECHAZA crear el perfil de otra persona', async () => {
    await assertFails(
      setDoc(doc(bob(), 'users/alice2'), {
        uid: 'alice2',
        displayName: 'No soy Alice',
        handle: 'alice2',
        role: 'user',
        status: 'active',
      })
    );
  });

  it('los handles se leen pero NO se escriben desde el cliente', async () => {
    // Si el cliente pudiera escribirlos, reservaría nombres ajenos a voluntad.
    // Por eso la unicidad la resuelve una transacción del servidor.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'handles/alice'), { uid: ALICE });
    });

    await assertSucceeds(getDoc(doc(bob(), 'handles/alice')));
    await assertFails(setDoc(doc(bob(), 'handles/bob'), { uid: BOB }));
    await assertFails(
      setDoc(doc(bob(), 'handles/alice'), { uid: BOB })
    );
  });

  it('RECHAZA que el cliente toque lastLoginAt', async () => {
    // No está entre los campos que `onlyFields` autoriza. Este test existe
    // porque la app llegó a tener código que lo escribía: sin la regla, habría
    // pasado silenciosamente.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice'), { lastLoginAt: 'ahora' })
    );
  });

  it('RECHAZA que el cliente cambie su propio email', async () => {
    // El email lo gobierna Firebase Auth; un documento que no coincida con la
    // cuenta real sería una suplantación silenciosa.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice'), { email: 'otro@ascend.app' })
    );
  });

  it('PERMITE guardar ajustes y cerrar el onboarding', async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice'), {
        settings: { themeMode: 'dark' },
        updatedAt: new Date(),
      })
    );
    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice'), {
        onboarding: { completed: true, interests: ['fitness'] },
      })
    );
  });

  it('PERMITE editar la foto de perfil', async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice'), {
        photoUrl: 'https://cdn/avatar.jpg',
      })
    );
  });

  it('el perfil público de otra persona SÍ se lee; el privado no', async () => {
    // Es la razón de existir de `publicProfiles`: mostrar autores en el feed
    // sin abrir lectura sobre email y ajustes.
    await assertSucceeds(getDoc(doc(bob(), 'publicProfiles/alice')));
    await assertFails(getDoc(doc(bob(), 'users/alice')));
  });

  it('el log de auditoría de roles no lo ve un usuario común', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'auditLog/entrada1'), {
        action: 'set_user_role',
        actorUid: ADMIN,
        targetUid: ALICE,
      });
    });

    await assertFails(getDoc(doc(alice(), 'auditLog/entrada1')));
    await assertSucceeds(getDoc(doc(admin(), 'auditLog/entrada1')));
  });

  it('una cuenta suspendida no puede crear objetivos', async () => {
    await assertFails(
      setDoc(doc(suspended(), 'users/bob/goals/g1'), {
        ownerId: BOB,
        title: 'Objetivo de cuenta suspendida',
      })
    );
  });
});

describe('Colecciones exclusivas del servidor', () => {
  it('publicProfiles se lee pero no se escribe', async () => {
    await assertSucceeds(getDoc(doc(bob(), 'publicProfiles/alice')));
    await assertFails(
      updateDoc(doc(alice(), 'publicProfiles/alice'), { level: 99 })
    );
  });

  it('el log de auditoría es inmutable hasta para el admin', async () => {
    // Un registro que quien audita puede borrar no sirve para auditar.
    await assertFails(
      setDoc(doc(admin(), 'auditLog/entrada'), { action: 'inventada' })
    );
  });

  it('los costos de IA solo los ve el admin', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'aiJobs/j1'), { uid: ALICE, tokensIn: 100 });
    });
    await assertFails(getDoc(doc(alice(), 'aiJobs/j1')));
    await assertSucceeds(getDoc(doc(admin(), 'aiJobs/j1')));
  });

  it('los seguidores los mantiene un trigger, no el cliente', async () => {
    await assertFails(
      setDoc(doc(bob(), 'users/bob/followers/falso'), { at: 'ahora' })
    );
  });

  it('una colección no contemplada nace cerrada', async () => {
    // La regla de denegación por defecto cubre lo que todavía no existe.
    await assertFails(
      setDoc(doc(alice(), 'coleccionQueNadieCreo/doc'), { x: 1 })
    );
  });
});

describe('Objetivos — campos que solo escribe el servidor', () => {
  const validGoal = {
    ownerId: ALICE,
    title: 'Aprender inglés',
    categoryId: 'languages',
    status: 'active',
  };

  it('el dueño crea su objetivo', async () => {
    await assertSucceeds(
      setDoc(doc(alice(), 'users/alice/goals/g1'), validGoal)
    );
  });

  it('RECHAZA crear un objetivo con progress', async () => {
    // El progreso lo calcula el servidor a partir de las misiones. Si el
    // cliente pudiera fijarlo, cualquiera mostraría objetivos al 100%.
    await assertFails(
      setDoc(doc(alice(), 'users/alice/goals/g1'), {
        ...validGoal,
        progress: { missionsTotal: 10, missionsCompleted: 10 },
      })
    );
  });

  it('RECHAZA crear un objetivo con auraEarned', async () => {
    await assertFails(
      setDoc(doc(alice(), 'users/alice/goals/g1'), {
        ...validGoal,
        auraEarned: 99999,
      })
    );
  });

  it('RECHAZA crear un objetivo a nombre de otra persona', async () => {
    await assertFails(
      setDoc(doc(alice(), 'users/alice/goals/g1'), {
        ...validGoal,
        ownerId: BOB,
      })
    );
  });

  it('RECHAZA un título vacío o larguísimo', async () => {
    await assertFails(
      setDoc(doc(alice(), 'users/alice/goals/g1'), { ...validGoal, title: '' })
    );
    await assertFails(
      setDoc(doc(alice(), 'users/alice/goals/g2'), {
        ...validGoal,
        title: 'a'.repeat(81),
      })
    );
  });

  it('RECHAZA que el cliente se otorgue progreso al editar', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/goals/g1'), {
        ...validGoal,
        progress: { missionsTotal: 10, missionsCompleted: 2 },
        auraEarned: 50,
      });
    });

    await assertFails(
      updateDoc(doc(alice(), 'users/alice/goals/g1'), {
        progress: { missionsTotal: 10, missionsCompleted: 10 },
      })
    );
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/goals/g1'), { auraEarned: 99999 })
    );
  });

  it('RECHAZA esconder un campo prohibido entre campos permitidos', async () => {
    // El ataque real no manda `auraEarned` solo: lo cuela junto a un título
    // nuevo esperando que la regla mire únicamente el campo legítimo.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/goals/g1'), {
        ...validGoal,
        auraEarned: 50,
      });
    });

    await assertFails(
      updateDoc(doc(alice(), 'users/alice/goals/g1'), {
        title: 'Título nuevo y legítimo',
        auraEarned: 99999,
      })
    );
  });

  it('RECHAZA cambiar el dueño de un objetivo', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/goals/g1'), validGoal);
    });

    await assertFails(
      updateDoc(doc(alice(), 'users/alice/goals/g1'), { ownerId: BOB })
    );
  });

  it('el dueño SÍ puede editar título, estado y hitos', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/goals/g1'), validGoal);
    });

    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice/goals/g1'), {
        title: 'Aprender alemán',
        status: 'paused',
        milestones: [{ id: 'm1', title: 'Primer hito', order: 0, done: true }],
      })
    );
  });

  it('nadie lee ni escribe los objetivos de otra persona', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/goals/g1'), validGoal);
    });

    await assertFails(getDoc(doc(bob(), 'users/alice/goals/g1')));
    await assertFails(
      updateDoc(doc(bob(), 'users/alice/goals/g1'), { title: 'secuestrado' })
    );
    await assertFails(deleteDoc(doc(bob(), 'users/alice/goals/g1')));
  });

  it('el admin lee los objetivos pero el dueño es quien los borra', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/goals/g1'), validGoal);
    });

    await assertSucceeds(getDoc(doc(admin(), 'users/alice/goals/g1')));
    await assertSucceeds(deleteDoc(doc(alice(), 'users/alice/goals/g1')));
  });
});

describe('Catálogo de categorías', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'categories/languages'), {
        name: { es: 'Idiomas', en: 'Languages' },
        icon: 'translate',
        colorHex: '#3B82F6',
        order: 2,
        active: true,
      });
    });
  });

  it('cualquier persona autenticada lee el catálogo', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'categories/languages')));
  });

  it('un anónimo no lee el catálogo', async () => {
    await assertFails(getDoc(doc(anon(), 'categories/languages')));
  });

  it('un usuario común NO puede tocar el catálogo', async () => {
    // Es un catálogo global: si cualquiera pudiera editarlo, una persona
    // rompería la app de todas las demás.
    await assertFails(
      updateDoc(doc(alice(), 'categories/languages'), { name: { es: 'Hack' } })
    );
    await assertFails(
      setDoc(doc(alice(), 'categories/inventada'), { name: { es: 'Mía' } })
    );
  });

  it('el admin sí administra el catálogo', async () => {
    await assertSucceeds(
      setDoc(doc(admin(), 'categories/fitness'), {
        name: { es: 'Fitness', en: 'Fitness' },
        icon: 'fitness_center',
        colorHex: '#22C55E',
        order: 1,
        active: true,
      })
    );
  });
});

describe('Misiones — la recompensa la fija el servidor', () => {
  const validMission = {
    ownerId: ALICE,
    goalId: 'g1',
    title: 'Ver un capítulo en inglés',
    status: 'pending',
    difficulty: 'easy',
    budget: 'free',
  };

  it('el dueño crea su misión', async () => {
    await assertSucceeds(
      setDoc(doc(alice(), 'users/alice/missions/m2'), validMission)
    );
  });

  it('RECHAZA crear una misión con auraReward', async () => {
    // Es el exploit central del sistema de Aura: si el cliente pudiera
    // proponer la recompensa, se otorgaría la que quisiera.
    await assertFails(
      setDoc(doc(alice(), 'users/alice/missions/m2'), {
        ...validMission,
        auraReward: 99999,
      })
    );
  });

  it('RECHAZA crear una misión a nombre de otra persona', async () => {
    await assertFails(
      setDoc(doc(alice(), 'users/alice/missions/m2'), {
        ...validMission,
        ownerId: BOB,
      })
    );
  });

  it('RECHAZA un título vacío o larguísimo', async () => {
    await assertFails(
      setDoc(doc(alice(), 'users/alice/missions/m2'), {
        ...validMission,
        title: '',
      })
    );
    await assertFails(
      setDoc(doc(alice(), 'users/alice/missions/m3'), {
        ...validMission,
        title: 'a'.repeat(81),
      })
    );
  });

  it('RECHAZA subirse la recompensa al editar', async () => {
    // El fixture ya trae users/alice/missions/m1 con auraReward: 25.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), { auraReward: 99999 })
    );
  });

  it('RECHAZA colar la recompensa junto a un cambio legítimo de estado', async () => {
    // El ataque real no manda `auraReward` solo: lo esconde detrás de la
    // acción normal de completar la misión.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), {
        status: 'completed',
        auraReward: 99999,
      })
    );
  });

  it('el dueño SÍ puede completar su misión', async () => {
    // El cliente solo cambia el estado; el Aura la otorga el trigger (ADR-003).
    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), {
        status: 'completed',
        evidence: { note: 'Listo', uploadStatus: 'pending' },
      })
    );
  });

  it('RECHAZA cambiar el dueño de una misión', async () => {
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), { ownerId: BOB })
    );
  });

  it('nadie toca las misiones de otra persona', async () => {
    await assertFails(getDoc(doc(bob(), 'users/alice/missions/m1')));
    await assertFails(
      updateDoc(doc(bob(), 'users/alice/missions/m1'), { status: 'completed' })
    );
    await assertFails(deleteDoc(doc(bob(), 'users/alice/missions/m1')));
  });

  it('una cuenta suspendida no crea ni completa misiones', async () => {
    await assertFails(
      setDoc(doc(suspended(), 'users/bob/missions/m9'), {
        ...validMission,
        ownerId: BOB,
      })
    );
  });

  it('el admin lee las misiones y el dueño las borra', async () => {
    await assertSucceeds(getDoc(doc(admin(), 'users/alice/missions/m1')));
    await assertSucceeds(deleteDoc(doc(alice(), 'users/alice/missions/m1')));
  });
});

describe('Evidencias — la revisión la decide el servidor', () => {
  it('el dueño adjunta una evidencia sin declararla revisada', async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), {
        evidence: {
          localPath: '/tmp/foto.jpg',
          note: 'Listo',
          uploadStatus: 'pending',
        },
      })
    );
  });

  it('acepta reviewStatus explícitamente en pending', async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), {
        evidence: {
          localPath: '/tmp/foto.jpg',
          uploadStatus: 'pending',
          reviewStatus: 'pending',
        },
      })
    );
  });

  it('RECHAZA que alguien se apruebe su propia evidencia', async () => {
    // Sin esta regla, cualquiera acredita un logro con una foto inventada.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), {
        evidence: {
          photoUrl: 'https://cdn/falsa.jpg',
          uploadStatus: 'uploaded',
          reviewStatus: 'approved',
        },
      })
    );
  });

  it('RECHAZA también marcarla como rechazada', async () => {
    // La moderación es del servidor en ambos sentidos: si el cliente pudiera
    // escribir 'rejected', podría ensuciar la evidencia de una cuenta ajena
    // en cuanto se abriera cualquier otro camino de escritura.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), {
        evidence: {
          photoUrl: 'https://cdn/a.jpg',
          uploadStatus: 'uploaded',
          reviewStatus: 'rejected',
        },
      })
    );
  });

  it('RECHAZA colar la aprobación junto al completado de la misión', async () => {
    // El ataque realista: aprobarse la evidencia dentro de la acción legítima
    // de completar, esperando que la regla mire solo el estado.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), {
        status: 'completed',
        evidence: {
          photoUrl: 'https://cdn/falsa.jpg',
          uploadStatus: 'uploaded',
          reviewStatus: 'approved',
        },
      })
    );
  });

  it('quitar la evidencia sigue permitido', async () => {
    await assertSucceeds(
      updateDoc(doc(alice(), 'users/alice/missions/m1'), { evidence: null })
    );
  });
});

describe('Aura — server-authoritative de punta a punta', () => {
  it('RECHAZA que el cliente se escriba el saldo de Aura', async () => {
    // Sin esto, cualquiera con el SDK se pone 1.000.000 y el ranking es ficción.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice'), {
        aura: { total: 1000000, level: 99 },
      })
    );
  });

  it('RECHAZA colar el aura junto a un cambio legítimo de perfil', async () => {
    await assertFails(
      updateDoc(doc(alice(), 'users/alice'), {
        displayName: 'Alice',
        aura: { total: 1000000 },
      })
    );
  });

  it('RECHAZA escribir un asiento en el ledger', async () => {
    // El ledger es append-only y solo lo escribe el Admin SDK.
    await assertFails(
      setDoc(doc(alice(), 'users/alice/auraLedger/inventado'), {
        amount: 99999,
        reason: 'mission_completed',
      })
    );
  });

  it('RECHAZA borrar un asiento del ledger', async () => {
    // Un libro contable que el interesado puede borrar no sirve para auditar.
    await assertFails(deleteDoc(doc(alice(), 'users/alice/auraLedger/l1')));
  });

  it('el dueño SÍ lee su propio ledger', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'users/alice/auraLedger/l1')));
  });

  it('nadie lee el ledger de otra persona', async () => {
    await assertFails(getDoc(doc(bob(), 'users/alice/auraLedger/l1')));
  });

  it('el consumo diario del tope se lee pero no se escribe', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/auraUsage/2026-08-14'), {
        awarded: 300,
        missions: 8,
      });
    });

    await assertSucceeds(
      getDoc(doc(alice(), 'users/alice/auraUsage/2026-08-14'))
    );
    // Reescribirlo en cero sería resetearse el tope y farmear sin límite.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/auraUsage/2026-08-14'), {
        awarded: 0,
      })
    );
  });

  it('las reglas de Aura del catálogo no las edita un usuario común', async () => {
    await assertFails(
      setDoc(doc(alice(), 'config/auraRules'), {
        rewards: { mission: { easy: 99999 } },
      })
    );
  });
});

describe('Comunidad — contadores y autor son del servidor', () => {
  const validPost = {
    authorId: ALICE,
    type: 'reflection',
    text: 'Hoy me costó, pero seguí',
  };

  it('RECHAZA publicar con contadores propios', async () => {
    // Sin esto, cualquiera nace con mil "me gusta".
    await assertFails(
      setDoc(doc(alice(), 'posts/p_nuevo'), {
        ...validPost,
        counters: { likes: 1000, comments: 0, reports: 0 },
      })
    );
  });

  it('RECHAZA publicar autoaprobándose la moderación', async () => {
    await assertFails(
      setDoc(doc(alice(), 'posts/p_nuevo'), {
        ...validPost,
        moderation: { status: 'visible', aiScore: 0 },
      })
    );
  });

  it('RECHAZA publicar con un autor inventado', async () => {
    // El autor lo copia un trigger desde publicProfiles. Si el cliente lo
    // escribiera, publicaría con el nombre y el nivel de otra persona.
    await assertFails(
      setDoc(doc(alice(), 'posts/p_nuevo'), {
        ...validPost,
        author: { displayName: 'Otra persona', handle: 'otra', level: 99 },
      })
    );
  });

  it('PERMITE publicar una reflexión limpia', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'posts/p_nuevo'), validPost));
  });

  it('RECHAZA inflar los contadores de un post ajeno', async () => {
    await assertFails(
      updateDoc(doc(bob(), 'posts/p1'), {
        counters: { likes: 9999, comments: 0, reports: 0 },
      })
    );
  });

  it('RECHAZA que el autor se infle sus propios contadores', async () => {
    // Ser dueño del post no habilita a escribir lo que mantiene el servidor.
    await assertFails(
      updateDoc(doc(alice(), 'posts/p1'), {
        counters: { likes: 9999, comments: 0, reports: 0 },
      })
    );
  });
});

describe('Panel de administración — la frontera del backoffice', () => {
  /**
   * El criterio de aceptación de la Fase 8: alguien sin el claim `admin` no
   * puede entrar **ni leer datos** aunque manipule el cliente. El guard del
   * router es comodidad de navegación; lo que realmente frena es esto.
   */
  const suspendedAdmin = () =>
    testEnv
      .authenticatedContext('root', { role: 'admin', status: 'suspended' })
      .firestore();

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'adminStats/latest'), {
        usersTotal: 1200,
        generatedAt: '2026-08-17T04:00:00.000Z',
      });
    });
  });

  it('una cuenta común no puede listar los usuarios', async () => {
    // Es la tabla principal del panel: sin esto, cualquiera con el bundle web
    // del admin se llevaría el email de todo el mundo.
    await assertFails(getDocs(collection(alice(), 'users')));
  });

  it('el admin sí puede listarlos', async () => {
    await assertSucceeds(getDocs(collection(admin(), 'users')));
  });

  it('una cuenta común no lee las métricas agregadas', async () => {
    await assertFails(getDoc(doc(alice(), 'adminStats/latest')));
  });

  it('el admin lee las métricas', async () => {
    await assertSucceeds(getDoc(doc(admin(), 'adminStats/latest')));
  });

  it('NADIE escribe las métricas, ni el admin', async () => {
    // Las calcula una función programada con el Admin SDK. Si el panel
    // pudiera escribirlas, los números del dashboard dejarían de significar
    // algo.
    await assertFails(setDoc(doc(admin(), 'adminStats/latest'), { usersTotal: 0 }));
    await assertFails(setDoc(doc(alice(), 'adminStats/latest'), { usersTotal: 0 }));
  });

  it('una cuenta común no ve la cola de moderación', async () => {
    // Ver qué se reportó y qué no es información de moderación: revelaría a
    // quién están investigando.
    await assertFails(getDocs(collection(alice(), 'reports')));
  });

  it('el admin ve la cola de moderación', async () => {
    await assertSucceeds(getDocs(collection(admin(), 'reports')));
  });

  it('una cuenta común no lee el registro de auditoría', async () => {
    await assertFails(getDocs(collection(alice(), 'auditLog')));
  });

  it('un administrador SUSPENDIDO pierde el acceso', async () => {
    // Suspender a un administrador tiene que quitarle el poder de verdad. Si
    // las reglas solo miraran el rol, seguiría leyendo todo y moderando hasta
    // que su token caducara —y la suspensión es justamente la herramienta para
    // frenar a un administrador que hace daño—.
    await assertFails(getDoc(doc(suspendedAdmin(), 'users/alice')));
    await assertFails(getDoc(doc(suspendedAdmin(), 'adminStats/latest')));
    await assertFails(getDocs(collection(suspendedAdmin(), 'reports')));
  });

  it('un administrador suspendido tampoco edita el catálogo', async () => {
    await assertFails(
      setDoc(doc(suspendedAdmin(), 'categories/nueva'), { name: { es: 'X' } })
    );
  });

  it('un administrador suspendido tampoco oculta publicaciones', async () => {
    await assertFails(
      updateDoc(doc(suspendedAdmin(), 'posts/p1'), {
        moderation: { status: 'hidden' },
      })
    );
  });

  it('un anónimo no toca nada del panel', async () => {
    await assertFails(getDoc(doc(anon(), 'adminStats/latest')));
    await assertFails(getDocs(collection(anon(), 'auditLog')));
    await assertFails(getDocs(collection(anon(), 'users')));
  });
});
