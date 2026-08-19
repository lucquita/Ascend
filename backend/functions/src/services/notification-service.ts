/**
 * Lógica pura de las notificaciones.
 *
 * Es el espejo en TypeScript de `notification_usecases.dart`. Está duplicada a
 * propósito y el motivo es concreto: **el envío ocurre en el servidor**, así que
 * la decisión tiene que poder tomarse acá sin consultar al cliente; y la app
 * necesita las mismas reglas para pintar los ajustes de forma coherente con lo
 * que realmente va a pasar.
 *
 * Las dos copias están probadas por separado y comparten los mismos casos
 * límite, que es lo que evita que se separen sin que nadie lo note.
 *
 * La regla que ordena todo: **una notificación que molesta se desactiva, y
 * entonces se pierden también las que servían.**
 */

/** Tipos de notificación, en el mismo orden que el enum de Dart. */
export type NotificationType =
  | 'mission_reminder'
  | 'streak_warning'
  | 'aura_gained'
  | 'level_up'
  | 'new_like'
  | 'new_comment'
  | 'new_follower'
  | 'ai_suggestion'
  | 'moderation_action'
  | 'system';

/** Preferencias de notificación tal como viven en `users/{uid}`. */
export interface NotificationPrefs {
  dailyReminder?: boolean;
  reminderTime?: string;
  streakAlerts?: boolean;
  socialActivity?: boolean;
  aiSuggestions?: boolean;
  quietHoursStart?: string | null;
  quietHoursEnd?: string | null;
}

/** Qué hacer con una notificación que está por enviarse. */
export type Delivery = 'push' | 'inbox_only' | 'drop';

/** Minutos desde la medianoche de un `HH:mm`, o `null` si no tiene esa forma. */
export function minutesOfDay(time: string | null | undefined): number | null {
  if (!time) {
    return null;
  }
  const parts = time.split(':');
  if (parts.length !== 2) {
    return null;
  }
  const hour = Number(parts[0]);
  const minute = Number(parts[1]);
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/**
 * `true` si [localMinutes] cae dentro del horario de silencio.
 *
 * El horario de silencio normal es **nocturno**: 22:00 a 07:00. Ahí el inicio es
 * mayor que el fin, y la comparación ingenua `inicio <= t && t < fin` da `false`
 * durante toda la noche — justo cuando había que callarse.
 */
export function isWithinQuietHours(
  localMinutes: number,
  start: string | null | undefined,
  end: string | null | undefined,
): boolean {
  const from = minutesOfDay(start);
  const to = minutesOfDay(end);
  if (from === null || to === null || from === to) {
    return false;
  }
  return from < to
    ? localMinutes >= from && localMinutes < to
    : localMinutes >= from || localMinutes < to;
}

/**
 * `true` si el tipo está habilitado en las preferencias.
 *
 * Los tipos sin interruptor —subida de nivel, moderación, anuncios— no se
 * pueden apagar: son pocos, no se repiten y avisan de algo que afecta a la
 * cuenta. Un aviso de moderación silenciado dejaría a alguien sin entender por
 * qué desapareció su publicación.
 *
 * Un campo ausente cuenta como **encendido**: es el valor por defecto del
 * perfil, y un `undefined` no puede significar "lo apagó".
 */
export function isTypeEnabled(
  type: NotificationType,
  prefs: NotificationPrefs,
): boolean {
  switch (type) {
    case 'mission_reminder':
      return prefs.dailyReminder !== false;
    case 'streak_warning':
      return prefs.streakAlerts !== false;
    case 'new_like':
    case 'new_comment':
    case 'new_follower':
      return prefs.socialActivity !== false;
    case 'ai_suggestion':
      return prefs.aiSuggestions !== false;
    default:
      return true;
  }
}

/** Decide qué hacer con una notificación. */
export function resolveDelivery(
  type: NotificationType,
  prefs: NotificationPrefs,
  localMinutes: number,
): Delivery {
  if (!isTypeEnabled(type, prefs)) {
    return 'drop';
  }
  // El silencio no descarta: guarda sin sonar. Descartar haría que alguien se
  // entere de un comentario solo si abre la app justo ese día.
  if (
    isWithinQuietHours(localMinutes, prefs.quietHoursStart, prefs.quietHoursEnd)
  ) {
    return 'inbox_only';
  }
  return 'push';
}

/**
 * Hora local de una zona horaria, en minutos desde la medianoche.
 *
 * Usa `Intl` en lugar de guardar un desfase fijo porque el desfase **cambia dos
 * veces al año** con el horario de verano. Un offset persistido se desactualiza
 * en silencio y los recordatorios empiezan a llegar una hora corridos.
 *
 * Ante una zona horaria desconocida cae a UTC en vez de fallar: un recordatorio
 * a la hora equivocada es mejor que ninguno, y el dato sale del perfil.
 */
export function localMinutesIn(timezone: string, now: Date): number {
  try {
    const formatted = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(now);
    const minutes = minutesOfDay(formatted.replace('24:', '00:'));
    return minutes ?? now.getUTCHours() * 60 + now.getUTCMinutes();
  } catch {
    return now.getUTCHours() * 60 + now.getUTCMinutes();
  }
}

/**
 * `true` si a esta persona le toca el recordatorio en esta corrida.
 *
 * La tarea corre **una vez por hora**, así que la ventana es la hora en curso:
 * si el recordatorio es a las 20:30 y la corrida es la de las 20:00 local, le
 * toca. Comparar el minuto exacto no serviría —la tarea no corre a los 30
 * minutos— y comparar solo la hora sin ventana haría que un recordatorio a las
 * 20:59 se perdiera.
 */
export function isReminderDue(
  reminderTime: string | undefined,
  localMinutes: number,
): boolean {
  const target = minutesOfDay(reminderTime ?? '20:00');
  if (target === null) {
    return false;
  }
  const currentHour = Math.floor(localMinutes / 60);
  const targetHour = Math.floor(target / 60);
  return currentHour === targetHour;
}

/**
 * Clave con la que se agrupan las notificaciones sociales.
 *
 * Cincuenta likes en la misma publicación tienen que producir **una**
 * notificación que diga "50 personas", no cincuenta. Sin esto, una publicación
 * que funciona bien se convierte en un castigo para su autor y en la razón por
 * la que apaga las notificaciones para siempre.
 *
 * La clave incluye el día: agrupar los likes de hoy con los de la semana pasada
 * daría un contador que nunca deja de crecer y una notificación que nunca se
 * siente nueva.
 */
export function groupKeyFor(
  type: NotificationType,
  targetId: string,
  dayKey: string,
): string | null {
  if (!targetId) {
    return null;
  }
  if (type !== 'new_like' && type !== 'new_comment') {
    return null;
  }
  return `${type}__${targetId}__${dayKey}`;
}

/**
 * Texto de una notificación social agrupada.
 *
 * La pluralización en español no es "agregar una s": "1 persona" y "2 personas"
 * cambian el verbo que las acompaña.
 */
export function groupedSocialBody(
  type: NotificationType,
  count: number,
  firstName: string | null,
): string {
  const plural = type === 'new_comment' ? 'comentaron' : 'les gustó';
  const singular = type === 'new_comment' ? 'comentó' : 'le gustó';

  if (count <= 1) {
    return `${firstName ?? 'Alguien'} ${singular} tu publicación.`;
  }
  if (firstName === null) {
    return `A ${count} personas ${plural} tu publicación.`;
  }
  const others = count - 1;
  const suffix = others === 1 ? 'persona más' : 'personas más';
  return `${firstName} y ${others} ${suffix} ${plural} tu publicación.`;
}

/** Cuerpo del recordatorio diario, según cuántas misiones queden. */
export function reminderBody(pendingToday: number): string {
  if (pendingToday <= 0) {
    // No se envía nada en este caso; el texto existe para que la función que
    // decide no tenga que inventar uno si algún día cambia el criterio.
    return 'Hoy no te queda nada pendiente. Bien ahí.';
  }
  if (pendingToday === 1) {
    return 'Te queda una misión para hoy. Son cinco minutos.';
  }
  return `Te quedan ${pendingToday} misiones para hoy.`;
}

/** Cuerpo del aviso de racha en riesgo. */
export function streakWarningBody(streak: number): string {
  return streak === 1
    ? 'Empezaste una racha ayer. No la cortes hoy.'
    : `Llevás ${streak} días seguidos. Te quedan pocas horas para sostenerlo.`;
}

/**
 * Día calendario (`YYYY-MM-DD`) de una fecha en una zona horaria dada.
 *
 * Comparar días en UTC daría mal para casi todo el continente: a las 22:00 de
 * Buenos Aires ya es el día siguiente en UTC, así que una racha se daría por
 * rota dos horas antes de que terminara el día de esa persona.
 */
export function dayKeyIn(timezone: string, date: Date): string {
  try {
    // `en-CA` produce YYYY-MM-DD, que es exactamente el formato que usamos
    // como clave de día en el resto del sistema.
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(date);
  } catch {
    return date.toISOString().slice(0, 10);
  }
}

/**
 * `true` si la racha se pierde hoy salvo que la persona haga algo.
 *
 * Exige racha viva y ninguna actividad registrada en el día local en curso. Sin
 * la segunda condición, el aviso llegaría también a quien ya cumplió — que es
 * el aviso que enseña a ignorar los avisos.
 */
export function isStreakAtRisk(input: {
  currentStreak: number;
  lastActivityDayKey: string | null;
  todayDayKey: string;
}): boolean {
  return (
    input.currentStreak > 0 && input.lastActivityDayKey !== input.todayDayKey
  );
}
