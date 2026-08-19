import 'dart:async';

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Conecta las notificaciones del sistema con la navegación de la app.
///
/// Envuelve al árbol y no vive en una pantalla porque tiene que estar escuchando
/// desde el arranque: la push puede llegar en cualquier momento, y la que abrió
/// la app estando cerrada solo se puede leer una vez, al principio.
///
/// ## Los tres estados de una push
///
/// | Estado de la app | Cómo llega |
/// |---|---|
/// | En primer plano | No abre nada sola: interrumpir a alguien que está usando la app es peor que esperar. El contador de la campana se actualiza solo, porque escucha Firestore. |
/// | En segundo plano | `openedMessages()` emite al tocarla. |
/// | Cerrada | `initialMessage()` la entrega en el arranque. |
///
/// El tercer caso es el que se olvida siempre, y es justamente el que pide el
/// criterio de aceptación: tocar una push con la app cerrada tiene que abrir la
/// pantalla exacta, no la inicial.
class PushDeepLinks extends ConsumerStatefulWidget {
  /// Envuelve [child] con la escucha de deep links.
  const PushDeepLinks({required this.child, super.key});

  /// Árbol de la aplicación.
  final Widget child;

  @override
  ConsumerState<PushDeepLinks> createState() => _PushDeepLinksState();
}

class _PushDeepLinksState extends ConsumerState<PushDeepLinks> {
  static const AscendLogger _logger = AscendLogger('pushDeepLinks');

  StreamSubscription<Map<String, String>>? _opened;
  StreamSubscription<String>? _tokenRefresh;
  bool _handledInitial = false;

  @override
  void initState() {
    super.initState();
    // Después del primer frame: navegar durante `initState` explota porque el
    // router todavía no está montado.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    final messaging = ref.read(firebaseMessagingDataSourceProvider);

    _opened = messaging.openedMessages().listen(_navigate);

    _tokenRefresh = messaging.tokenRefreshes().listen((_) {
      // El token rotó: se vuelve a registrar. Sin esto el dispositivo deja de
      // recibir push en silencio y nadie se entera hasta que alguien reclama.
      final uid = ref.read(authStateProvider).value?.uid;
      if (uid != null) {
        unawaited(
          ref.read(notificationRepositoryProvider).registerDeviceToken(uid),
        );
      }
    });

    unawaited(_handleInitial(messaging));
  }

  Future<void> _handleInitial(FirebaseMessagingDataSource messaging) async {
    if (_handledInitial) {
      return;
    }
    _handledInitial = true;
    final data = await messaging.initialMessage();
    if (data != null) {
      _navigate(data);
    }
  }

  void _navigate(Map<String, String> data) {
    final route = data['route'];
    if (route == null || route.isEmpty || !mounted) {
      return;
    }
    _logger.info('Deep link desde una notificación', context: data);
    // `push` y no `go`: la persona venía de afuera de la app, así que tiene que
    // poder volver atrás a la pantalla principal en vez de quedar encerrada.
    GoRouter.of(context).push(route);
  }

  @override
  void dispose() {
    unawaited(_opened?.cancel());
    unawaited(_tokenRefresh?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Registra el dispositivo cuando hay sesión y lo da de baja al cerrarla.
///
/// Va aparte del pedido de permiso: alguien que ya lo concedió en una sesión
/// anterior no tiene que volver a ver ningún diálogo, pero su token sí tiene
/// que quedar asociado a la cuenta con la que entró ahora.
///
/// Dar de baja al salir no es opcional: sin eso, el teléfono seguiría recibiendo
/// las notificaciones de la cuenta anterior, que en un dispositivo compartido es
/// una filtración de datos.
class DeviceRegistrar extends ConsumerStatefulWidget {
  /// Envuelve [child] con el registro del dispositivo.
  const DeviceRegistrar({required this.child, super.key});

  /// Árbol de la aplicación.
  final Widget child;

  @override
  ConsumerState<DeviceRegistrar> createState() => _DeviceRegistrarState();
}

class _DeviceRegistrarState extends ConsumerState<DeviceRegistrar> {
  String? _registeredUid;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppUser?>>(authStateProvider, (
      _,
      AsyncValue<AppUser?> next,
    ) {
      final uid = next.value?.uid;
      if (uid == _registeredUid) {
        return;
      }

      final repository = ref.read(notificationRepositoryProvider);
      final previous = _registeredUid;
      _registeredUid = uid;

      if (previous != null) {
        unawaited(repository.unregisterDeviceToken(previous));
      }
      if (uid != null) {
        // Solo si ya hay permiso: registrar un token sin permiso deja al
        // servidor mandando push que el sistema descarta, y cada envío
        // fallido igual se paga.
        unawaited(
          repository.permissionStatus().then((NotificationPermission status) {
            if (status == NotificationPermission.granted) {
              return repository.registerDeviceToken(uid);
            }
            return null;
          }),
        );
      }
    });

    return widget.child;
  }
}
