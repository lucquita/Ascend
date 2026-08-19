import { describe, expect, it } from 'vitest';
import {
  dayKeyIn,
  groupKeyFor,
  groupedSocialBody,
  isReminderDue,
  isStreakAtRisk,
  isTypeEnabled,
  isWithinQuietHours,
  localMinutesIn,
  minutesOfDay,
  reminderBody,
  resolveDelivery,
  streakWarningBody,
  type NotificationPrefs,
} from '../src/services/notification-service';

/**
 * Esta es la copia en TypeScript de `notification_usecases.dart`. Los casos
 * límite son los mismos a propósito: si una de las dos se desvía, el envío real
 * dejaría de coincidir con lo que la app promete en los ajustes.
 */
const at = (hour: number, minute = 0) => hour * 60 + minute;

describe('minutesOfDay', () => {
  it('convierte un HH:mm válido', () => {
    expect(minutesOfDay('20:30')).toBe(at(20, 30));
    expect(minutesOfDay('00:00')).toBe(0);
    expect(minutesOfDay('23:59')).toBe(at(23, 59));
  });

  it('devuelve null ante cualquier basura, en vez de lanzar', () => {
    // El valor sale del perfil, que lo pudo escribir una versión vieja.
    for (const bad of [null, undefined, '', 'ayer', '25:00', '10:70', '10']) {
      expect(minutesOfDay(bad)).toBeNull();
    }
  });
});

describe('isWithinQuietHours', () => {
  it('una ventana NOCTURNA cubre toda la noche', () => {
    // Es el caso que se rompe siempre: con 22:00–07:00 la comparación ingenua
    // da false durante toda la noche, justo cuando había que callarse.
    for (const hour of [22, 23, 0, 3, 6]) {
      expect(isWithinQuietHours(at(hour), '22:00', '07:00')).toBe(true);
    }
  });

  it('fuera de la ventana nocturna suena', () => {
    for (const hour of [7, 12, 21]) {
      expect(isWithinQuietHours(at(hour), '22:00', '07:00')).toBe(false);
    }
  });

  it('una ventana diurna se evalúa directo', () => {
    expect(isWithinQuietHours(at(14), '13:00', '16:00')).toBe(true);
    expect(isWithinQuietHours(at(17), '13:00', '16:00')).toBe(false);
  });

  it('sin horario configurado no hay silencio', () => {
    // Ante la duda se entrega: un aviso de más molesta menos que una racha
    // perdida en silencio.
    expect(isWithinQuietHours(at(3), null, null)).toBe(false);
    expect(isWithinQuietHours(at(3), '22:00', undefined)).toBe(false);
  });

  it('inicio igual a fin no silencia las 24 horas', () => {
    expect(isWithinQuietHours(at(12), '22:00', '22:00')).toBe(false);
  });
});

describe('isTypeEnabled', () => {
  const allOff: NotificationPrefs = {
    dailyReminder: false,
    streakAlerts: false,
    socialActivity: false,
    aiSuggestions: false,
  };

  it('cada interruptor apaga su tipo', () => {
    expect(isTypeEnabled('mission_reminder', allOff)).toBe(false);
    expect(isTypeEnabled('streak_warning', allOff)).toBe(false);
    expect(isTypeEnabled('new_like', allOff)).toBe(false);
    expect(isTypeEnabled('ai_suggestion', allOff)).toBe(false);
  });

  it('un campo ausente cuenta como encendido', () => {
    // Un perfil viejo sin el campo no puede quedarse sin notificaciones: el
    // valor por defecto del perfil es "sí".
    expect(isTypeEnabled('new_like', {})).toBe(true);
    expect(isTypeEnabled('mission_reminder', {})).toBe(true);
  });

  it('moderación y sistema no se pueden apagar', () => {
    expect(isTypeEnabled('moderation_action', allOff)).toBe(true);
    expect(isTypeEnabled('system', allOff)).toBe(true);
    expect(isTypeEnabled('level_up', allOff)).toBe(true);
  });
});

describe('resolveDelivery', () => {
  const quiet: NotificationPrefs = {
    quietHoursStart: '22:00',
    quietHoursEnd: '07:00',
  };

  it('fuera del silencio manda push', () => {
    expect(resolveDelivery('new_like', quiet, at(12))).toBe('push');
  });

  it('en silencio guarda en la bandeja, NO descarta', () => {
    // Descartar haría que alguien se entere de un comentario solo si abre la
    // app justo ese día.
    expect(resolveDelivery('new_like', quiet, at(3))).toBe('inbox_only');
  });

  it('un tipo apagado se descarta del todo', () => {
    expect(resolveDelivery('new_like', { socialActivity: false }, at(12))).toBe(
      'drop',
    );
  });

  it('el interruptor pesa más que el silencio', () => {
    expect(
      resolveDelivery('new_like', { ...quiet, socialActivity: false }, at(3)),
    ).toBe('drop');
  });
});

describe('localMinutesIn', () => {
  // 2026-08-17T23:30:00Z. Argentina está en UTC-3 todo el año.
  const instant = new Date('2026-08-17T23:30:00Z');

  it('convierte a la hora local de la zona', () => {
    expect(localMinutesIn('America/Argentina/Buenos_Aires', instant)).toBe(
      at(20, 30),
    );
  });

  it('da horas distintas en zonas distintas para el mismo instante', () => {
    // Es la razón de ser de la tarea horaria: "las 20:00" no es un momento,
    // es un momento por zona horaria.
    const buenosAires = localMinutesIn(
      'America/Argentina/Buenos_Aires',
      instant,
    );
    const madrid = localMinutesIn('Europe/Madrid', instant);
    const mexico = localMinutesIn('America/Mexico_City', instant);

    expect(new Set([buenosAires, madrid, mexico]).size).toBe(3);
  });

  it('maneja la medianoche sin devolver 24:00', () => {
    const midnight = new Date('2026-08-18T03:00:00Z');
    expect(localMinutesIn('America/Argentina/Buenos_Aires', midnight)).toBe(0);
  });

  it('una zona desconocida cae a UTC en vez de fallar', () => {
    expect(localMinutesIn('Marte/Olympus', instant)).toBe(at(23, 30));
  });
});

describe('isReminderDue', () => {
  it('le toca durante toda la hora del recordatorio', () => {
    // La tarea corre en punto: comparar el minuto exacto no serviría.
    expect(isReminderDue('20:30', at(20, 0))).toBe(true);
    expect(isReminderDue('20:30', at(20, 59))).toBe(true);
  });

  it('no le toca en otra hora', () => {
    expect(isReminderDue('20:30', at(19, 59))).toBe(false);
    expect(isReminderDue('20:30', at(21, 0))).toBe(false);
  });

  it('sin hora configurada usa las 20:00', () => {
    expect(isReminderDue(undefined, at(20, 15))).toBe(true);
    expect(isReminderDue(undefined, at(9))).toBe(false);
  });

  it('una hora inválida no dispara nada', () => {
    // Mejor no mandar que mandar a las 00:00 por interpretar mal el dato.
    expect(isReminderDue('ayer', at(20))).toBe(false);
  });
});

describe('agrupación social', () => {
  it('los likes de una publicación y un día comparten clave', () => {
    expect(groupKeyFor('new_like', 'p1', '2026-08-17')).toBe(
      groupKeyFor('new_like', 'p1', '2026-08-17'),
    );
  });

  it('cada día empieza un grupo nuevo', () => {
    expect(groupKeyFor('new_like', 'p1', '2026-08-17')).not.toBe(
      groupKeyFor('new_like', 'p1', '2026-08-18'),
    );
  });

  it('un like y un comentario no se mezclan', () => {
    expect(groupKeyFor('new_like', 'p1', '2026-08-17')).not.toBe(
      groupKeyFor('new_comment', 'p1', '2026-08-17'),
    );
  });

  it('lo que no se agrupa devuelve null', () => {
    expect(groupKeyFor('new_follower', 'u1', '2026-08-17')).toBeNull();
    expect(groupKeyFor('new_like', '', '2026-08-17')).toBeNull();
  });

  it('50 likes producen UN texto que dice 50', () => {
    // Es el criterio de aceptación de la fase.
    expect(groupedSocialBody('new_like', 50, 'Ana')).toBe(
      'Ana y 49 personas más les gustó tu publicación.',
    );
  });

  it('con dos, el resto va en singular', () => {
    expect(groupedSocialBody('new_comment', 2, 'Ana')).toContain(
      '1 persona más',
    );
  });

  it('sin nombre no inventa uno', () => {
    expect(groupedSocialBody('new_like', 3, null)).toBe(
      'A 3 personas les gustó tu publicación.',
    );
    expect(groupedSocialBody('new_like', 1, null)).toMatch(/^Alguien/);
  });
});

describe('dayKeyIn', () => {
  it('usa el día local, no el UTC', () => {
    // A las 22:00 de Buenos Aires ya es el día siguiente en UTC: comparar en
    // UTC daría la racha por rota dos horas antes de tiempo.
    const lateNight = new Date('2026-08-18T01:00:00Z');
    expect(dayKeyIn('America/Argentina/Buenos_Aires', lateNight)).toBe(
      '2026-08-17',
    );
    expect(dayKeyIn('Etc/UTC', lateNight)).toBe('2026-08-18');
  });

  it('una zona desconocida cae al día UTC', () => {
    expect(dayKeyIn('Marte/Olympus', new Date('2026-08-17T12:00:00Z'))).toBe(
      '2026-08-17',
    );
  });
});

describe('isStreakAtRisk', () => {
  it('con racha viva y sin actividad hoy, está en riesgo', () => {
    expect(
      isStreakAtRisk({
        currentStreak: 12,
        lastActivityDayKey: '2026-08-16',
        todayDayKey: '2026-08-17',
      }),
    ).toBe(true);
  });

  it('si ya hizo algo hoy, NO se avisa', () => {
    // El aviso a quien ya cumplió es el que enseña a ignorar los avisos.
    expect(
      isStreakAtRisk({
        currentStreak: 12,
        lastActivityDayKey: '2026-08-17',
        todayDayKey: '2026-08-17',
      }),
    ).toBe(false);
  });

  it('sin racha no hay nada que perder', () => {
    expect(
      isStreakAtRisk({
        currentStreak: 0,
        lastActivityDayKey: null,
        todayDayKey: '2026-08-17',
      }),
    ).toBe(false);
  });
});

describe('textos', () => {
  it('el recordatorio distingue una misión de varias', () => {
    expect(reminderBody(1)).toContain('una misión');
    expect(reminderBody(4)).toContain('4 misiones');
  });

  it('el aviso de racha distingue el primer día', () => {
    expect(streakWarningBody(1)).toContain('Empezaste');
    expect(streakWarningBody(30)).toContain('30 días');
  });
});
