import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Mission _mission({
  MissionStatus status = MissionStatus.pending,
  Evidence? evidence,
  Recurrence? recurrence,
  DateTime? dueDate,
}) => Mission(
  id: 'm1',
  ownerId: 'u1',
  goalId: 'g1',
  title: 'Ver un capítulo en inglés',
  createdAt: DateTime.utc(2026, 8),
  goalTitle: 'Aprender inglés',
  categoryId: 'languages',
  description: 'Anotar 5 palabras nuevas',
  status: status,
  difficulty: MissionDifficulty.hard,
  budget: MissionBudget.medium,
  // Se construye CON recompensa a propósito: es el campo que no debe viajar
  // aunque la entidad lo tenga cargado.
  auraReward: 50,
  estimatedMinutes: 25,
  dueDate: dueDate,
  recurrence: recurrence,
  evidence: evidence,
);

void main() {
  group('MissionDto — el campo que nunca viaja', () {
    test('toCreate NO incluye auraReward', () {
      // `absent('auraReward')` mira la PRESENCIA de la clave: mandarla en null
      // haría fallar el alta entera igual que mandar una recompensa inventada.
      // Si el cliente pudiera fijarla, se otorgaría el Aura que quisiera.
      expect(
        MissionDto.toCreate(_mission()).containsKey('auraReward'),
        isFalse,
      );
    });

    test('toUpdate NO incluye auraReward ni ownerId', () {
      final update = MissionDto.toUpdate(_mission());

      for (final field in <String>['auraReward', 'ownerId']) {
        expect(
          update.containsKey(field),
          isFalse,
          reason: 'La clave "$field" viola `unchanged()` en la edición.',
        );
      }
    });

    test('ninguna escritura de estado toca la recompensa', () {
      for (final update in <Map<String, Object?>>[
        MissionDto.completionUpdate(),
        MissionDto.statusUpdate(MissionStatus.skipped),
        MissionDto.orderUpdate(3),
      ]) {
        expect(update.containsKey('auraReward'), isFalse);
      }
    });

    test('toCreate manda ownerId, porque la regla lo exige', () {
      expect(MissionDto.toCreate(_mission())['ownerId'], 'u1');
    });

    test('toCreate desnormaliza goalTitle y categoryId', () {
      final create = MissionDto.toCreate(_mission());

      expect(create['goalTitle'], 'Aprender inglés');
      expect(create['categoryId'], 'languages');
    });

    test('los enums viajan por su wireValue', () {
      final create = MissionDto.toCreate(_mission());

      expect(create['status'], 'pending');
      expect(create['difficulty'], 'hard');
      expect(create['budget'], 'medium');
    });

    test('completar sella la fecha y adjunta la evidencia', () {
      final update = MissionDto.completionUpdate(
        evidence: Evidence(
          capturedAt: DateTime.utc(2026, 8, 14),
          localPath: '/tmp/foto.jpg',
          note: 'Terminé el capítulo 3',
        ),
      );

      expect(update['status'], 'completed');
      expect(update['completedAt'], isNotNull);
      final evidence = update['evidence']! as Map<String, Object?>;
      expect(evidence['localPath'], '/tmp/foto.jpg');
      expect(evidence['uploadStatus'], 'pending');
    });

    test('completar sin evidencia no manda la clave evidence', () {
      // Mandar `evidence: null` borraría una evidencia que ya estuviera
      // adjunta desde otra pantalla.
      expect(MissionDto.completionUpdate().containsKey('evidence'), isFalse);
    });

    test('el reordenamiento solo escribe la posición', () {
      final update = MissionDto.orderUpdate(3);

      expect(update['order'], 3);
      expect(update.containsKey('title'), isFalse);
      expect(update.containsKey('status'), isFalse);
    });
  });

  group('MissionDto — lectura tolerante', () {
    test('mapea un documento completo', () {
      final mission = MissionDto.fromMap(<String, dynamic>{
        'ownerId': 'u1',
        'goalId': 'g1',
        'goalTitle': 'Aprender inglés',
        'categoryId': 'languages',
        'title': 'Ver un capítulo',
        'status': 'in_progress',
        'difficulty': 'easy',
        'budget': 'high',
        'auraReward': 25,
        'estimatedMinutes': 25,
        'requiresEvidence': true,
        'order': 3,
        'dueDate': Timestamp.fromDate(DateTime.utc(2026, 8, 20)),
        'recurrence': <String, dynamic>{
          'type': 'weekly',
          'days': <int>[1, 3, 5],
        },
        'evidence': <String, dynamic>{
          'photoUrl': 'https://cdn/e.jpg',
          'note': 'Listo',
          'uploadStatus': 'uploaded',
          'capturedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 14)),
        },
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8)),
      }, id: 'm1');

      expect(mission.status, MissionStatus.inProgress);
      expect(mission.difficulty, MissionDifficulty.easy);
      expect(mission.budget, MissionBudget.high);
      expect(mission.auraReward, 25);
      expect(mission.order, 3);
      expect(mission.recurrence?.weekdays, <int>[1, 3, 5]);
      expect(mission.evidence?.uploadStatus, EvidenceUploadStatus.uploaded);
      expect(mission.evidence?.hasImage, isTrue);
    });

    test('un documento vacío no rompe la lista del día', () {
      final mission = MissionDto.fromMap(const <String, dynamic>{}, id: 'm1');

      expect(mission.title, isEmpty);
      expect(mission.status, MissionStatus.pending);
      expect(mission.budget, MissionBudget.free);
      expect(mission.evidence, isNull);
      expect(mission.recurrence, isNull);
      expect(mission.createdAt, isNotNull);
    });

    test('tolera campos con el tipo equivocado', () {
      final mission = MissionDto.fromMap(<String, dynamic>{
        'title': 42,
        'evidence': 'no soy un mapa',
        'recurrence': <String>['tampoco'],
        'order': 2.9,
        'estimatedMinutes': 'un rato',
      }, id: 'm1');

      expect(mission.title, isEmpty);
      expect(mission.evidence, isNull);
      expect(mission.order, 2);
      expect(mission.estimatedMinutes, isNull);
    });

    test('un presupuesto desconocido degrada a gratis', () {
      final mission = MissionDto.fromMap(<String, dynamic>{
        'budget': 'carísimo',
      }, id: 'm1');

      expect(mission.budget, MissionBudget.free);
    });

    test('las fechas entran al dominio en UTC', () {
      final mission = MissionDto.fromMap(<String, dynamic>{
        'dueDate': Timestamp.fromDate(DateTime.utc(2026, 8, 20)),
      }, id: 'm1');

      expect(mission.dueDate?.isUtc, isTrue);
    });

    test('el ida y vuelta conserva lo que el cliente sí controla', () {
      final original = _mission(dueDate: DateTime.utc(2026, 8, 20));
      final map = MissionDto.toCreate(original);

      // `toCreate` usa centinelas de servidor para las fechas de auditoría, así
      // que se releen solo los campos de negocio.
      final rebuilt = MissionDto.fromMap(<String, dynamic>{
        ...map,
        'createdAt': Timestamp.fromDate(original.createdAt),
      }, id: original.id);

      expect(rebuilt.title, original.title);
      expect(rebuilt.difficulty, original.difficulty);
      expect(rebuilt.budget, original.budget);
      expect(rebuilt.goalTitle, original.goalTitle);
      expect(rebuilt.dueDate, original.dueDate);
      // Y lo que el cliente NO controla vuelve en cero, porque nunca viajó.
      expect(rebuilt.auraReward, 0);
    });
  });
}
