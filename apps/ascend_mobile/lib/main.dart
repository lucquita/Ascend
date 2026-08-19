import 'package:ascend_mobile/app.dart';
import 'package:ascend_mobile/bootstrap.dart';

/// Punto de entrada de la app móvil.
///
/// Toda la inicialización vive en [bootstrap], que además instala la red de
/// captura de errores. `main` solo dice qué widget construir: así el arranque
/// se puede testear sin arrancar la app entera.
void main() => bootstrap(AscendApp.new);
