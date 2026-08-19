import { describe, expect, it } from 'vitest';
import {
  AI_COST_PER_CALL_USD,
  buildStatsDocument,
  checkModeration,
  hidesContent,
  resolvedStatus,
  statsDocId,
  windowStart,
  type StatsCounters,
} from '../src/services/admin-service';
import {
  moderateContentSchema,
  setUserStatusSchema,
} from '../src/lib/validation';
import { requireAdmin } from '../src/lib/admin-guard';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * La administración es la parte del sistema con más poder: cambia roles,
 * suspende cuentas y borra contenido de la vista de todos. Lo que no se
 * compruebe acá se compruebe en producción, sobre gente real.
 */
describe('checkModeration', () => {
  const base = {
    action: 'hide_content' as const,
    targetType: 'post',
    reportStatus: 'open',
  };

  it('acepta ocultar una publicación reportada', () => {
    expect(checkModeration(base).ok).toBe(true);
  });

  it('acepta un reporte que ya estaba en revisión', () => {
    expect(checkModeration({ ...base, reportStatus: 'reviewing' }).ok).toBe(
      true,
    );
  });

  it('rechaza resolver dos veces el mismo reporte', () => {
    // Resolver de nuevo duplicaría la auditoría y podría suspender a alguien
    // dos veces por lo mismo.
    const result = checkModeration({ ...base, reportStatus: 'resolved' });
    expect(result).toEqual({ ok: false, code: 'already-closed' });
  });

  it('rechaza un tipo de contenido que no sabemos moderar', () => {
    // Sin esto escribiríamos un campo `moderation` en una colección
    // cualquiera, siguiendo lo que dijera el documento del reporte.
    const result = checkModeration({ ...base, targetType: 'goal' });
    expect(result).toEqual({ ok: false, code: 'unknown-target' });
  });

  it('exige motivo para suspender a alguien', () => {
    const result = checkModeration({ ...base, action: 'suspend_author' });
    expect(result).toEqual({ ok: false, code: 'note-required' });
  });

  it('no acepta un motivo de relleno', () => {
    const result = checkModeration({
      ...base,
      action: 'suspend_author',
      note: '  x  ',
    });
    expect(result).toEqual({ ok: false, code: 'note-required' });
  });

  it('acepta suspender con un motivo escrito', () => {
    const result = checkModeration({
      ...base,
      action: 'suspend_author',
      note: 'Acoso reiterado a otra persona',
    });
    expect(result.ok).toBe(true);
  });

  it('descartar no necesita motivo', () => {
    // Descartar es la acción reversible: si se descarta mal, el contenido
    // sigue publicado y se puede volver a reportar.
    expect(checkModeration({ ...base, action: 'dismiss' }).ok).toBe(true);
  });
});

describe('efecto de cada acción', () => {
  it('ocultar y suspender esconden el contenido; descartar no', () => {
    expect(hidesContent('hide_content')).toBe(true);
    expect(hidesContent('suspend_author')).toBe(true);
    expect(hidesContent('dismiss')).toBe(false);
  });

  it('el reporte queda resuelto o descartado según la decisión', () => {
    // La distinción importa para las métricas: descartados masivos significan
    // que la gente reporta mal, resueltos masivos que hay un problema real.
    expect(resolvedStatus('hide_content')).toBe('resolved');
    expect(resolvedStatus('suspend_author')).toBe('resolved');
    expect(resolvedStatus('dismiss')).toBe('dismissed');
  });
});

describe('windowStart', () => {
  it('normaliza a medianoche UTC', () => {
    // Sin normalizar, "activos en 7 días" daría distinto según la hora a la
    // que corrió la agregación y dos días seguidos no serían comparables.
    const start = windowStart(new Date('2026-08-17T18:45:33Z'), 7);
    expect(start.toISOString()).toBe('2026-08-10T00:00:00.000Z');
  });

  it('con cero días devuelve el comienzo del día en curso', () => {
    const start = windowStart(new Date('2026-08-17T18:45:33Z'), 0);
    expect(start.toISOString()).toBe('2026-08-17T00:00:00.000Z');
  });

  it('cruza bien el cambio de mes', () => {
    const start = windowStart(new Date('2026-03-03T10:00:00Z'), 7);
    expect(start.toISOString()).toBe('2026-02-24T00:00:00.000Z');
  });
});

describe('statsDocId', () => {
  it('usa la fecha como identificador', () => {
    expect(statsDocId(new Date('2026-08-17T23:59:00Z'))).toBe('2026-08-17');
  });
});

describe('buildStatsDocument', () => {
  const counters: StatsCounters = {
    usersTotal: 1200,
    usersActive7d: 380,
    usersNew7d: 47,
    goalsActive: 900,
    missionsCompleted7d: 2100,
    auraGranted7d: 54000,
    postsTotal: 640,
    reportsOpen: 3,
    aiCallsToday: 250,
  };

  it('estima el costo de la IA a partir de las llamadas', () => {
    const document = buildStatsDocument(
      counters,
      new Date('2026-08-17T04:00:00Z'),
    );
    expect(document.aiCostUsdToday).toBe(250 * AI_COST_PER_CALL_USD);
  });

  it('sin llamadas el costo es cero, no null', () => {
    // Un `null` en el panel se pintaría como "—", que se lee como "no sabemos"
    // en vez de "no se gastó nada".
    const document = buildStatsDocument(
      { ...counters, aiCallsToday: 0 },
      new Date('2026-08-17T04:00:00Z'),
    );
    expect(document.aiCostUsdToday).toBe(0);
  });

  it('sella cuándo se calcularon', () => {
    // Es lo que permite al panel avisar que las métricas quedaron viejas en
    // vez de mostrar números de hace una semana como si fueran de hoy.
    const document = buildStatsDocument(
      counters,
      new Date('2026-08-17T04:00:00Z'),
    );
    expect(document.generatedAt).toBe('2026-08-17T04:00:00.000Z');
  });

  it('conserva todos los contadores', () => {
    const document = buildStatsDocument(counters, new Date());
    expect(document).toMatchObject(counters);
  });
});

describe('esquemas de entrada de la administración', () => {
  it('setUserStatus solo acepta los dos estados reales', () => {
    expect(
      setUserStatusSchema.safeParse({ targetUid: 'u1', status: 'active' })
        .success,
    ).toBe(true);
    expect(
      setUserStatusSchema.safeParse({ targetUid: 'u1', status: 'deleted' })
        .success,
    ).toBe(false);
  });

  it('setUserStatus exige un uid', () => {
    expect(
      setUserStatusSchema.safeParse({ targetUid: '', status: 'suspended' })
        .success,
    ).toBe(false);
  });

  it('moderateContent rechaza una acción inventada', () => {
    // Una llamable se invoca con `curl`: lo que no se rechace acá, entra.
    expect(
      moderateContentSchema.safeParse({ reportId: 'r1', action: 'delete_all' })
        .success,
    ).toBe(false);
  });

  it('moderateContent acepta las tres acciones previstas', () => {
    for (const action of ['hide_content', 'dismiss', 'suspend_author']) {
      expect(
        moderateContentSchema.safeParse({
          reportId: 'r1',
          action,
          note: 'Motivo suficiente',
        }).success,
      ).toBe(true);
    }
  });

  it('moderateContent acota la nota', () => {
    const result = moderateContentSchema.safeParse({
      reportId: 'r1',
      action: 'dismiss',
      note: 'x'.repeat(501),
    });
    expect(result.success).toBe(false);
  });
});

describe('requireAdmin', () => {
  const request = (token?: Record<string, unknown>) =>
    ({
      auth: token === undefined ? null : { uid: 'root', token },
    }) as unknown as Parameters<typeof requireAdmin>[0];

  it('deja pasar a un administrador activo', () => {
    expect(requireAdmin(request({ role: 'admin' }), 'x')).toBe('root');
  });

  it('rechaza a quien no inició sesión', () => {
    expect(() => requireAdmin(request(), 'x')).toThrow(HttpsError);
  });

  it('rechaza a una cuenta común', () => {
    expect(() => requireAdmin(request({ role: 'user' }), 'x')).toThrow(
      HttpsError
    );
  });

  it('rechaza a un token sin rol', () => {
    // El claim ausente es lo normal en una cuenta recién creada.
    expect(() => requireAdmin(request({}), 'x')).toThrow(HttpsError);
  });

  it('rechaza a un ADMINISTRADOR SUSPENDIDO', () => {
    // Suspender a un administrador tiene que quitarle el poder de verdad: si
    // solo se mirara el rol, seguiría moderando y cambiando roles hasta que su
    // token caducara, y la suspensión es precisamente la herramienta para
    // frenar a un administrador que hace daño.
    expect(() =>
      requireAdmin(request({ role: 'admin', status: 'suspended' }), 'x')
    ).toThrow(HttpsError);
  });
});
