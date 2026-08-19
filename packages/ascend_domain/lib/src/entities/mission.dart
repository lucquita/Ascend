import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/goal.dart';
import 'package:ascend_domain/src/enums/enums.dart';
import 'package:meta/meta.dart';

/// Estado de la subida de una evidencia.
enum EvidenceUploadStatus {
  /// Esperando en la cola local.
  pending('pending'),

  /// Subiendo.
  uploading('uploading'),

  /// Subida y confirmada.
  uploaded('uploaded'),

  /// Falló tras agotar los reintentos.
  failed('failed');

  const EvidenceUploadStatus(this.wireValue);

  /// Valor persistido.
  final String wireValue;

  /// Convierte desde el valor persistido.
  static EvidenceUploadStatus fromWire(String? value) => switch (value) {
    'uploading' => EvidenceUploadStatus.uploading,
    'uploaded' => EvidenceUploadStatus.uploaded,
    'failed' => EvidenceUploadStatus.failed,
    _ => EvidenceUploadStatus.pending,
  };

  /// `true` si todavía no llegó al servidor.
  bool get isPending =>
      this == EvidenceUploadStatus.pending ||
      this == EvidenceUploadStatus.uploading;
}

/// Prueba de que una misión se cumplió: foto, descripción y fecha.
///
/// Va embebida en la misión porque la relación es 1:1 y siempre se leen juntas.
/// Si en el futuro se admiten varias, pasa a subcolección sin cambiar el
/// contrato del repositorio.
@immutable
class Evidence {
  /// Crea una evidencia.
  const Evidence({
    required this.capturedAt,
    this.photoUrl,
    this.thumbUrl,
    this.localPath,
    this.note,
    this.uploadStatus = EvidenceUploadStatus.pending,
    this.reviewStatus = EvidenceReviewStatus.pending,
    this.sizeBytes,
  });

  /// Cuándo se capturó (hora del dispositivo).
  final DateTime capturedAt;

  /// URL remota de la foto, una vez subida.
  final String? photoUrl;

  /// URL de la miniatura generada por el servidor.
  final String? thumbUrl;

  /// Ruta local del archivo mientras está en la cola de subida.
  ///
  /// Es lo que permite completar una misión sin conexión: la misión se marca
  /// completada de inmediato y la foto viaja después.
  final String? localPath;

  /// Descripción escrita por la persona.
  final String? note;

  /// Estado de la subida del archivo.
  final EvidenceUploadStatus uploadStatus;

  /// Estado de la revisión del contenido. 🔒 Lo escribe el servidor.
  final EvidenceReviewStatus reviewStatus;

  /// Peso del archivo original, en bytes. `null` si todavía no se midió.
  final int? sizeBytes;

  /// `true` si hay algo que mostrar (remoto o local).
  bool get hasImage => photoUrl != null || localPath != null;

  /// `true` si la evidencia sirve para acreditar el logro.
  ///
  /// Una evidencia rechazada por moderación no acredita nada, aunque el archivo
  /// haya subido perfectamente.
  bool get isValidProof => hasImage && !reviewStatus.isRejected;

  /// Copia con cambios.
  Evidence copyWith({
    DateTime? capturedAt,
    String? photoUrl,
    String? thumbUrl,
    String? localPath,
    String? note,
    EvidenceUploadStatus? uploadStatus,
    EvidenceReviewStatus? reviewStatus,
    int? sizeBytes,
  }) => Evidence(
    capturedAt: capturedAt ?? this.capturedAt,
    photoUrl: photoUrl ?? this.photoUrl,
    thumbUrl: thumbUrl ?? this.thumbUrl,
    localPath: localPath ?? this.localPath,
    note: note ?? this.note,
    uploadStatus: uploadStatus ?? this.uploadStatus,
    reviewStatus: reviewStatus ?? this.reviewStatus,
    sizeBytes: sizeBytes ?? this.sizeBytes,
  );
}

/// Regla de repetición de una misión.
@immutable
class Recurrence {
  /// Crea una regla de repetición.
  const Recurrence({required this.type, this.weekdays = const <int>[]});

  /// `daily`, `weekly` o `custom`.
  final String type;

  /// Días de la semana (1 = lunes … 7 = domingo) para `weekly`.
  final List<int> weekdays;

  /// `true` si se repite todos los días.
  bool get isDaily => type == 'daily';
}

/// Misión: la unidad mínima de acción de Ascend.
///
/// Vive en una colección plana bajo el usuario (`users/{uid}/missions`) y no
/// anidada bajo el objetivo. Ver ADR-005: la pantalla "Hoy" necesita todas las
/// misiones del día de todos los objetivos en una sola consulta.
@immutable
class Mission {
  /// Crea una misión.
  const Mission({
    required this.id,
    required this.ownerId,
    required this.goalId,
    required this.title,
    required this.createdAt,
    this.goalTitle,
    this.categoryId,
    this.description,
    this.status = MissionStatus.pending,
    this.difficulty = MissionDifficulty.medium,
    this.budget = MissionBudget.free,
    this.auraReward = 0,
    this.estimatedMinutes,
    this.dueDate,
    this.scheduledFor,
    this.recurrence,
    this.order = 0,
    this.requiresEvidence = false,
    this.evidence,
    this.ai = AiMetadata.manual,
    this.completedAt,
    this.updatedAt,
  });

  /// Identificador, generado en el cliente.
  final String id;

  /// Dueño.
  final String ownerId;

  /// Objetivo al que pertenece.
  final String goalId;

  /// Título de la acción concreta.
  final String title;

  /// Fecha de creación.
  final DateTime createdAt;

  /// Título del objetivo, desnormalizado para poder pintar la lista "Hoy" sin
  /// una lectura extra por misión.
  final String? goalTitle;

  /// Categoría heredada del objetivo.
  final String? categoryId;

  /// Detalle de qué hay que hacer.
  final String? description;

  /// Estado.
  final MissionStatus status;

  /// Dificultad. Determina la recompensa.
  final MissionDifficulty difficulty;

  /// Costo económico estimado.
  ///
  /// Sirve para filtrar; **no** entra en el cálculo de Aura. Si pagar más diera
  /// más progreso, la gamificación se volvería un ranking de poder adquisitivo.
  final MissionBudget budget;

  /// Aura que otorga. **La fija el servidor**, el cliente solo la muestra.
  final int auraReward;

  /// Duración estimada en minutos.
  final int? estimatedMinutes;

  /// Fecha límite.
  final DateTime? dueDate;

  /// Día para el que está agendada (`YYYY-MM-DD`).
  final String? scheduledFor;

  /// Regla de repetición, si es recurrente.
  final Recurrence? recurrence;

  /// Posición dentro de su lista.
  final int order;

  /// Si exige adjuntar evidencia para completarse.
  final bool requiresEvidence;

  /// Evidencia adjunta.
  final Evidence? evidence;

  /// Metadatos de generación por IA.
  final AiMetadata ai;

  /// Cuándo se completó.
  final DateTime? completedAt;

  /// Última modificación.
  final DateTime? updatedAt;

  /// `true` si está pendiente y su fecha límite ya pasó.
  bool isOverdue({DateTime? now}) {
    final due = dueDate;
    if (due == null || !status.isOpen) {
      return false;
    }
    return AscendDateUtils.isOverdue(due, now: now);
  }

  /// `true` si vence hoy.
  bool isDueToday({DateTime? now}) {
    final due = dueDate;
    if (due == null) {
      return false;
    }
    return AscendDateUtils.isToday(due, now: now);
  }

  /// `true` si se puede marcar como completada ahora mismo.
  ///
  /// Es la regla de negocio que impide completar dos veces la misma misión —el
  /// exploit más obvio del sistema de Aura— y la que exige evidencia cuando
  /// corresponde. Vive acá, en el dominio, no en el widget del botón.
  bool get canComplete {
    if (!status.isOpen) {
      return false;
    }
    if (requiresEvidence && !(evidence?.hasImage ?? false)) {
      return false;
    }
    return true;
  }

  /// `true` si tiene evidencia esperando subir.
  bool get hasPendingUpload => evidence?.uploadStatus.isPending ?? false;

  /// Copia con cambios.
  Mission copyWith({
    String? goalId,
    String? goalTitle,
    String? categoryId,
    String? title,
    String? description,
    MissionStatus? status,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    int? auraReward,
    int? estimatedMinutes,
    DateTime? dueDate,
    String? scheduledFor,
    Recurrence? recurrence,
    int? order,
    bool? requiresEvidence,
    Evidence? evidence,
    AiMetadata? ai,
    DateTime? completedAt,
    DateTime? updatedAt,
  }) => Mission(
    id: id,
    ownerId: ownerId,
    goalId: goalId ?? this.goalId,
    title: title ?? this.title,
    createdAt: createdAt,
    goalTitle: goalTitle ?? this.goalTitle,
    categoryId: categoryId ?? this.categoryId,
    description: description ?? this.description,
    status: status ?? this.status,
    difficulty: difficulty ?? this.difficulty,
    budget: budget ?? this.budget,
    auraReward: auraReward ?? this.auraReward,
    estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
    dueDate: dueDate ?? this.dueDate,
    scheduledFor: scheduledFor ?? this.scheduledFor,
    recurrence: recurrence ?? this.recurrence,
    order: order ?? this.order,
    requiresEvidence: requiresEvidence ?? this.requiresEvidence,
    evidence: evidence ?? this.evidence,
    ai: ai ?? this.ai,
    completedAt: completedAt ?? this.completedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Mission && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Mission($id, $title, ${status.wireValue})';
}
