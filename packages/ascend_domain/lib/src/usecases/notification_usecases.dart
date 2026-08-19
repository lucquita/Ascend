/// Notificaciones: qué se manda, cuándo y a quién.
///
/// Toda la decisión vive acá, en Dart puro. El servidor aplica las mismas
/// reglas —hay una copia en TypeScript— porque una notificación se envía desde
/// el backend, pero tenerlas escritas y probadas de este lado permite que la
/// app decida sin ir a la red y que las reglas se puedan verificar sin
/// emuladores.
///
/// La regla que ordena todo: **una notificación que molesta se desactiva, y
/// entonces se pierden también las que servían**. Cada envío que no aporta
/// cuesta más que el que se ahorra.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/app_user.dart';
import 'package:ascend_domain/src/entities/category.dart';
import 'package:ascend_domain/src/enums/enums.dart';
import 'package:ascend_domain/src/repositories/repositories.dart';
import 'package:meta/meta.dart';

/// Minutos desde la medianoche de un `HH:mm`.
///
/// Devuelve `null` si el texto no tiene esa forma. Nunca lanza: el valor sale
/// del perfil, que lo puede haber escrito una versión vieja de la app.
int? minutesOfDay(String? time) {
  if (time == null) {
    return null;
  }
  final parts = time.split(':');
  if (parts.length != 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/// `true` si [now] cae dentro del horario de silencio.
///
/// ## El caso que se rompe siempre
///
/// El horario de silencio normal es **nocturno**: 22:00 a 07:00. Ahí el inicio
/// es mayor que el fin, y la comparación ingenua `inicio <= t && t < fin` da
/// `false` para toda la noche —justo cuando había que callarse—. Por eso la
/// ventana que cruza la medianoche se evalúa al revés.
///
/// Sin horario configurado, o con uno mal formado, no hay silencio: ante la
/// duda se entrega, porque un recordatorio de más molesta menos que una racha
/// perdida en silencio.
bool isWithinQuietHours({
  required DateTime now,
  required String? start,
  required String? end,
}) {
  final from = minutesOfDay(start);
  final to = minutesOfDay(end);
  if (from == null || to == null || from == to) {
    return false;
  }

  final current = now.hour * 60 + now.minute;
  return from < to
      ? current >= from && current < to
      // Ventana nocturna: vale desde el inicio hasta medianoche, y desde
      // medianoche hasta el fin.
      : current >= from || current < to;
}

/// `true` si el tipo está habilitado en las preferencias.
///
/// Los tipos sin interruptor propio —subida de nivel, moderación, anuncios— no
/// se pueden apagar por diseño: son pocos, no se repiten y avisan de algo que
/// afecta a la cuenta. Un aviso de moderación silenciado dejaría a alguien sin
/// entender por qué desapareció su publicación.
bool isTypeEnabled(NotificationType type, NotificationSettings settings) =>
    switch (type) {
      NotificationType.missionReminder => settings.dailyReminder,
      NotificationType.streakWarning => settings.streakAlerts,
      NotificationType.newLike ||
      NotificationType.newComment ||
      NotificationType.newFollower => settings.socialActivity,
      NotificationType.aiSuggestion => settings.aiSuggestions,
      NotificationType.auraGained ||
      NotificationType.levelUp ||
      NotificationType.moderationAction ||
      NotificationType.system => true,
    };

/// Qué hacer con una notificación que está por enviarse.
enum NotificationDelivery {
  /// Se envía como push.
  push,

  /// Se guarda en la bandeja, pero sin push.
  ///
  /// Es lo que corresponde en horario de silencio: la información no se pierde,
  /// simplemente no suena el teléfono a las tres de la mañana.
  inboxOnly,

  /// No se genera nada: la persona apagó ese tipo.
  drop,
}

/// Decide qué hacer con una notificación.
NotificationDelivery resolveDelivery({
  required NotificationType type,
  required NotificationSettings settings,
  required DateTime localNow,
}) {
  if (!isTypeEnabled(type, settings)) {
    return NotificationDelivery.drop;
  }
  // El silencio no descarta: guarda sin sonar. Descartar haría que alguien se
  // enterara de un comentario solo si abre la app justo ese día.
  if (isWithinQuietHours(
    now: localNow,
    start: settings.quietHoursStart,
    end: settings.quietHoursEnd,
  )) {
    return NotificationDelivery.inboxOnly;
  }
  return NotificationDelivery.push;
}

/// Clave con la que se agrupan las notificaciones sociales.
///
/// Cincuenta likes en la misma publicación tienen que producir **una**
/// notificación que diga "50 personas", no cincuenta. Sin esto, una publicación
/// que funciona bien se convierte en un castigo para su autor y en la razón por
/// la que apaga las notificaciones para siempre.
///
/// La clave incluye el día: agrupar likes de hoy con los de la semana pasada
/// daría un contador que nunca deja de crecer y una notificación que nunca se
/// siente nueva.
String? groupKeyFor({
  required NotificationType type,
  required String? targetId,
  required DateTime day,
}) {
  if (targetId == null || targetId.isEmpty) {
    return null;
  }
  final agrupable =
      type == NotificationType.newLike || type == NotificationType.newComment;
  if (!agrupable) {
    return null;
  }
  return '${type.wireValue}__${targetId}__${AscendDateUtils.toDayKey(day)}';
}

/// Texto de una notificación social agrupada.
///
/// Se escribe acá y no en la plantilla del servidor porque la pluralización en
/// español no es "agregar una s": "1 persona" y "2 personas" cambian el verbo.
String groupedSocialBody({
  required NotificationType type,
  required int count,
  required String? firstName,
}) {
  final accion = type == NotificationType.newComment
      ? 'comentaron'
      : 'les gustó';
  final accionSingular = type == NotificationType.newComment
      ? 'comentó'
      : 'le gustó';

  if (count <= 1) {
    final quien = firstName ?? 'Alguien';
    return '$quien $accionSingular tu publicación.';
  }
  if (firstName == null) {
    return 'A $count personas $accion tu publicación.';
  }
  final otros = count - 1;
  return '$firstName y $otros ${otros == 1 ? 'persona más' : 'personas más'} '
      '$accion tu publicación.';
}

/// Permiso del sistema para mostrar notificaciones.
enum NotificationPermission {
  /// Todavía no se preguntó.
  notDetermined,

  /// Concedido.
  granted,

  /// Denegado.
  denied,

  /// Denegado de forma permanente: hay que ir a los ajustes del sistema.
  permanentlyDenied,
}

/// `true` si conviene mostrar la explicación previa antes de pedir el permiso.
///
/// ## Por qué existe la explicación previa
///
/// El diálogo del sistema se puede mostrar **una sola vez**. Si se lanza al
/// abrir la app, antes de que la persona entienda para qué sirve, la mayoría lo
/// rechaza — y ese rechazo es definitivo: recuperarlo exige ir a los ajustes del
/// sistema, que casi nadie hace.
///
/// Mostrando primero una pantalla propia se puede insistir más adelante sin
/// gastar la única oportunidad.
bool shouldExplainBeforeAsking(NotificationPermission permission) =>
    permission == NotificationPermission.notDetermined;

/// Cantidad de notificaciones sin leer, acotada para mostrar en una insignia.
///
/// Por encima de 99 se muestra "99+": el número exacto deja de aportar y una
/// insignia de cuatro dígitos rompe el diseño.
@immutable
class UnreadBadge {
  /// Crea la insignia.
  const UnreadBadge(this.count);

  /// Cantidad real.
  final int count;

  /// `true` si hay algo que mostrar.
  bool get isVisible => count > 0;

  /// Texto de la insignia.
  String get label => count > 99 ? '99+' : '$count';
}

/// Marca una notificación como leída y navega a su destino.
class OpenNotificationUseCase {
  /// Crea el caso de uso.
  const OpenNotificationUseCase(this._notifications);

  final NotificationRepository _notifications;

  /// Marca como leída y devuelve la ruta a la que ir, si la hay.
  ///
  /// Marcar y navegar van juntos porque separarlos deja el caso en que se
  /// navega y no se marca: la insignia sigue mostrando un número que ya no
  /// corresponde a nada.
  ///
  /// Un fallo al marcar **no** impide navegar: llegar a la pantalla es lo que
  /// la persona pidió; que la insignia quede un rato desactualizada es menor.
  Future<String?> call({
    required String uid,
    required AppNotification notification,
  }) async {
    if (!notification.read) {
      await _notifications.markAsRead(uid: uid, id: notification.id);
    }
    return notification.route;
  }
}

/// Pide el permiso de notificaciones y registra el dispositivo.
class EnableNotificationsUseCase {
  /// Crea el caso de uso.
  const EnableNotificationsUseCase(this._notifications);

  final NotificationRepository _notifications;

  /// Pide permiso y, si lo conceden, registra el dispositivo.
  ///
  /// Devuelve el estado final para que la pantalla pueda explicar qué pasó.
  /// Registrar el token sin permiso no serviría de nada: el sistema descarta
  /// las push igual, y quedaría un token muerto acumulando envíos fallidos.
  Future<NotificationPermission> call(String uid) async {
    final permission = await _notifications.requestPermission();
    if (permission == NotificationPermission.granted) {
      await _notifications.registerDeviceToken(uid);
    }
    return permission;
  }
}
