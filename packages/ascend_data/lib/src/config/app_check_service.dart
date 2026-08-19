import 'package:ascend_core/ascend_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Activación de Firebase App Check.
///
/// ## Por qué esto es obligatorio y no opcional
///
/// Las cuatro Cloud Functions llamables de Ascend se despliegan con
/// `enforceAppCheck: true` (complemento del ADR-002). Sin un token de App Check
/// válido, el gate las rechaza **antes de ejecutar una sola línea** de la
/// función: el registro de una cuenta nueva falla y no hay forma de dar de alta
/// a nadie.
///
/// Eso fue exactamente el BUG-001: el paquete figuraba en `pubspec.yaml` pero
/// nunca se llamaba a `activate()`. Estaba instalado y jamás inicializado.
///
/// ## Proveedores según el entorno
///
/// | Entorno | Android | Apple |
/// |---|---|---|
/// | debug / profile | `debug` | `debug` |
/// | release | `playIntegrity` | `deviceCheck` |
///
/// El proveedor de depuración **no** debilita la seguridad de producción: los
/// tokens de depuración se registran uno por uno a mano en la consola de
/// Firebase y solo valen para el proyecto de desarrollo.
///
/// ## Paso manual que hay que hacer una vez por dispositivo
///
/// Al arrancar en modo depuración, el SDK imprime en el log una línea así:
///
/// ```
/// D DebugAppCheckProvider: Enter this debug secret into the allow list
/// in the Firebase Console for your project: 123e4567-e89b-...
/// ```
///
/// Ese token hay que pegarlo en **Firebase Console → App Check → Apps →
/// (tu app) → Administrar tokens de depuración**. Sin ese paso, las llamables
/// siguen rechazando al dispositivo aunque el código sea correcto.
abstract final class AppCheckService {
  static const AscendLogger _logger = AscendLogger('AppCheck');

  static bool _activated = false;

  /// `true` si App Check quedó activo.
  ///
  /// Las pantallas que invocan llamables lo consultan para poder explicar el
  /// motivo real cuando el servidor rechaza, en vez de mostrar un
  /// `unauthenticated` que no le dice nada a nadie.
  static bool get isActive => _activated;

  /// Activa App Check para el entorno actual.
  ///
  /// **Nunca lanza.** Si la activación falla, la app tiene que abrir igual y
  /// explicar el problema; un error de atestación no puede dejar a alguien
  /// mirando una pantalla en blanco. Devuelve `false` para que quien llame
  /// pueda registrarlo.
  ///
  /// [webRecaptchaSiteKey] es la clave de sitio de reCAPTCHA v3, necesaria solo
  /// en web. No es un secreto —viaja en el HTML de cualquier sitio que use
  /// reCAPTCHA—, pero se inyecta por `--dart-define` para no fijar en el código
  /// un valor que cambia entre proyectos.
  static Future<bool> activate({String? webRecaptchaSiteKey}) async {
    // Reactivar es innecesario y en algunas plataformas vuelve a pedir
    // atestación, que es una llamada de red que se paga en latencia de arranque.
    if (_activated) {
      return true;
    }

    // En depuración se usa el proveedor de debug: Play Integrity exige una app
    // firmada y publicada en Play, cosa que ningún build local cumple.
    const useDebugProvider = !kReleaseMode;

    try {
      // Se usan las clases `provider*` y no los parámetros `androidProvider` /
      // `appleProvider`: estos últimos están deprecados y el análisis del
      // proyecto corre con `--fatal-infos`, así que usarlos rompería CI.
      await FirebaseAppCheck.instance.activate(
        providerAndroid: useDebugProvider
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: useDebugProvider
            ? const AppleDebugProvider()
            : const AppleDeviceCheckProvider(),
        providerWeb: webRecaptchaSiteKey == null || webRecaptchaSiteKey.isEmpty
            ? null
            : ReCaptchaV3Provider(webRecaptchaSiteKey),
      );

      _activated = true;
      _logger.info(
        'App Check activado',
        context: <String, Object?>{
          'provider': useDebugProvider ? 'debug' : 'attestation',
        },
      );
      return true;
    } on Object catch (error, stackTrace) {
      _activated = false;
      // Se registra como error, no como aviso: con App Check caído, toda
      // llamable va a rechazar y el registro de cuentas deja de funcionar.
      _logger.error(
        'No se pudo activar App Check: las Cloud Functions llamables van a '
        'rechazar las peticiones de este dispositivo.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Reinicia el estado. Solo para tests.
  @visibleForTesting
  static void resetForTest() => _activated = false;
}
