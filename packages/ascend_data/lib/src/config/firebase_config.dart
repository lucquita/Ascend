import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/config/app_check_service.dart';
import 'package:ascend_data/src/config/regions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctions;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Inicialización de Firebase por entorno.
///
/// Vive en `ascend_data` y no en una app porque **las dos la necesitan igual**:
/// la app móvil y el panel web arrancan contra el mismo proyecto, con el mismo
/// App Check y el mismo modo degradado. Tenerla dos veces garantizaba que una
/// de las dos copias se quedara vieja.
///
/// El archivo `firebase_options.dart` lo genera FlutterFire CLI y **no está en
/// el repositorio todavía**: se crea al dar de alta los proyectos dev/stg/prod.
///
/// Hasta entonces las dos apps arrancan igual, en modo sin backend. Es
/// deliberado: permite verificar la navegación, los temas y los estados de
/// error sin depender de que exista un proyecto en la nube, y evita que un
/// desarrollador nuevo quede bloqueado el primer día. En web pesa todavía más,
/// porque ahí `initializeApp()` sin opciones explícitas siempre falla.
abstract final class FirebaseConfig {
  static const AscendLogger _logger = AscendLogger('FirebaseConfig');

  static bool _initialized = false;

  /// Clave de sitio de reCAPTCHA v3, necesaria solo en web.
  ///
  /// No es un secreto —viaja en el HTML de cualquier sitio que use reCAPTCHA—,
  /// pero se inyecta por `--dart-define` porque cambia entre proyectos.
  static const String _recaptchaSiteKey = String.fromEnvironment(
    'RECAPTCHA_SITE_KEY',
  );

  /// `true` si Firebase quedó operativo.
  ///
  /// Las funcionalidades que dependen del backend consultan esto para degradar
  /// con elegancia en vez de explotar.
  static bool get isAvailable => _initialized;

  /// Opciones de juguete para el emulador local.
  ///
  /// El prefijo `demo-` no es decorativo: el conjunto de emuladores reconoce
  /// los proyectos que empiezan así y **no exige credenciales reales ni una
  /// cuenta de Firebase**. Nada de esto es un secreto —son valores de relleno
  /// que solo sirven contra `localhost`— y por eso pueden vivir en el
  /// repositorio.
  static const FirebaseOptions _emulatorOptions = FirebaseOptions(
    apiKey: 'demo-ascend-key',
    appId: '1:0:web:0',
    messagingSenderId: '0',
    projectId: 'demo-ascend',
  );

  /// `true` si la app está hablando con el emulador y no con Firebase real.
  ///
  /// Lo consultan las pantallas para poder avisarlo: alguien que ve datos de
  /// prueba tiene que saber que son de prueba.
  static bool get isUsingEmulators => _initialized && AppFlavor.useEmulators;

  /// Inicializa Firebase para el flavor actual.
  ///
  /// Nunca lanza: si falla, lo registra y devuelve `false`. Un problema de
  /// configuración no puede impedir que la app abra y muestre un mensaje.
  static Future<bool> initialize() async {
    try {
      if (AppFlavor.useEmulators) {
        return _initializeForEmulators();
      }

      await Firebase.initializeApp();
      _initialized = true;

      // App Check va inmediatamente después de inicializar Firebase y antes de
      // que la app pueda invocar nada: las cuatro llamables se despliegan con
      // `enforceAppCheck: true` y sin token válido rechazan la petición antes
      // de ejecutarse. Omitir este paso rompe el registro de cuentas — fue
      // exactamente el BUG-001.
      //
      // Su fallo no aborta el arranque: se registra y la app abre igual.
      await AppCheckService.activate(webRecaptchaSiteKey: _recaptchaSiteKey);

      _logger.info(
        'Firebase inicializado',
        context: <String, Object?>{
          'flavor': AppFlavor.current.key,
          'appCheck': AppCheckService.isActive ? 'activo' : 'inactivo',
        },
      );
      return true;
    } on Object catch (error, stackTrace) {
      _initialized = false;
      _logger.warning(
        'Firebase no está configurado todavía: la app arranca sin backend. '
        'Generá firebase_options.dart con `flutterfire configure`.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Arranca contra el conjunto de emuladores local.
  ///
  /// ## Para qué sirve
  ///
  /// Permite usar la aplicación **entera** —registrarse, crear objetivos,
  /// completar misiones, publicar, moderar desde el panel— sin una cuenta de
  /// Firebase, sin desplegar nada y sin plan de pago. Es el camino corto para
  /// ver el producto funcionando y para desarrollar sin tocar datos reales.
  ///
  /// ## Por qué App Check queda afuera
  ///
  /// El emulador de funciones no valida el token de App Check, y activarlo sin
  /// una clave real solo produce ruido en los logs. Contra Firebase real sí se
  /// activa, que es donde importa.
  ///
  /// Los puertos coinciden con los de `backend/firebase.json`. Si se cambian
  /// allá, hay que cambiarlos acá: es la única duplicación y está anotada.
  static Future<bool> _initializeForEmulators() async {
    try {
      await Firebase.initializeApp(options: _emulatorOptions);

      // `127.0.0.1` y no `localhost`: en Windows `localhost` puede resolver
      // primero a IPv6 (::1) y el emulador escucha en IPv4, con lo que la
      // conexión falla con un timeout que no explica nada.
      //
      // Desde el emulador de Android hay que pasar `10.0.2.2`, que es la
      // dirección con la que ese teléfono virtual ve al equipo anfitrión.
      const host = String.fromEnvironment(
        'EMULATOR_HOST',
        defaultValue: '127.0.0.1',
      );

      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      FirebaseFunctions.instanceFor(
        region: kFunctionsRegion,
      ).useFunctionsEmulator(host, 5001);
      await FirebaseStorage.instance.useStorageEmulator(host, 9199);

      _initialized = true;
      _logger.info(
        'Firebase apuntando a los emuladores locales',
        context: <String, Object?>{'host': host, 'proyecto': 'demo-ascend'},
      );
      return true;
    } on Object catch (error, stackTrace) {
      _initialized = false;
      _logger.warning(
        'No se pudo conectar a los emuladores. ¿Están corriendo? '
        'Arrancalos con `firebase emulators:start` dentro de `backend/`.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
