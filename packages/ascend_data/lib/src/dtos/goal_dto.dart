import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Traducción entre `users/{uid}/goals/{goalId}` y [Goal].
///
/// ## Escrituras parciales, no `toJson()` completo
///
/// Las reglas de `goals` prohíben que el cliente toque tres campos:
///
/// ```
/// allow create: ... && absent('progress') && absent('auraEarned');
/// allow update: ... && unchanged('ownerId')
///                   && unchanged('progress') && unchanged('auraEarned');
/// ```
///
/// `absent()` comprueba la **presencia de la clave**, no su valor: mandar
/// `'progress': null` en el alta hace fallar la escritura entera igual que
/// mandar un progreso inventado. Por eso [toCreate] no incluye esas claves, y
/// [toUpdate] tampoco incluye `ownerId`.
///
/// Es la misma lección que dejó `lastLoginAt` en la Fase 1: un serializador
/// automático mandaría el objeto completo y Firestore rechazaría cada guardado.
/// Escribirlo a mano hace explícito qué viaja en cada operación, que es
/// justamente lo que hay que poder auditar cuando una regla rechaza algo.
abstract final class GoalDto {
  /// Convierte un documento de Firestore en la entidad de dominio.
  ///
  /// Nunca lanza: un documento incompleto o con campos del tipo equivocado cae
  /// a valores por defecto. Un objetivo a medio escribir tiene que poder
  /// abrirse para arreglarlo, no romper la lista entera.
  static Goal fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) =>
      fromMap(snapshot.data() ?? const <String, dynamic>{}, id: snapshot.id);

  /// Convierte un mapa plano en la entidad.
  ///
  /// Separado de [fromFirestore] para poder testear el mapeo sin instanciar
  /// Firestore.
  static Goal fromMap(Map<String, dynamic> data, {required String id}) {
    final progress = _mapOf(data['progress']);
    final ai = _mapOf(data['ai']);

    return Goal(
      id: id,
      ownerId: _stringOf(data['ownerId']),
      title: _stringOf(data['title']),
      categoryId: _stringOf(data['categoryId']),
      createdAt: _dateOf(data['createdAt']) ?? DateTime.now().toUtc(),
      description: _nullableStringOf(data['description']),
      status: GoalStatus.fromWire(_nullableStringOf(data['status'])),
      difficulty: MissionDifficulty.fromWire(
        _nullableStringOf(data['difficulty']),
      ),
      // El progreso lo calcula el servidor a partir de las misiones. Acá solo
      // se lee.
      progress: GoalProgress(
        missionsTotal: _intOf(progress['missionsTotal']),
        missionsCompleted: _intOf(progress['missionsCompleted']),
      ),
      auraEarned: _intOf(data['auraEarned']),
      milestones: _milestonesOf(data['milestones']),
      ai: AiMetadata(
        generated: ai['generated'] == true,
        model: _nullableStringOf(ai['model']),
        promptVersion: _nullableStringOf(ai['promptVersion']),
        jobId: _nullableStringOf(ai['jobId']),
        generatedAt: _dateOf(ai['generatedAt']),
      ),
      colorHex: _nullableStringOf(data['colorHex']),
      icon: _nullableStringOf(data['icon']),
      startDate: _dateOf(data['startDate']),
      targetDate: _dateOf(data['targetDate']),
      completedAt: _dateOf(data['completedAt']),
      updatedAt: _dateOf(data['updatedAt']),
    );
  }

  /// Documento de alta.
  ///
  /// **No incluye `progress` ni `auraEarned`**: las reglas exigen que esas
  /// claves ni siquiera aparezcan. El servidor las crea cuando corresponde.
  static Map<String, Object?> toCreate(Goal goal) => <String, Object?>{
    'ownerId': goal.ownerId,
    'title': goal.title,
    'description': goal.description,
    'categoryId': goal.categoryId,
    'status': goal.status.wireValue,
    'difficulty': goal.difficulty.wireValue,
    'icon': goal.icon,
    'colorHex': goal.colorHex,
    'milestones': goal.milestones.map(_milestoneToMap).toList(growable: false),
    'ai': _aiToMap(goal.ai),
    'startDate': _timestampOf(goal.startDate),
    'targetDate': _timestampOf(goal.targetDate),
    'completedAt': null,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'deletedAt': null,
  };

  /// Campos editables de un objetivo existente.
  ///
  /// **No incluye `ownerId`, `progress` ni `auraEarned`.** Mandar `ownerId` con
  /// el mismo valor pasaría la regla —`diff()` no registra un campo que no
  /// cambió—, pero omitirlo deja la intención explícita y evita que un refactor
  /// futuro lo convierta en un agujero.
  static Map<String, Object?> toUpdate(Goal goal) => <String, Object?>{
    'title': goal.title,
    'description': goal.description,
    'categoryId': goal.categoryId,
    'status': goal.status.wireValue,
    'difficulty': goal.difficulty.wireValue,
    'icon': goal.icon,
    'colorHex': goal.colorHex,
    'milestones': goal.milestones.map(_milestoneToMap).toList(growable: false),
    'startDate': _timestampOf(goal.startDate),
    'targetDate': _timestampOf(goal.targetDate),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Cambio de estado aislado.
  ///
  /// Va aparte de [toUpdate] para que pausar un objetivo desde la lista no
  /// reescriba título, descripción y fechas: menos campos en el `diff` es menos
  /// superficie para que una regla rechace, y menos riesgo de pisar una edición
  /// hecha en otro dispositivo.
  static Map<String, Object?> statusUpdate(GoalStatus status) =>
      <String, Object?>{
        'status': status.wireValue,
        // Marcar el cierre acá y no en el servidor es correcto: `completedAt`
        // no está entre los campos protegidos, y el trigger de Aura usa la
        // transición de estado, no esta fecha.
        if (status == GoalStatus.completed)
          'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Escritura de la lista de hitos.
  static Map<String, Object?> milestonesUpdate(List<Milestone> milestones) =>
      <String, Object?>{
        'milestones': milestones.map(_milestoneToMap).toList(growable: false),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Map<String, Object?> _milestoneToMap(Milestone milestone) =>
      <String, Object?>{
        'id': milestone.id,
        'title': milestone.title,
        'order': milestone.order,
        'done': milestone.done,
        'completedAt': _timestampOf(milestone.completedAt),
      };

  static Map<String, Object?> _aiToMap(AiMetadata ai) => <String, Object?>{
    'generated': ai.generated,
    'model': ai.model,
    'promptVersion': ai.promptVersion,
    'jobId': ai.jobId,
    'generatedAt': _timestampOf(ai.generatedAt),
  };

  /// Lee los hitos embebidos, descartando los que no tengan forma de hito.
  ///
  /// Se ordenan por `order` acá y no en la consulta porque son un array dentro
  /// del documento: Firestore no puede ordenarlos, y la pantalla los necesita
  /// en orden.
  static List<Milestone> _milestonesOf(Object? value) {
    if (value is! List) {
      return const <Milestone>[];
    }

    final milestones = <Milestone>[];
    for (final item in value) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final id = _nullableStringOf(map['id']);
      final title = _nullableStringOf(map['title']);
      // Un hito sin id ni título no se puede mostrar ni marcar: se ignora en
      // lugar de pintar una fila vacía.
      if (id == null || title == null) {
        continue;
      }
      milestones.add(
        Milestone(
          id: id,
          title: title,
          order: _intOf(map['order']),
          done: map['done'] == true,
          completedAt: _dateOf(map['completedAt']),
        ),
      );
    }

    milestones.sort((a, b) => a.order.compareTo(b.order));
    return List<Milestone>.unmodifiable(milestones);
  }

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

  static Timestamp? _timestampOf(DateTime? value) =>
      value == null ? null : Timestamp.fromDate(value);

  // Todo lo que entra al dominio va en UTC: `Timestamp.toDate()` devuelve hora
  // local y las fechas objetivo se comparan contra "hoy".
  static DateTime? _dateOf(Object? value) => switch (value) {
    final Timestamp v => v.toDate().toUtc(),
    final DateTime v => v.toUtc(),
    // Entre que se escribe con `serverTimestamp()` y que el servidor confirma,
    // la caché local devuelve null. No es un error: es el valor pendiente.
    _ => null,
  };
}
