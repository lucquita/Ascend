import 'package:ascend_domain/src/enums/enums.dart';
import 'package:meta/meta.dart';

/// Autor desnormalizado dentro de una publicación.
///
/// Se copia en cada post para que pintar el feed no cueste una lectura de
/// perfil por publicación (§9 de arquitectura: sin esto, 20 posts serían 21
/// lecturas). Un trigger propaga los cambios de perfil a los posts recientes.
///
/// 🔒 Lo escribe el servidor: las reglas rechazan `author` en la creación.
@immutable
class PostAuthor {
  /// Crea el autor desnormalizado.
  const PostAuthor({
    required this.displayName,
    required this.handle,
    this.photoUrl,
    this.level = 1,
  });

  /// Nombre visible.
  final String displayName;

  /// Nombre de usuario público.
  final String handle;

  /// Avatar.
  final String? photoUrl;

  /// Nivel de Aura alcanzado.
  final int level;

  /// Handle listo para mostrar.
  String get displayHandle => '@$handle';
}

/// Logro al que apunta una publicación.
///
/// **Solo lleva títulos, nunca datos privados.** Un post enlaza a un objetivo y
/// a una misión por su nombre; quien lo lee no accede al objetivo ajeno.
@immutable
class PostSource {
  /// Crea la referencia al logro.
  const PostSource({
    this.goalId,
    this.goalTitle,
    this.missionId,
    this.missionTitle,
    this.auraEarned = 0,
  });

  /// Objetivo asociado.
  final String? goalId;

  /// Título del objetivo.
  final String? goalTitle;

  /// Misión asociada.
  final String? missionId;

  /// Título de la misión.
  final String? missionTitle;

  /// Aura que otorgó el logro.
  final int auraEarned;

  /// `true` si apunta a algo concreto.
  bool get isEmpty => goalId == null && missionId == null;
}

/// Contadores de interacción. 🔒 Los mantiene el servidor por trigger.
@immutable
class PostCounters {
  /// Crea los contadores.
  const PostCounters({this.likes = 0, this.comments = 0, this.reports = 0});

  /// Sin interacciones.
  static const PostCounters empty = PostCounters();

  /// Cuántos "me gusta".
  final int likes;

  /// Cuántos comentarios.
  final int comments;

  /// Cuántos reportes recibió.
  final int reports;
}

/// Publicación del feed.
///
/// **Regla de producto codificada en el modelo:** un post de logro debe
/// referenciar algo real. Solo las reflexiones quedan exentas. Está verificado
/// en el dominio —`validatePost`— y en las reglas de Firestore, no solo en la
/// interfaz.
@immutable
class Post {
  /// Crea una publicación.
  const Post({
    required this.id,
    required this.authorId,
    required this.type,
    required this.text,
    required this.createdAt,
    this.author,
    this.source,
    this.categoryId,
    this.mediaUrl,
    this.thumbUrl,
    this.visibility = Visibility.public,
    this.counters = PostCounters.empty,
    this.moderation = ModerationStatus.visible,
    this.updatedAt,
  });

  /// Identificador, generado en el cliente.
  final String id;

  /// Quién publicó.
  final String authorId;

  /// Autor desnormalizado. `null` hasta que el trigger lo completa.
  final PostAuthor? author;

  /// Qué clase de publicación es.
  final PostType type;

  /// Texto escrito por la persona.
  final String text;

  /// Momento de publicación.
  final DateTime createdAt;

  /// Logro al que apunta.
  final PostSource? source;

  /// Categoría heredada del objetivo.
  final String? categoryId;

  /// Imagen adjunta.
  final String? mediaUrl;

  /// Miniatura generada por el servidor.
  final String? thumbUrl;

  /// Quién puede verlo.
  final Visibility visibility;

  /// Contadores. 🔒
  final PostCounters counters;

  /// Estado de moderación. 🔒
  final ModerationStatus moderation;

  /// Última edición.
  final DateTime? updatedAt;

  /// `true` si aparece en el feed público.
  bool get isVisible => moderation.isPublic;

  /// `true` si este contenido lo escribió [uid].
  bool isAuthoredBy(String uid) => authorId == uid;

  /// Copia con cambios. Solo el texto es editable tras publicar.
  Post copyWith({String? text, DateTime? updatedAt}) => Post(
    id: id,
    authorId: authorId,
    type: type,
    text: text ?? this.text,
    createdAt: createdAt,
    author: author,
    source: source,
    categoryId: categoryId,
    mediaUrl: mediaUrl,
    thumbUrl: thumbUrl,
    visibility: visibility,
    counters: counters,
    moderation: moderation,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Post && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Comentario de una publicación.
@immutable
class Comment {
  /// Crea un comentario.
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.text,
    required this.createdAt,
    this.author,
    this.parentId,
    this.likes = 0,
    this.moderation = ModerationStatus.visible,
  });

  /// Identificador.
  final String id;

  /// Publicación a la que pertenece.
  final String postId;

  /// Quién comentó.
  final String authorId;

  /// Autor desnormalizado. 🔒
  final PostAuthor? author;

  /// Texto.
  final String text;

  /// Momento.
  final DateTime createdAt;

  /// Comentario padre. Un solo nivel de respuestas.
  final String? parentId;

  /// Cuántos "me gusta". 🔒
  final int likes;

  /// Estado de moderación. 🔒
  final ModerationStatus moderation;

  /// `true` si es respuesta a otro comentario.
  bool get isReply => parentId != null;

  /// `true` si este comentario lo escribió [uid].
  bool isAuthoredBy(String uid) => authorId == uid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Comment && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Estado de un reporte de moderación.
enum ReportStatus {
  /// Sin revisar.
  open('open'),

  /// En revisión.
  reviewing('reviewing'),

  /// Resuelto con alguna acción.
  resolved('resolved'),

  /// Revisado y descartado.
  dismissed('dismissed');

  const ReportStatus(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static ReportStatus fromWire(String? value) => switch (value) {
    'reviewing' => ReportStatus.reviewing,
    'resolved' => ReportStatus.resolved,
    'dismissed' => ReportStatus.dismissed,
    _ => ReportStatus.open,
  };

  /// `true` si todavía espera decisión.
  bool get isPending =>
      this == ReportStatus.open || this == ReportStatus.reviewing;
}

/// Reporte de contenido.
///
/// Su id es determinístico —`{targetId}_{reporterId}`— para que la misma
/// persona no pueda inflar el contador reportando cien veces. Es la misma
/// técnica que los likes: la unicidad la da la clave, no una consulta.
@immutable
class Report {
  /// Crea un reporte.
  const Report({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.createdAt,
    this.targetOwnerId,
    this.details,
    this.status = ReportStatus.open,
  });

  /// Identificador determinístico.
  final String id;

  /// Quién reportó.
  final String reporterId;

  /// Qué clase de contenido (`post`, `comment`).
  final String targetType;

  /// Contenido reportado.
  final String targetId;

  /// Autor del contenido reportado.
  final String? targetOwnerId;

  /// Motivo.
  final ReportReason reason;

  /// Detalle escrito por quien reporta.
  final String? details;

  /// Estado de la revisión. 🔒 Lo cambia el admin.
  final ReportStatus status;

  /// Momento del reporte.
  final DateTime createdAt;

  /// Construye el id determinístico de un reporte.
  static String buildId({
    required String targetId,
    required String reporterId,
  }) => '${targetId}_$reporterId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Report && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
