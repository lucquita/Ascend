import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado del permiso del sistema, releído bajo demanda.
///
/// Es un `FutureProvider` y no un valor guardado porque el permiso se puede
/// cambiar desde los ajustes del sistema operativo, fuera de la app: cualquier
/// copia local queda vieja sin que nadie se entere.
final FutureProvider<NotificationPermission> notificationPermissionProvider =
    FutureProvider<NotificationPermission>(
      (ref) => ref.watch(notificationRepositoryProvider).permissionStatus(),
      name: 'notificationPermission',
    );

/// Acciones sobre la bandeja y el permiso.
class NotificationsController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Marca una notificación como leída y devuelve su destino.
  ///
  /// Devuelve `null` si no hay a dónde ir. Nunca lanza: un fallo al marcar no
  /// puede impedir que se abra la pantalla, que es lo que la persona pidió.
  Future<String?> open(AppNotification notification) async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) {
      return notification.route;
    }
    return ref
        .read(openNotificationUseCaseProvider)
        .call(uid: uid, notification: notification);
  }

  /// Marca todas como leídas.
  Future<bool> markAllRead() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) {
      return false;
    }
    state = const AsyncLoading<void>();
    final result = await guardResult(
      () => ref.read(notificationRepositoryProvider).markAllAsRead(uid),
    );

    return result.fold(
      onSuccess: (_) {
        state = const AsyncData<void>(null);
        return true;
      },
      onFailure: (Failure failure) {
        state = AsyncError<void>(
          failure,
          failure.stackTrace ?? StackTrace.empty,
        );
        return false;
      },
    );
  }

  /// Pide el permiso y registra el dispositivo si lo conceden.
  Future<NotificationPermission> enable() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) {
      return NotificationPermission.denied;
    }

    final permission = await ref
        .read(enableNotificationsUseCaseProvider)
        .call(uid);
    // El estado del permiso se relee: la pantalla tiene que reflejar lo que
    // realmente pasó, no lo que se pidió.
    ref.invalidate(notificationPermissionProvider);
    return permission;
  }

  /// Descarta el error mostrado.
  void clearError() {
    if (state.hasError) {
      state = const AsyncData<void>(null);
    }
  }
}

/// Controlador de la bandeja.
final NotifierProvider<NotificationsController, AsyncValue<void>>
notificationsControllerProvider =
    NotifierProvider<NotificationsController, AsyncValue<void>>(
      NotificationsController.new,
      name: 'notificationsController',
    );

/// Guarda las preferencias de notificación del perfil.
class NotificationSettingsController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Aplica un cambio en las preferencias.
  ///
  /// Escribe **solo** el bloque `settings`, no el perfil entero: mandar todo
  /// pisaría campos que mantiene el servidor —Aura, estadísticas, rol— y las
  /// reglas lo rechazarían de todos modos.
  ///
  /// Parte de los ajustes actuales del perfil para no borrar el tema, el idioma
  /// ni el huso horario al tocar un interruptor de notificaciones.
  Future<bool> save(NotificationSettings notifications) async {
    // El uid sale del propio perfil y no de `authStateProvider`: el perfil ya
    // hace falta para no pisar el resto de los ajustes, y leer el mismo dato de
    // dos fuentes abre la puerta a que una esté lista y la otra todavía no.
    final profile = ref.read(profileProvider).value?.valueOrNull;
    if (profile == null) {
      return false;
    }

    state = const AsyncLoading<void>();
    final result = await guardResult(
      () => ref
          .read(userRepositoryProvider)
          .updateSettings(
            uid: profile.uid,
            settings: profile.settings.copyWith(notifications: notifications),
          ),
    );

    return result.fold(
      onSuccess: (_) {
        state = const AsyncData<void>(null);
        return true;
      },
      onFailure: (Failure failure) {
        state = AsyncError<void>(
          failure,
          failure.stackTrace ?? StackTrace.empty,
        );
        return false;
      },
    );
  }
}

/// Controlador de las preferencias de notificación.
final NotifierProvider<NotificationSettingsController, AsyncValue<void>>
notificationSettingsControllerProvider =
    NotifierProvider<NotificationSettingsController, AsyncValue<void>>(
      NotificationSettingsController.new,
      name: 'notificationSettingsController',
    );
