import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart' show NotificationPermission;
// `firebase_messaging` exporta su propio `NotificationSettings`, que colisiona
// con el del dominio (las preferencias de la persona). Se importa con prefijo.
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;

/// Acceso a Firebase Cloud Messaging.
///
/// ## Por qué envuelve al SDK en vez de usarlo directo
///
/// FCM **no existe en todas las plataformas ni en todos los entornos**: en un
/// test de widget no hay canal de plataforma, en web hace falta un service
/// worker y una clave VAPID, y sin `google-services.json` el SDK lanza al
/// primer uso. Envolverlo permite que todo eso se degrade en un `null` o en un
/// `NotificationPermission.denied` en vez de tumbar la app al arrancar.
///
/// Todos los métodos capturan y registran: ninguno lanza.
class FirebaseMessagingDataSource {
  /// Crea el datasource.
  FirebaseMessagingDataSource({fcm.FirebaseMessaging? messaging})
    : _messaging = messaging;

  static const AscendLogger _logger = AscendLogger('FirebaseMessaging');

  final fcm.FirebaseMessaging? _messaging;

  /// Instancia perezosa: pedirla antes de inicializar Firebase lanza.
  fcm.FirebaseMessaging? get _instance {
    if (_messaging != null) {
      return _messaging;
    }
    try {
      return fcm.FirebaseMessaging.instance;
    } on Object catch (error) {
      _logger.warning('FCM no disponible en este entorno', error: error);
      return null;
    }
  }

  /// Estado actual del permiso, sin pedir nada.
  Future<NotificationPermission> permissionStatus() async {
    final messaging = _instance;
    if (messaging == null) {
      return NotificationPermission.denied;
    }
    try {
      final settings = await messaging.getNotificationSettings();
      return _map(settings.authorizationStatus);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'No se pudo leer el permiso de notificaciones',
        error: error,
        stackTrace: stackTrace,
      );
      return NotificationPermission.denied;
    }
  }

  /// Pide el permiso al sistema.
  Future<NotificationPermission> requestPermission() async {
    final messaging = _instance;
    if (messaging == null) {
      return NotificationPermission.denied;
    }
    try {
      final settings = await messaging.requestPermission();
      return _map(settings.authorizationStatus);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Falló el pedido de permiso',
        error: error,
        stackTrace: stackTrace,
      );
      return NotificationPermission.denied;
    }
  }

  /// Token del dispositivo actual, o `null` si no se pudo obtener.
  Future<String?> token() async {
    final messaging = _instance;
    if (messaging == null) {
      return null;
    }
    try {
      return await messaging.getToken();
    } on Object catch (error, stackTrace) {
      // Sin token no hay push, pero la app sigue funcionando entera: la
      // bandeja in-app se alimenta de Firestore, no de FCM.
      _logger.warning(
        'No se pudo obtener el token de FCM',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Emite cuando el token se renueva.
  ///
  /// FCM rota el token solo —al reinstalar, al restaurar un backup, al limpiar
  /// los datos de la app—. Sin escuchar esto, el dispositivo deja de recibir
  /// push en silencio y nadie se entera hasta que alguien reclama.
  Stream<String> tokenRefreshes() {
    final messaging = _instance;
    if (messaging == null) {
      return const Stream<String>.empty();
    }
    try {
      return messaging.onTokenRefresh;
    } on Object catch (error) {
      _logger.warning('No se pudo escuchar la rotación', error: error);
      return const Stream<String>.empty();
    }
  }

  /// Borra el token del dispositivo. Se llama al cerrar sesión.
  ///
  /// Sin esto, el dispositivo seguiría recibiendo las notificaciones de la
  /// cuenta anterior — que es una filtración de datos en un teléfono
  /// compartido.
  Future<void> deleteToken() async {
    try {
      await _instance?.deleteToken();
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'No se pudo borrar el token',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static NotificationPermission _map(fcm.AuthorizationStatus status) =>
      switch (status) {
        fcm.AuthorizationStatus.authorized ||
        // "Provisional" es el permiso silencioso de iOS: las notificaciones
        // llegan directamente al centro de notificaciones sin sonar. Cuenta
        // como concedido: hay a dónde entregar.
        fcm.AuthorizationStatus.provisional => NotificationPermission.granted,
        fcm.AuthorizationStatus.denied => NotificationPermission.denied,
        fcm.AuthorizationStatus.notDetermined =>
          NotificationPermission.notDetermined,
      };
}

/// Notificación tocada por la persona, con sus datos.
///
/// Se expone como un mapa plano y no como el tipo de FCM para que la app pueda
/// leerlo sin depender del SDK de mensajería: el destino del deep link viaja en
/// `data['route']`, igual que en la bandeja.
extension MessagingDeepLinks on FirebaseMessagingDataSource {
  /// Emite cuando se toca una push con la app en segundo plano.
  Stream<Map<String, String>> openedMessages() {
    try {
      return fcm.FirebaseMessaging.onMessageOpenedApp.map(_dataOf);
    } on Object catch (error) {
      FirebaseMessagingDataSource._logger.warning(
        'No se pudo escuchar las push abiertas',
        error: error,
      );
      return const Stream<Map<String, String>>.empty();
    }
  }

  /// Push que abrió la app estando cerrada, si la hubo.
  ///
  /// Es un caso aparte del anterior: con la app terminada no hay stream vivo
  /// que escuchar, el mensaje viene en el arranque. Sin esto, tocar una push
  /// con la app cerrada abre la pantalla inicial en lugar de la misión, que es
  /// exactamente lo que el criterio de aceptación prohíbe.
  Future<Map<String, String>?> initialMessage() async {
    try {
      final message = await fcm.FirebaseMessaging.instance.getInitialMessage();
      return message == null ? null : _dataOf(message);
    } on Object catch (error) {
      FirebaseMessagingDataSource._logger.warning(
        'No se pudo leer la push inicial',
        error: error,
      );
      return null;
    }
  }

  static Map<String, String> _dataOf(fcm.RemoteMessage message) =>
      <String, String>{
        for (final entry in message.data.entries)
          if (entry.value is String) entry.key: entry.value as String,
      };
}
