import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Traducción entre `users/{uid}/missions/{missionId}` y [Mission].
///
/// ## El campo que nunca viaja: `auraReward`
///
/// ```
/// allow create: ... && absent('auraReward');
/// allow update: ... && unchanged('ownerId') && unchanged('auraReward');
/// ```
///
/// La recompensa la fija el servidor según `config/auraRules` (ADR-003). Si el
/// cliente pudiera proponerla, se otorgaría el Aura que quisiera y el ranking
/// sería ficción. Por eso [toCreate] no incluye esa clave —`absent()` mira la
/// presencia, así que `'auraReward': null` fallaría igual— y ninguna escritura
/// de este DTO la toca.
///
/// ## Las misiones son planas (ADR-005)
///
/// Viven en `users/{uid}/missions` con `goalId` indexado, no anidadas bajo el
/// objetivo. La pantalla "Hoy" necesita todas las misiones del día de todos los
/// objetivos en **una sola consulta**; con misiones anidadas eso exigiría un
/// `collectionGroup` o N consultas.
abstract final class MissionDto {
  /// Convierte un documento de Firestore en la entidad.
  static Mission fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => fromMap(snapshot.data() ?? const <String, dynamic>{}, id: snapshot.id);

  /// Convierte un mapa plano en la entidad.
  ///
  /// Nunca lanza: un documento incompleto cae a valores por defecto. Una misión
  /// rota no puede romper la lista entera del día.
  static Mission fromMap(Map<String, dynamic> data, {required String id}) {
    final evidence = _mapOf(data['evidence']);
    final recurrence = _mapOf(data['recurrence']);
    final ai = _mapOf(data['ai']);

    return Mission(
      id: id,
      ownerId: _stringOf(data['ownerId']),
      goalId: _stringOf(data['goalId']),
      title: _stringOf(data['title']),
      createdAt: _dateOf(data['createdAt']) ?? DateTime.now().toUtc(),
      goalTitle: _nullableStringOf(data['goalTitle']),
      categoryId: _nullableStringOf(data['categoryId']),
      description: _nullableStringOf(data['description']),
      status: MissionStatus.fromWire(_nullableStringOf(data['status'])),
      difficulty: MissionDifficulty.fromWire(
        _nullableStringOf(data['difficulty']),
      ),
      budget: MissionBudget.fromWire(_nullableStringOf(data['budget'])),
      auraReward: _intOf(data['auraReward']),
      estimatedMinutes: _nullableIntOf(data['estimatedMinutes']),
      dueDate: _dateOf(data['dueDate']),
      scheduledFor: _nullableStringOf(data['scheduledFor']),
      recurrence: recurrence.isEmpty
          ? null
          : Recurrence(
              type: _stringOf(recurrence['type'], fallback: 'daily'),
              weekdays: _intListOf(recurrence['days']),
            ),
      order: _intOf(data['order']),
      requiresEvidence: data['requiresEvidence'] == true,
      evidence: evidence.isEmpty
          ? null
          : Evidence(
              capturedAt:
                  _dateOf(evidence['capturedAt']) ?? DateTime.now().toUtc(),
              photoUrl: _nullableStringOf(evidence['photoUrl']),
              thumbUrl: _nullableStringOf(evidence['thumbUrl']),
              localPath: _nullableStringOf(evidence['localPath']),
              note: _nullableStringOf(evidence['note']),
              uploadStatus: EvidenceUploadStatus.fromWire(
                _nullableStringOf(evidence['uploadStatus']),
              ),
              reviewStatus: EvidenceReviewStatus.fromWire(
                _nullableStringOf(evidence['reviewStatus']),
              ),
              sizeBytes: _nullableIntOf(evidence['sizeBytes']),
            ),
      ai: AiMetadata(
        generated: ai['generated'] == true,
        model: _nullableStringOf(ai['model']),
        promptVersion: _nullableStringOf(ai['promptVersion']),
        jobId: _nullableStringOf(ai['jobId']),
        generatedAt: _dateOf(ai['generatedAt']),
      ),
      completedAt: _dateOf(data['completedAt']),
      updatedAt: _dateOf(data['updatedAt']),
    );
  }

  /// Documento de alta. **No incluye `auraReward`.**
  static Map<String, Object?> toCreate(Mission mission) => <String, Object?>{
    'ownerId': mission.ownerId,
    'goalId': mission.goalId,
    // El título del objetivo va desnormalizado: la lista "Hoy" lo necesita para
    // dar contexto y sin esto costaría una lectura extra por misión.
    'goalTitle': mission.goalTitle,
    'categoryId': mission.categoryId,
    'title': mission.title,
    'description': mission.description,
    'status': mission.status.wireValue,
    'difficulty': mission.difficulty.wireValue,
    'budget': mission.budget.wireValue,
    'estimatedMinutes': mission.estimatedMinutes,
    'dueDate': _timestampOf(mission.dueDate),
    'scheduledFor': mission.scheduledFor,
    'recurrence': _recurrenceToMap(mission.recurrence),
    'order': mission.order,
    'requiresEvidence': mission.requiresEvidence,
    'evidence': _evidenceToMap(mission.evidence),
    'ai': _aiToMap(mission.ai),
    'completedAt': null,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'deletedAt': null,
  };

  /// Campos editables de una misión existente.
  ///
  /// **No incluye `ownerId` ni `auraReward`.** Tampoco `status`: cambiar de
  /// estado tiene su propio método porque dispara el trigger de Aura y conviene
  /// que la escritura sea mínima y explícita.
  static Map<String, Object?> toUpdate(Mission mission) => <String, Object?>{
    'goalId': mission.goalId,
    'goalTitle': mission.goalTitle,
    'categoryId': mission.categoryId,
    'title': mission.title,
    'description': mission.description,
    'difficulty': mission.difficulty.wireValue,
    'budget': mission.budget.wireValue,
    'estimatedMinutes': mission.estimatedMinutes,
    'dueDate': _timestampOf(mission.dueDate),
    'scheduledFor': mission.scheduledFor,
    'recurrence': _recurrenceToMap(mission.recurrence),
    'requiresEvidence': mission.requiresEvidence,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Marca la misión como completada.
  ///
  /// El cliente **solo** cambia el estado y adjunta la evidencia; el Aura la
  /// otorga un trigger del servidor al ver la transición (ADR-003).
  static Map<String, Object?> completionUpdate({Evidence? evidence}) =>
      <String, Object?>{
        'status': MissionStatus.completed.wireValue,
        'completedAt': FieldValue.serverTimestamp(),
        if (evidence != null) 'evidence': _evidenceToMap(evidence),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Cambio de estado que no es "completada".
  static Map<String, Object?> statusUpdate(MissionStatus status) =>
      <String, Object?>{
        'status': status.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Reordenamiento: solo la posición.
  static Map<String, Object?> orderUpdate(int order) => <String, Object?>{
    'order': order,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Adjunta o reemplaza la evidencia sin tocar el estado.
  static Map<String, Object?> evidenceUpdate(Evidence evidence) =>
      <String, Object?>{
        'evidence': _evidenceToMap(evidence),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Map<String, Object?>? _evidenceToMap(Evidence? evidence) {
    if (evidence == null) {
      return null;
    }
    return <String, Object?>{
      'photoUrl': evidence.photoUrl,
      'thumbUrl': evidence.thumbUrl,
      'localPath': evidence.localPath,
      'note': evidence.note,
      'capturedAt': _timestampOf(evidence.capturedAt),
      'uploadStatus': evidence.uploadStatus.wireValue,
      'sizeBytes': evidence.sizeBytes,
      // `reviewStatus` NO viaja: lo escribe la moderación del servidor. Si el
      // cliente pudiera marcarse una evidencia como aprobada, la moderación
      // dejaría de existir. Las reglas lo rechazan además de esta omisión.
    };
  }

  static Map<String, Object?>? _recurrenceToMap(Recurrence? recurrence) {
    if (recurrence == null) {
      return null;
    }
    return <String, Object?>{
      'type': recurrence.type,
      'days': recurrence.weekdays,
    };
  }

  static Map<String, Object?> _aiToMap(AiMetadata ai) => <String, Object?>{
    'generated': ai.generated,
    'model': ai.model,
    'promptVersion': ai.promptVersion,
    'jobId': ai.jobId,
    'generatedAt': _timestampOf(ai.generatedAt),
  };

  static Map<String, dynamic> _mapOf(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  static String _stringOf(Object? value, {String fallback = ''}) =>
      value is String && value.isNotEmpty ? value : fallback;

  static String? _nullableStringOf(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static int _intOf(Object? value, {int fallback = 0}) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => fallback,
  };

  static int? _nullableIntOf(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => null,
  };

  static List<int> _intListOf(Object? value) => value is List
      ? value.whereType<num>().map((n) => n.toInt()).toList(growable: false)
      : const <int>[];

  static Timestamp? _timestampOf(DateTime? value) =>
      value == null ? null : Timestamp.fromDate(value);

  // Todo lo que entra al dominio va en UTC: las rachas se calculan con fechas y
  // `Timestamp.toDate()` devuelve hora local.
  static DateTime? _dateOf(Object? value) => switch (value) {
    final Timestamp v => v.toDate().toUtc(),
    final DateTime v => v.toUtc(),
    _ => null,
  };
}
