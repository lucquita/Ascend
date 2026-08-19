import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctions;

/// Implementación de [AiRepository] sobre la Cloud Function llamable.
///
/// **El cliente nunca habla con Gemini** (ADR-002): manda el pedido a
/// `generateGoalPlan`, que lee la key de Secret Manager. Si la key viajara en el
/// binario, se extraería de un APK en cinco minutos y la factura sería nuestra.
class AiRepositoryImpl implements AiRepository {
  /// Crea el repositorio.
  const AiRepositoryImpl({
    required FirebaseFunctions functions,
    required FirebaseFirestore firestore,
  }) : _functions = functions,
       _firestore = firestore;

  /// Cuántas generaciones se permiten por día. Coincide con `LIMITS` del
  /// servidor, que es quien realmente lo aplica.
  static const int dailyLimit = 20;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  @override
  Future<Result<ProposedPlan>> generateGoalPlan({
    required String goalTitle,
    required String categoryId,
    String? description,
    int horizonDays = 90,
    int missionCount = 6,
    MissionBudget budget = MissionBudget.free,
  }) => runGuarded(() async {
    final response = await _functions
        .httpsCallable('generateGoalPlan')
        .call<Map<String, dynamic>>(<String, Object?>{
          'goalTitle': goalTitle,
          'categoryId': categoryId,
          if (description != null && description.isNotEmpty)
            'description': description,
          'horizonDays': horizonDays,
          'missionCount': missionCount,
          'budget': budget.wireValue,
        });

    return _planFrom(response.data);
  });

  @override
  Future<Result<int>> remainingQuota(String uid) => runGuarded(() async {
    final today = AscendDateUtils.toDayKey(DateTime.now().toUtc());
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('aiUsage')
        .doc(today)
        .get();

    final used = switch (snapshot.data()?['generations']) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0,
    };
    return (dailyLimit - used).clamp(0, dailyLimit);
  });

  /// Convierte la respuesta de la llamable en el plan del dominio.
  ///
  /// El servidor ya validó la forma contra un schema estricto; acá se vuelve a
  /// leer con tolerancia porque el `Map<String, dynamic>` que devuelve el SDK
  /// no tiene tipos: un campo faltante rompería con un cast crudo.
  static ProposedPlan _planFrom(Map<String, dynamic> data) {
    final rawMissions = data['missions'];
    final missions = <ProposedMission>[];

    if (rawMissions is List) {
      for (final item in rawMissions) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final title = map['title'];
        if (title is! String || title.isEmpty) {
          continue;
        }
        missions.add(
          ProposedMission(
            title: title,
            description: map['description'] is String
                ? map['description'] as String
                : null,
            difficulty: MissionDifficulty.fromWire(
              map['difficulty'] as String?,
            ),
            budget: MissionBudget.fromWire(map['budget'] as String?),
            estimatedMinutes: switch (map['estimatedMinutes']) {
              final int v => v,
              final num v => v.toInt(),
              _ => null,
            },
          ),
        );
      }
    }

    final rawMilestones = data['milestones'];
    final milestones = <String>[];
    if (rawMilestones is List) {
      for (final item in rawMilestones) {
        if (item is Map && item['title'] is String) {
          milestones.add(item['title'] as String);
        }
      }
    }

    return ProposedPlan(
      missions: missions,
      milestones: milestones,
      model: data['model'] is String ? data['model'] as String : null,
      promptVersion: data['promptVersion'] is String
          ? data['promptVersion'] as String
          : null,
    );
  }
}
