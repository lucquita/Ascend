import 'package:ascend_domain/src/enums/enums.dart';
import 'package:meta/meta.dart';

/// Hito intermedio de un objetivo.
///
/// Va embebido en el objetivo y no en una subcolección: son pocos (3 a 8),
/// siempre se leen junto al objetivo y nunca se consultan por separado.
@immutable
class Milestone {
  /// Crea un hito.
  const Milestone({
    required this.id,
    required this.title,
    required this.order,
    this.done = false,
    this.completedAt,
  });

  /// Identificador dentro del objetivo.
  final String id;

  /// Título del hito.
  final String title;

  /// Posición en la lista.
  final int order;

  /// Si ya se alcanzó.
  final bool done;

  /// Cuándo se alcanzó.
  final DateTime? completedAt;

  /// Copia con cambios.
  Milestone copyWith({
    String? title,
    int? order,
    bool? done,
    DateTime? completedAt,
  }) => Milestone(
    id: id,
    title: title ?? this.title,
    order: order ?? this.order,
    done: done ?? this.done,
    completedAt: completedAt ?? this.completedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Milestone && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Avance de un objetivo. Lo calcula el servidor a partir de sus misiones.
@immutable
class GoalProgress {
  /// Crea el avance.
  const GoalProgress({this.missionsTotal = 0, this.missionsCompleted = 0});

  /// Avance de un objetivo sin misiones.
  static const GoalProgress empty = GoalProgress();

  /// Misiones totales.
  final int missionsTotal;

  /// Misiones completadas.
  final int missionsCompleted;

  /// Porcentaje de avance entre 0.0 y 1.0.
  double get fraction {
    if (missionsTotal <= 0) {
      return 0;
    }
    return (missionsCompleted / missionsTotal).clamp(0.0, 1.0);
  }

  /// Porcentaje de avance entre 0 y 100.
  double get percent => fraction * 100;

  /// `true` si todas las misiones están completadas.
  bool get isComplete =>
      missionsTotal > 0 && missionsCompleted >= missionsTotal;

  /// Misiones que faltan.
  int get remaining =>
      (missionsTotal - missionsCompleted).clamp(0, missionsTotal);
}

/// Metadatos de generación por IA.
@immutable
class AiMetadata {
  /// Crea los metadatos de una generación.
  const AiMetadata({
    required this.generated,
    this.model,
    this.promptVersion,
    this.jobId,
    this.generatedAt,
  });

  /// Metadatos de contenido creado a mano.
  static const AiMetadata manual = AiMetadata(generated: false);

  /// Si el contenido lo generó la IA.
  final bool generated;

  /// Modelo usado.
  final String? model;

  /// Versión del prompt, para poder correlacionar calidad con cambios.
  final String? promptVersion;

  /// Identificador del trabajo en `aiJobs`.
  final String? jobId;

  /// Cuándo se generó.
  final DateTime? generatedAt;
}

/// Objetivo personal.
@immutable
class Goal {
  /// Crea un objetivo.
  const Goal({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.categoryId,
    required this.createdAt,
    this.description,
    this.status = GoalStatus.active,
    this.difficulty = MissionDifficulty.medium,
    this.progress = GoalProgress.empty,
    this.auraEarned = 0,
    this.milestones = const <Milestone>[],
    this.ai = AiMetadata.manual,
    this.colorHex,
    this.icon,
    this.startDate,
    this.targetDate,
    this.completedAt,
    this.updatedAt,
  });

  /// Identificador. Se genera en el cliente para que la escritura sea idempotente.
  final String id;

  /// Dueño del objetivo.
  final String ownerId;

  /// Título.
  final String title;

  /// Categoría a la que pertenece.
  final String categoryId;

  /// Fecha de creación.
  final DateTime createdAt;

  /// Descripción opcional.
  final String? description;

  /// Estado.
  final GoalStatus status;

  /// Dificultad percibida.
  final MissionDifficulty difficulty;

  /// Avance calculado por el servidor.
  final GoalProgress progress;

  /// Aura acumulada por este objetivo.
  final int auraEarned;

  /// Hitos intermedios.
  final List<Milestone> milestones;

  /// Metadatos de generación por IA.
  final AiMetadata ai;

  /// Color de acento en formato `#RRGGBB`.
  final String? colorHex;

  /// Nombre del icono.
  final String? icon;

  /// Fecha de inicio.
  final DateTime? startDate;

  /// Fecha objetivo.
  final DateTime? targetDate;

  /// Fecha de finalización.
  final DateTime? completedAt;

  /// Última modificación.
  final DateTime? updatedAt;

  /// `true` si tiene fecha objetivo y ya pasó sin completarse.
  bool isOverdue({DateTime? now}) {
    final target = targetDate;
    if (target == null || status == GoalStatus.completed) {
      return false;
    }
    return (now ?? DateTime.now()).isAfter(target);
  }

  /// Días que faltan para la fecha objetivo. `null` si no tiene.
  int? daysRemaining({DateTime? now}) {
    final target = targetDate;
    if (target == null) {
      return null;
    }
    return target.difference(now ?? DateTime.now()).inDays;
  }

  /// Hitos ya alcanzados.
  List<Milestone> get completedMilestones =>
      milestones.where((m) => m.done).toList(growable: false);

  /// Copia con cambios.
  Goal copyWith({
    String? title,
    String? description,
    String? categoryId,
    GoalStatus? status,
    MissionDifficulty? difficulty,
    GoalProgress? progress,
    int? auraEarned,
    List<Milestone>? milestones,
    AiMetadata? ai,
    String? colorHex,
    String? icon,
    DateTime? startDate,
    DateTime? targetDate,
    DateTime? completedAt,
    DateTime? updatedAt,
  }) => Goal(
    id: id,
    ownerId: ownerId,
    title: title ?? this.title,
    categoryId: categoryId ?? this.categoryId,
    createdAt: createdAt,
    description: description ?? this.description,
    status: status ?? this.status,
    difficulty: difficulty ?? this.difficulty,
    progress: progress ?? this.progress,
    auraEarned: auraEarned ?? this.auraEarned,
    milestones: milestones ?? this.milestones,
    ai: ai ?? this.ai,
    colorHex: colorHex ?? this.colorHex,
    icon: icon ?? this.icon,
    startDate: startDate ?? this.startDate,
    targetDate: targetDate ?? this.targetDate,
    completedAt: completedAt ?? this.completedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Goal && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Goal($id, $title, ${status.wireValue})';
}
