import 'package:ascend_data/ascend_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Estos tests existen por el BUG-001.
///
/// El paquete `firebase_app_check` estaba declarado en `pubspec.yaml` y nunca
/// se llamaba a `activate()`. Como las cuatro llamables se despliegan con
/// `enforceAppCheck: true`, eso rompía el registro de cuentas contra Firebase
/// real — y ningún test lo detectaba, porque ninguno miraba la activación.
///
/// No se puede verificar acá que la atestación *funcione* (eso exige un
/// dispositivo y un proyecto de Firebase). Sí se puede blindar el contrato que
/// se violó: que la activación exista, que nunca tumbe el arranque, y que su
/// estado sea consultable en vez de silencioso.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AppCheckService.resetForTest);

  group('AppCheckService — contrato de resiliencia', () {
    test('sin Firebase inicializado NO lanza: devuelve false', () async {
      // Es el principio 3 de la arquitectura aplicado al arranque: un problema
      // de atestación no puede impedir que la app abra. Si esto lanzara,
      // `FirebaseConfig.initialize` se iría por el `catch` y la app quedaría en
      // "modo sin backend" por una causa equivocada.
      await expectLater(AppCheckService.activate(), completion(isFalse));
    });

    test('una activación fallida deja isActive en false', () async {
      await AppCheckService.activate();

      // Importa que sea consultable: si App Check no quedó activo, toda
      // llamable va a rechazar, y la app tiene que poder explicar por qué en
      // lugar de mostrar un `unauthenticated` sin contexto.
      expect(AppCheckService.isActive, isFalse);
    });

    test('una clave de reCAPTCHA vacía no rompe la activación', () async {
      // En móvil `RECAPTCHA_SITE_KEY` no se define, así que `String.fromEnvironment`
      // devuelve ''. Ese caso tiene que tratarse como "sin proveedor web", no
      // como una clave válida y vacía.
      await expectLater(
        AppCheckService.activate(webRecaptchaSiteKey: ''),
        completion(isFalse),
      );
    });
  });
}
