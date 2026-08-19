import 'package:ascend_core/ascend_core.dart';
import 'package:flutter/widgets.dart';

/// Traduce un [Failure] al texto que verá la persona.
typedef FailureMessageResolver =
    String Function(BuildContext context, Failure failure);

/// Describe un fallo en pantalla: título, mensaje y etiqueta del botón.
@immutable
class FailureDisplay {
  /// Crea la descripción visual de un fallo.
  const FailureDisplay({
    required this.title,
    required this.message,
    this.actionLabel,
  });

  /// Título corto (por ejemplo "Sin conexión").
  final String title;

  /// Explicación en lenguaje llano y, si se puede, con la salida.
  final String message;

  /// Etiqueta del botón de acción, si corresponde.
  final String? actionLabel;
}

/// Instala en el árbol la función que convierte fallos en texto localizado.
///
/// El design system no depende del paquete de traducciones: la app le inyecta
/// el traductor. Así `ascend_ui` sigue siendo reutilizable y los tests pueden
/// pasar textos fijos sin montar toda la infraestructura de i18n.
///
/// Si nadie lo instala, se usa [defaultResolver], que devuelve mensajes en
/// español. Es a propósito: preferimos un texto en duro antes que mostrar una
/// clave técnica como `failure.network` a un usuario real.
class AscendFailureMessages extends InheritedWidget {
  /// Instala el traductor de fallos para todo el subárbol.
  const AscendFailureMessages({
    required this.resolve,
    required super.child,
    super.key,
  });

  /// Función que traduce un fallo.
  final FailureMessageResolver resolve;

  /// Obtiene el traductor más cercano, o el de reserva si no hay ninguno.
  static FailureMessageResolver of(BuildContext context) {
    final widget = context
        .dependOnInheritedWidgetOfExactType<AscendFailureMessages>();
    return widget?.resolve ?? defaultResolver;
  }

  /// Traductor de reserva. Cubre todos los casos del `sealed Failure`.
  ///
  /// Al ser exhaustivo, agregar un nuevo tipo de fallo rompe la compilación
  /// acá y obliga a escribir su mensaje: es imposible olvidarse.
  static String defaultResolver(BuildContext context, Failure failure) =>
      describe(failure).message;

  /// Descompone un fallo en título, mensaje y acción sugerida.
  static FailureDisplay describe(Failure failure) => switch (failure) {
    NetworkFailure() => const FailureDisplay(
      title: 'Sin conexión',
      message:
          'No pudimos conectarnos. Revisá tu internet: tus cambios se guardan '
          'y se sincronizan solos cuando vuelvas.',
      actionLabel: 'Reintentar',
    ),
    TimeoutFailure() => const FailureDisplay(
      title: 'Tardó demasiado',
      message: 'La conexión está lenta. Probá de nuevo en un momento.',
      actionLabel: 'Reintentar',
    ),
    ServerFailure() => const FailureDisplay(
      title: 'Algo falló de nuestro lado',
      message:
          'Ya estamos al tanto y lo estamos resolviendo. Probá de nuevo en '
          'unos minutos.',
      actionLabel: 'Reintentar',
    ),
    AuthFailure(:final messageKey) => FailureDisplay(
      title: 'No pudimos verificar tu cuenta',
      message:
          _authMessages[messageKey] ?? 'Revisá tus datos e intentá otra vez.',
      actionLabel: 'Reintentar',
    ),
    PermissionFailure() => const FailureDisplay(
      title: 'No tenés acceso',
      message: 'Esta acción no está disponible para tu cuenta.',
    ),
    // Un "revisá los datos" genérico obliga a adivinar qué campo está mal.
    // Cada validación trae su clave y su mensaje concreto.
    ValidationFailure(:final messageKey) => FailureDisplay(
      title: 'Revisá los datos',
      message:
          _validationMessages[messageKey] ??
          'Hay algo que corregir antes de continuar.',
    ),
    NotFoundFailure() => const FailureDisplay(
      title: 'No lo encontramos',
      message: 'Puede que se haya eliminado.',
    ),
    // `QuotaFailure` cubre dos situaciones distintas: la cuota diaria de IA y
    // el almacenamiento no habilitado. Decirle a alguien "volvé mañana" cuando
    // el problema es que Storage no existe sería mentirle.
    QuotaFailure(messageKey: 'failure.storage.unavailable') =>
      const FailureDisplay(
        title: 'Las fotos todavía no se suben',
        message:
            'El almacenamiento de imágenes no está habilitado. Tu foto queda '
            'guardada en el teléfono y se sube sola cuando lo activemos.',
      ),
    QuotaFailure() => const FailureDisplay(
      title: 'Llegaste al límite por hoy',
      message:
          'Mañana volvés a tener generaciones disponibles. Mientras tanto '
          'podés crear tu plan a mano.',
    ),
    QueuedOfflineFailure() => const FailureDisplay(
      title: 'Guardado sin conexión',
      message: 'Lo subimos automáticamente cuando vuelva el internet.',
    ),
    UnsupportedVersionFailure() => const FailureDisplay(
      title: 'Actualizá Ascend',
      message: 'Esta versión ya no está soportada.',
      actionLabel: 'Actualizar',
    ),
    UnknownFailure() => const FailureDisplay(
      title: 'Algo salió mal',
      message: 'No pudimos completar la acción. Probá de nuevo.',
      actionLabel: 'Reintentar',
    ),
  };

  static const Map<String, String> _authMessages = <String, String>{
    'failure.auth.invalidCredentials': 'El email o la contraseña no coinciden.',
    'failure.auth.emailInUse': 'Ese email ya tiene una cuenta en Ascend.',
    'failure.auth.weakPassword':
        'Elegí una contraseña más segura: 8 caracteres con letras y números.',
    'failure.auth.sessionExpired': 'Tu sesión caducó. Volvé a entrar.',
    'failure.auth.accountDisabled':
        'Tu cuenta está suspendida. Escribinos si creés que es un error.',
    'failure.auth.cancelled': 'Cancelaste el inicio de sesión.',
    'failure.auth.tooManyRequests':
        'Demasiados intentos seguidos. Esperá unos minutos.',
    'failure.auth.socialUnavailable':
        'Entrar con Google o Apple todavía no está disponible. Usá tu email.',
  };

  static const Map<String, String> _validationMessages = <String, String>{
    'validation.email.required': 'Escribí tu email.',
    'validation.email.invalid': 'Ese email no parece válido.',
    'validation.password.required': 'Escribí una contraseña.',
    'validation.password.tooShort': 'Usá al menos 8 caracteres.',
    'validation.password.tooWeak': 'Combiná letras y números.',
    'validation.password.mismatch': 'Las contraseñas no coinciden.',
    'validation.password.sameAsCurrent':
        'La contraseña nueva tiene que ser distinta de la actual.',
    'validation.handle.required': 'Elegí un nombre de usuario.',
    'validation.handle.invalid':
        'Usá entre 3 y 20 caracteres: letras, números y guion bajo.',
    'validation.displayName.required': 'Escribí tu nombre.',
    'validation.displayName.tooLong': 'Ese nombre es demasiado largo.',
    'validation.bio.tooLong': 'La biografía no puede pasar de 160 caracteres.',
    'validation.terms.required':
        'Necesitamos que aceptes los términos para crear la cuenta.',
    'validation.interests.required': 'Elegí al menos un tema que te interese.',
    'validation.deleteAccount.notConfirmed':
        'Confirmá que querés eliminar la cuenta.',
    'validation.request.invalid':
        'Los datos enviados no son válidos. Revisalos e intentá otra vez.',
    // ── Objetivos ──
    'validation.title.required': 'Poné un título a tu objetivo.',
    'validation.title.tooLong':
        'El título no puede pasar de 80 caracteres. Contá el detalle en la '
        'descripción.',
    'validation.category.required': 'Elegí una categoría.',
    'validation.description.tooLong':
        'La descripción no puede pasar de 500 caracteres.',
    'validation.milestones.tooMany':
        'Un objetivo admite hasta 8 hitos. Si necesitás más, probablemente '
        'sean dos objetivos distintos.',
    'validation.targetDate.beforeStart':
        'La fecha objetivo tiene que ser posterior a la de inicio.',
    'validation.goal.notEditable':
        'Un objetivo completado o archivado no se puede editar. Reactivalo '
        'primero.',
    'validation.goal.invalidTransition':
        'Ese cambio de estado no es posible desde el estado actual.',
    // ── Misiones ──
    'validation.mission.goalNotEditable':
        'No se pueden agregar misiones a un objetivo completado o archivado. '
        'Reactivalo primero.',
    'validation.mission.completedNotEditable':
        'Una misión completada ya no se edita: su logro está registrado.',
    'validation.mission.alreadyCompleted': 'Esta misión ya estaba completada.',
    'validation.mission.evidenceRequired':
        'Esta misión pide una foto como evidencia antes de completarse.',
    'validation.mission.notOpen':
        'Solo se pueden saltear misiones pendientes o empezadas.',
    'validation.mission.invalidDuration':
        'La duración tiene que estar entre 1 minuto y 8 horas. Si lleva más, '
        'probablemente sea un objetivo y no una misión.',
    'validation.mission.duplicateOrder':
        'El nuevo orden tiene misiones repetidas.',
    // ── Evidencias ──
    'validation.evidence.fileRequired': 'Elegí o sacá una foto.',
    'validation.evidence.notAnImage':
        'El archivo tiene que ser una imagen (JPG, PNG, HEIC o WEBP).',
    'validation.evidence.tooLarge':
        'La imagen supera los 10 MB. Probá con una foto más liviana.',
    'validation.evidence.emptyFile': 'El archivo está vacío o dañado.',
    'validation.evidence.noteTooLong':
        'La nota no puede pasar de 280 caracteres.',
    'validation.evidence.completedMission':
        'No se puede quitar la evidencia de una misión ya completada: es lo '
        'que respalda el logro.',
    // ── Comunidad ──
    'validation.post.textRequired': 'Escribí algo para compartir.',
    'validation.post.tooLong':
        'La publicación no puede pasar de 500 caracteres.',
    'validation.post.sourceRequired':
        'Un logro tiene que apuntar a una misión u objetivo real. Elegí uno, o '
        'publicalo como reflexión.',
    'validation.post.missionNotCompleted':
        'Solo se pueden publicar misiones que ya completaste.',
    'validation.comment.required': 'Escribí tu comentario.',
    'validation.comment.tooLong':
        'El comentario no puede pasar de 300 caracteres.',
    'validation.report.ownContent': 'No podés reportar tu propio contenido.',
    'validation.report.tooLong': 'El detalle no puede pasar de 500 caracteres.',
    // ── Integraciones ──
    'validation.search.tooShort': 'Escribí al menos tres letras para buscar.',
    // ── Administración ──
    'validation.admin.selfRoleChange':
        'No podés cambiar tu propio rol. Pedíselo a otro administrador.',
    'validation.admin.selfStatusChange': 'No podés suspender tu propia cuenta.',
    'validation.admin.reasonRequired':
        'Escribí el motivo: queda en el registro de auditoría y es lo único '
        'que después explica la decisión.',
    'validation.admin.reportRequired': 'Elegí un reporte para resolver.',
  };

  @override
  bool updateShouldNotify(AscendFailureMessages oldWidget) =>
      resolve != oldWidget.resolve;
}
