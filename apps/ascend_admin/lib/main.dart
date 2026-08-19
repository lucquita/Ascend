import 'package:ascend_admin/app.dart';
import 'package:ascend_admin/bootstrap.dart';

/// Punto de entrada del panel de administración.
///
/// Toda la inicialización vive en [bootstrap], igual que en la app móvil: así
/// el arranque se puede probar sin levantar el panel entero.
void main() => bootstrap(AscendAdminApp.new);
