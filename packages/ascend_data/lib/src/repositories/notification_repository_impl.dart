import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/remote/firebase_messaging_datasource.dart';
import 'package:ascend_data/src/dtos/notification_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Implementación de [NotificationRepository].
///
/// ## La bandeja no depende de FCM
///
/// Las notificaciones se leen de `users/{uid}/notifications`, que escribe el
/// servidor. FCM solo aporta el **aviso**: el sonido y la burbuja del sistema.
///
/// Separarlo así tiene una consecuencia práctica importante: sin permiso de
/// notificaciones, sin token o sin conexión en el momento del envío, la
/// información **no se pierde**. Está en la bandeja la próxima vez que se abre
/// la app. Si la bandeja dependiera de las push, rechazar el permiso equivaldría
/// a no enterarse nunca de nada.
class NotificationRepositoryImpl implements NotificationRepository {
  /// Crea el repositorio.
  const NotificationRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseMessagingDataSource messaging,
  }) : _firestore = firestore,
       _messaging = messaging;

  final FirebaseFirestore _firestore;
  final FirebaseMessagingDataSource _messaging;

  CollectionReference<Map<String, dynamic>> _inbox(String uid) =>
      _firestore.collection('users').doc(uid).collection('notifications');

  @override
  Stream<Result<List<AppNotification>>> watchNotifications(String uid) =>
      guardStream(
        _inbox(uid)
            .orderBy('createdAt', descending: true)
            // 50 alcanza para una bandeja: nadie baja más que eso, y las
            // viejas se borran solas por la política TTL de `expiresAt`.
            .limit(50)
            .snapshots()
            .map(
              (snapshot) => <AppNotification>[
                for (final doc in snapshot.docs)
                  NotificationDto.fromFirestore(doc),
              ],
            ),
      );

  @override
  Stream<int> watchUnreadCount(String uid) => _inbox(uid)
      .where('read', isEqualTo: false)
      .limit(100)
      .snapshots()
      // Devuelve `int` y no `Result<int>` por contrato del puerto: una insignia
      // que no se puede leer es simplemente una insignia en cero, no un error
      // que valga la pena mostrar en pantalla.
      .map((snapshot) => snapshot.docs.length)
      .handleError((Object error) {
        const AscendLogger(
          'notifications',
        ).warning('No se pudo contar las no leídas', error: error);
      });

  @override
  Future<Result<void>> markAsRead({
    required String uid,
    required String id,
  }) => runGuarded(() async {
    // Escritura parcial: las reglas solo permiten tocar `read`. Un `set` con
    // el documento entero se rechazaría.
    await _inbox(uid).doc(id).update(<String, Object?>{'read': true});
  });

  @override
  Future<Result<void>> markAllAsRead(String uid) => runGuarded(() async {
    final pending = await _inbox(uid)
        .where('read', isEqualTo: false)
        // Un lote de Firestore admite 500 operaciones. Acotar acá evita que
        // una bandeja abandonada durante meses rompa la operación entera.
        .limit(400)
        .get();

    if (pending.docs.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    for (final doc in pending.docs) {
      batch.update(doc.reference, <String, Object?>{'read': true});
    }
    await batch.commit();
  });

  @override
  Future<NotificationPermission> permissionStatus() =>
      _messaging.permissionStatus();

  @override
  Future<NotificationPermission> requestPermission() =>
      _messaging.requestPermission();

  @override
  Future<Result<void>> registerDeviceToken(String uid) => runGuarded(() async {
    final token = await _messaging.token();
    if (token == null) {
      // Sin token no hay nada que registrar. No es un error: la app funciona
      // igual, solo que sin avisos del sistema.
      return;
    }

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(token)
        .set(<String, Object?>{
          'token': token,
          // La fecha del último uso es lo que permite limpiar tokens muertos:
          // un dispositivo que no se abre hace seis meses acumula envíos
          // fallidos que igual se pagan.
          'lastSeenAt': FieldValue.serverTimestamp(),
          'platform': defaultTargetPlatformName,
        }, SetOptions(merge: true));
  });

  @override
  Future<Result<void>> unregisterDeviceToken(String uid) =>
      runGuarded(() async {
        final token = await _messaging.token();
        if (token != null) {
          await _firestore
              .collection('users')
              .doc(uid)
              .collection('fcmTokens')
              .doc(token)
              .delete();
        }
        // Se borra también en FCM: si solo se borrara el documento, el
        // dispositivo seguiría teniendo un token válido y volvería a
        // registrarse solo al refrescarse.
        await _messaging.deleteToken();
      });
}

/// Nombre de la plataforma actual, para poder segmentar envíos.
///
/// Se calcula sin importar `dart:io` —que no existe en web— ni
/// `defaultTargetPlatform` de Flutter, que obligaría a que la capa de datos
/// dependiera del framework.
String get defaultTargetPlatformName {
  if (const bool.fromEnvironment('dart.library.js_interop')) {
    return 'web';
  }
  return 'mobile';
}
