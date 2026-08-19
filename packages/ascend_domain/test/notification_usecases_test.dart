import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

class _FakeNotificationRepository implements NotificationRepository {
  NotificationPermission next = NotificationPermission.granted;
  final List<String> marked = <String>[];
  int registrations = 0;

  @override
  Future<NotificationPermission> permissionStatus() async => next;

  @override
  Future<NotificationPermission> requestPermission() async => next;

  @override
  Future<Result<void>> registerDeviceToken(String uid) async {
    registrations++;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> unregisterDeviceToken(String uid) async =>
      const Success<void>(null);

  @override
  Future<Result<void>> markAsRead({
    required String uid,
    required String id,
  }) async {
    marked.add(id);
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> markAllAsRead(String uid) async =>
      const Success<void>(null);

  @override
  Stream<Result<List<AppNotification>>> watchNotifications(String uid) =>
      const Stream<Result<List<AppNotification>>>.empty();

  @override
  Stream<int> watchUnreadCount(String uid) => const Stream<int>.empty();
}

AppNotification _notification({
  bool read = false,
  Map<String, String> data = const <String, String>{},
}) => AppNotification(
  id: 'n1',
  type: NotificationType.newLike,
  title: 'Nuevo like',
  body: 'A alguien le gustó tu publicación.',
  createdAt: DateTime.utc(2026, 8, 17),
  data: data,
  read: read,
);

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 8, 17, hour, minute);

void main() {
  group('minutesOfDay', () {
    test('convierte un HH:mm válido', () {
      expect(minutesOfDay('20:30'), 20 * 60 + 30);
      expect(minutesOfDay('00:00'), 0);
      expect(minutesOfDay('23:59'), 23 * 60 + 59);
    });

    test('un texto inválido devuelve null en vez de lanzar', () {
      // El valor sale del perfil, que lo pudo escribir una versión vieja.
      for (final bad in <String?>[
        null,
        '',
        'ayer',
        '25:00',
        '10:70',
        '10',
        '10:30:00',
        '-1:00',
      ]) {
        expect(minutesOfDay(bad), isNull, reason: 'con "$bad"');
      }
    });
  });

  group('isWithinQuietHours', () {
    test('una ventana diurna se evalúa directo', () {
      expect(
        isWithinQuietHours(now: _at(14), start: '13:00', end: '16:00'),
        isTrue,
      );
      expect(
        isWithinQuietHours(now: _at(17), start: '13:00', end: '16:00'),
        isFalse,
      );
    });

    test('una ventana NOCTURNA cubre toda la noche', () {
      // Es el caso que se rompe siempre: con 22:00–07:00, la comparación
      // ingenua da false durante toda la noche, justo cuando había que
      // callarse.
      for (final hour in <int>[22, 23, 0, 3, 6]) {
        expect(
          isWithinQuietHours(now: _at(hour), start: '22:00', end: '07:00'),
          isTrue,
          reason: 'a las $hour debería estar en silencio',
        );
      }
    });

    test('fuera de la ventana nocturna no hay silencio', () {
      for (final hour in <int>[7, 12, 21]) {
        expect(
          isWithinQuietHours(now: _at(hour), start: '22:00', end: '07:00'),
          isFalse,
          reason: 'a las $hour debería sonar',
        );
      }
    });

    test('el límite de inicio silencia y el de fin ya no', () {
      expect(
        isWithinQuietHours(now: _at(22), start: '22:00', end: '07:00'),
        isTrue,
      );
      expect(
        isWithinQuietHours(now: _at(7), start: '22:00', end: '07:00'),
        isFalse,
      );
    });

    test('sin horario configurado no hay silencio', () {
      // Ante la duda se entrega: un recordatorio de más molesta menos que una
      // racha perdida en silencio.
      expect(isWithinQuietHours(now: _at(3), start: null, end: null), isFalse);
      expect(
        isWithinQuietHours(now: _at(3), start: '22:00', end: null),
        isFalse,
      );
      expect(
        isWithinQuietHours(now: _at(3), start: 'ayer', end: 'hoy'),
        isFalse,
      );
    });

    test('un inicio igual al fin no silencia las 24 horas', () {
      // Interpretarlo como "todo el día en silencio" apagaría las
      // notificaciones sin que nadie entienda por qué.
      expect(
        isWithinQuietHours(now: _at(12), start: '22:00', end: '22:00'),
        isFalse,
      );
    });
  });

  group('isTypeEnabled', () {
    const allOff = NotificationSettings(
      dailyReminder: false,
      streakAlerts: false,
      socialActivity: false,
      aiSuggestions: false,
    );

    test('cada interruptor apaga su tipo', () {
      expect(isTypeEnabled(NotificationType.missionReminder, allOff), isFalse);
      expect(isTypeEnabled(NotificationType.streakWarning, allOff), isFalse);
      expect(isTypeEnabled(NotificationType.newLike, allOff), isFalse);
      expect(isTypeEnabled(NotificationType.aiSuggestion, allOff), isFalse);
    });

    test('un solo interruptor cubre toda la actividad social', () {
      for (final type in <NotificationType>[
        NotificationType.newLike,
        NotificationType.newComment,
        NotificationType.newFollower,
      ]) {
        expect(isTypeEnabled(type, allOff), isFalse);
      }
    });

    test('moderación y sistema NO se pueden apagar', () {
      // Un aviso de moderación silenciado dejaría a alguien sin entender por
      // qué desapareció su publicación.
      expect(isTypeEnabled(NotificationType.moderationAction, allOff), isTrue);
      expect(isTypeEnabled(NotificationType.system, allOff), isTrue);
      expect(isTypeEnabled(NotificationType.levelUp, allOff), isTrue);
    });

    test('por defecto todo lo opcional está encendido', () {
      const defaults = NotificationSettings();
      for (final type in NotificationType.values) {
        expect(isTypeEnabled(type, defaults), isTrue);
      }
    });
  });

  group('resolveDelivery', () {
    const quiet = NotificationSettings(
      quietHoursStart: '22:00',
      quietHoursEnd: '07:00',
    );

    test('fuera del silencio, con el tipo activo, se manda push', () {
      expect(
        resolveDelivery(
          type: NotificationType.newLike,
          settings: quiet,
          localNow: _at(12),
        ),
        NotificationDelivery.push,
      );
    });

    test('en silencio se guarda en la bandeja, NO se descarta', () {
      // Descartar haría que alguien se entere de un comentario solo si abre la
      // app justo ese día.
      expect(
        resolveDelivery(
          type: NotificationType.newLike,
          settings: quiet,
          localNow: _at(3),
        ),
        NotificationDelivery.inboxOnly,
      );
    });

    test('un tipo apagado se descarta del todo', () {
      expect(
        resolveDelivery(
          type: NotificationType.newLike,
          settings: const NotificationSettings(socialActivity: false),
          localNow: _at(12),
        ),
        NotificationDelivery.drop,
      );
    });

    test('el interruptor pesa más que el silencio', () {
      // Si estuviera al revés, un tipo apagado seguiría llenando la bandeja.
      expect(
        resolveDelivery(
          type: NotificationType.newLike,
          settings: const NotificationSettings(
            socialActivity: false,
            quietHoursStart: '22:00',
            quietHoursEnd: '07:00',
          ),
          localNow: _at(3),
        ),
        NotificationDelivery.drop,
      );
    });

    test('la moderación llega igual en horario de silencio, sin sonar', () {
      expect(
        resolveDelivery(
          type: NotificationType.moderationAction,
          settings: quiet,
          localNow: _at(3),
        ),
        NotificationDelivery.inboxOnly,
      );
    });
  });

  group('groupKeyFor', () {
    final day = DateTime.utc(2026, 8, 17);

    test('los likes de una publicación y un día comparten clave', () {
      final a = groupKeyFor(
        type: NotificationType.newLike,
        targetId: 'p1',
        day: day,
      );
      final b = groupKeyFor(
        type: NotificationType.newLike,
        targetId: 'p1',
        day: day,
      );
      expect(a, isNotNull);
      expect(a, b);
    });

    test('publicaciones distintas no se agrupan entre sí', () {
      expect(
        groupKeyFor(type: NotificationType.newLike, targetId: 'p1', day: day),
        isNot(
          groupKeyFor(type: NotificationType.newLike, targetId: 'p2', day: day),
        ),
      );
    });

    test('un like y un comentario no se mezclan', () {
      expect(
        groupKeyFor(type: NotificationType.newLike, targetId: 'p1', day: day),
        isNot(
          groupKeyFor(
            type: NotificationType.newComment,
            targetId: 'p1',
            day: day,
          ),
        ),
      );
    });

    test('cada día empieza un grupo nuevo', () {
      // Sin esto el contador nunca deja de crecer y la notificación nunca se
      // siente nueva.
      expect(
        groupKeyFor(type: NotificationType.newLike, targetId: 'p1', day: day),
        isNot(
          groupKeyFor(
            type: NotificationType.newLike,
            targetId: 'p1',
            day: day.add(const Duration(days: 1)),
          ),
        ),
      );
    });

    test('lo que no se agrupa devuelve null', () {
      expect(
        groupKeyFor(
          type: NotificationType.newFollower,
          targetId: 'u1',
          day: day,
        ),
        isNull,
      );
      expect(
        groupKeyFor(type: NotificationType.newLike, targetId: null, day: day),
        isNull,
      );
      expect(
        groupKeyFor(type: NotificationType.newLike, targetId: '', day: day),
        isNull,
      );
    });
  });

  group('groupedSocialBody', () {
    test('con una sola persona usa el singular', () {
      expect(
        groupedSocialBody(
          type: NotificationType.newLike,
          count: 1,
          firstName: 'Ana',
        ),
        'Ana le gustó tu publicación.',
      );
    });

    test('con varias nombra a una y cuenta el resto', () {
      // 50 likes tienen que producir UNA notificación, no 50.
      expect(
        groupedSocialBody(
          type: NotificationType.newLike,
          count: 50,
          firstName: 'Ana',
        ),
        'Ana y 49 personas más les gustó tu publicación.',
      );
    });

    test('con dos, el resto va en singular', () {
      // La pluralización en español no es "agregar una s".
      expect(
        groupedSocialBody(
          type: NotificationType.newComment,
          count: 2,
          firstName: 'Ana',
        ),
        contains('1 persona más'),
      );
    });

    test('sin nombre no inventa uno', () {
      expect(
        groupedSocialBody(
          type: NotificationType.newLike,
          count: 3,
          firstName: null,
        ),
        'A 3 personas les gustó tu publicación.',
      );
      expect(
        groupedSocialBody(
          type: NotificationType.newLike,
          count: 1,
          firstName: null,
        ),
        startsWith('Alguien'),
      );
    });

    test('distingue like de comentario', () {
      expect(
        groupedSocialBody(
          type: NotificationType.newComment,
          count: 1,
          firstName: 'Ana',
        ),
        contains('comentó'),
      );
    });
  });

  group('shouldExplainBeforeAsking', () {
    test('solo antes de haber preguntado', () {
      // El diálogo del sistema se muestra una única vez: gastarlo sin contexto
      // convierte el rechazo en definitivo.
      expect(
        shouldExplainBeforeAsking(NotificationPermission.notDetermined),
        isTrue,
      );
      expect(
        shouldExplainBeforeAsking(NotificationPermission.granted),
        isFalse,
      );
      expect(
        shouldExplainBeforeAsking(NotificationPermission.permanentlyDenied),
        isFalse,
      );
    });
  });

  group('UnreadBadge', () {
    test('sin nada sin leer no se muestra', () {
      expect(const UnreadBadge(0).isVisible, isFalse);
    });

    test('acota en 99+', () {
      // Una insignia de cuatro dígitos rompe el diseño y el número exacto ya
      // no aporta.
      expect(const UnreadBadge(5).label, '5');
      expect(const UnreadBadge(99).label, '99');
      expect(const UnreadBadge(1200).label, '99+');
    });
  });

  group('OpenNotificationUseCase', () {
    late _FakeNotificationRepository notifications;

    setUp(() => notifications = _FakeNotificationRepository());

    test('marca como leída y devuelve el destino', () async {
      final route = await OpenNotificationUseCase(notifications).call(
        uid: 'u1',
        notification: _notification(
          data: const <String, String>{'route': '/missions/m1'},
        ),
      );

      expect(route, '/missions/m1');
      expect(notifications.marked, <String>['n1']);
    });

    test('una ya leída no se vuelve a marcar', () async {
      await OpenNotificationUseCase(
        notifications,
      ).call(uid: 'u1', notification: _notification(read: true));

      expect(notifications.marked, isEmpty);
    });

    test('sin ruta devuelve null y no rompe', () async {
      final route = await OpenNotificationUseCase(
        notifications,
      ).call(uid: 'u1', notification: _notification());

      expect(route, isNull);
      expect(notifications.marked, <String>['n1']);
    });
  });

  group('EnableNotificationsUseCase', () {
    late _FakeNotificationRepository notifications;

    setUp(() => notifications = _FakeNotificationRepository());

    test('con permiso concedido registra el dispositivo', () async {
      final result = await EnableNotificationsUseCase(notifications).call('u1');

      expect(result, NotificationPermission.granted);
      expect(notifications.registrations, 1);
    });

    test('sin permiso NO registra el token', () async {
      // Un token sin permiso acumula envíos fallidos: el sistema descarta las
      // push igual.
      notifications.next = NotificationPermission.denied;

      final result = await EnableNotificationsUseCase(notifications).call('u1');

      expect(result, NotificationPermission.denied);
      expect(notifications.registrations, 0);
    });
  });
}
