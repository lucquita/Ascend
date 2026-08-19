/// Reglas de negocio de la comunidad.
///
/// La premisa del producto —**el feed solo muestra logros reales**— vive acá y
/// en las reglas de Firestore, no en la interfaz. Una validación de pantalla se
/// esquiva con `curl`; esto no.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/mission.dart';
import 'package:ascend_domain/src/entities/post.dart';
import 'package:ascend_domain/src/enums/enums.dart';

/// Longitud máxima del texto de una publicación. Coincide con las reglas.
const int kMaxPostLength = 500;

/// Longitud máxima de un comentario. Coincide con las reglas.
const int kMaxCommentLength = 300;

/// Longitud máxima del detalle de un reporte.
const int kMaxReportDetailsLength = 500;

/// Valida una publicación antes de escribirla.
///
/// Devuelve el texto normalizado. Es una función pura para poder recorrer la
/// tabla completa de casos sin levantar nada.
Result<String> validatePost({
  required PostType type,
  required String text,
  PostSource? source,
}) {
  final trimmed = text.trim();

  // Una reflexión sin texto no comunica nada; un logro sí puede publicarse sin
  // comentario, porque el logro mismo es el contenido.
  if (trimmed.isEmpty && type == PostType.reflection) {
    return const Failed<String>(
      ValidationFailure(
        messageKey: 'validation.post.textRequired',
        field: 'text',
      ),
    );
  }

  if (trimmed.length > kMaxPostLength) {
    return const Failed<String>(
      ValidationFailure(messageKey: 'validation.post.tooLong', field: 'text'),
    );
  }

  // La premisa del producto, como regla verificable: un logro tiene que
  // apuntar a algo real. Sin esto, "completé mi objetivo" sería una frase que
  // cualquiera escribe sin haber hecho nada.
  if (type.requiresSource && (source == null || source.isEmpty)) {
    return const Failed<String>(
      ValidationFailure(
        messageKey: 'validation.post.sourceRequired',
        field: 'source',
      ),
    );
  }

  return Success<String>(trimmed);
}

/// Valida un comentario.
Result<String> validateComment(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const Failed<String>(
      ValidationFailure(
        messageKey: 'validation.comment.required',
        field: 'text',
      ),
    );
  }
  if (trimmed.length > kMaxCommentLength) {
    return const Failed<String>(
      ValidationFailure(
        messageKey: 'validation.comment.tooLong',
        field: 'text',
      ),
    );
  }
  return Success<String>(trimmed);
}

/// Valida un reporte.
Result<String?> validateReport({
  required String reporterId,
  required String targetOwnerId,
  String? details,
}) {
  // Reportarse a uno mismo no tiene sentido y sería la forma más fácil de
  // inflar el contador para auto-ocultarse contenido ajeno por confusión.
  if (reporterId == targetOwnerId) {
    return const Failed<String?>(
      ValidationFailure(
        messageKey: 'validation.report.ownContent',
        field: 'targetId',
      ),
    );
  }

  final trimmed = details?.trim();
  if (trimmed != null && trimmed.length > kMaxReportDetailsLength) {
    return const Failed<String?>(
      ValidationFailure(
        messageKey: 'validation.report.tooLong',
        field: 'details',
      ),
    );
  }

  return Success<String?>(trimmed == null || trimmed.isEmpty ? null : trimmed);
}

/// Arma la referencia al logro de una misión completada.
///
/// **Solo copia títulos.** El post no lleva ni el id del dueño ni nada del
/// objetivo más allá de su nombre: lo privado no se vuelve público por
/// accidente.
PostSource sourceFromMission(Mission mission) => PostSource(
  goalId: mission.goalId,
  goalTitle: mission.goalTitle,
  missionId: mission.id,
  missionTitle: mission.title,
  auraEarned: mission.auraReward,
);

/// Decide si una misión se puede publicar como logro.
///
/// Publicar algo que no se completó sería exactamente el "logro falso" que el
/// sistema de reportes existe para perseguir. Conviene impedirlo antes.
Result<void> canPublishMission(Mission mission) {
  if (!mission.status.isCompleted) {
    return const Failed<void>(
      ValidationFailure(
        messageKey: 'validation.post.missionNotCompleted',
        field: 'source',
      ),
    );
  }
  return const Success<void>(null);
}

/// Decide si un contenido es visible para quien lo mira.
///
/// El autor ve siempre lo suyo, incluso oculto por moderación: esconderle su
/// propio contenido sin explicación lo dejaría creyendo que se perdió. Un
/// administrador ve todo, porque para eso modera.
bool isPostVisibleFor(
  Post post, {
  required String viewerId,
  bool isAdmin = false,
}) => post.isVisible || post.isAuthoredBy(viewerId) || isAdmin;

/// Cuántos reportes hacen falta para ocultar un contenido de forma preventiva.
///
/// Tres personas distintas —el id determinístico impide que sea una sola tres
/// veces— alcanzan para sacarlo del feed mientras se revisa. Ocultar primero y
/// revisar después es lo correcto: el daño de dejar visible algo abusivo unas
/// horas es mayor que el de ocultar algo legítimo por error.
const int kReportsToAutoHide = 3;

/// `true` si el contenido debe ocultarse preventivamente.
bool shouldAutoHide(int reportCount) => reportCount >= kReportsToAutoHide;
