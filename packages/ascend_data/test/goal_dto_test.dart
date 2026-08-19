import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Campos que las reglas de Firestore **prohíben** al cliente.
///
/// ```
/// allow create: ... && absent('progress') && absent('auraEarned');
/// allow update: ... && unchanged('ownerId')
///                   && unchanged('progress') && unchanged('auraEarned');
/// ```
const List<String> _serverOwnedFields = <String>['progress', 'auraEarned'];

Goal _goal({
  List<Milestone> milestones = const <Milestone>[],
  GoalStatus status = GoalStatus.active,
  DateTime? targetDate,
}) => Goal(
  id: 'g1',
  ownerId: 'u1',
  title: 'Aprender inglés',
  categoryId: 'languages',
  createdAt: DateTime.utc(2026, 8),
  description: 'Charlar 20 minutos',
  status: status,
  milestones: milestones,
  targetDate: targetDate,
  // Se construye con progreso y aura ya cargados a propósito: son los campos
  // que NO tienen que viajar aunque la entidad los tenga.
  progress: const GoalProgress(missionsTotal: 24, missionsCompleted: 9),
  auraEarned: 450,
);

void main() {
  group('GoalDto — escritura: lo que las reglas prohíben', () {
    test('toCreate NO incluye progress ni auraEarned', () {
      // `absent()` mira la PRESENCIA de la clave, no su valor: mandar
      // `progress: null` haría fallar el alta entera igual que mandar un
      // progreso inventado.
      final create = GoalDto.toCreate(_goal());

      for (final field in _serverOwnedFields) {
        expect(
          create.containsKey(field),
          isFalse,
          reason:
              'La clave "$field" en el alta hace que la regla `absent()` '
              'rechace la escritura completa.',
        );
      }
    });

    test('toUpdate NO incluye ownerId, progress ni auraEarned', () {
      final update = GoalDto.toUpdate(_goal());

      for (final field in <String>[..._serverOwnedFields, 'ownerId']) {
        expect(
          update.containsKey(field),
          isFalse,
          reason: 'La clave "$field" viola `unchanged()` en la edición.',
        );
      }
    });

    test('toCreate manda ownerId, porque la regla lo exige', () {
      // `request.resource.data.ownerId == uid` es lo que impide crear un
      // objetivo a nombre de otra persona.
      expect(GoalDto.toCreate(_goal())['ownerId'], 'u1');
    });

    test('statusUpdate escribe solo estado y fechas', () {
      final update = GoalDto.statusUpdate(GoalStatus.paused);

      expect(update.keys, containsAll(<String>['status', 'updatedAt']));
      expect(update['status'], 'paused');
      // Menos campos en el `diff` es menos superficie para que una regla
      // rechace, y menos riesgo de pisar una edición de otro dispositivo.
      expect(update.containsKey('title'), isFalse);
      expect(update.containsKey('completedAt'), isFalse);
    });

    test('completar sella la fecha de cierre', () {
      final update = GoalDto.statusUpdate(GoalStatus.completed);

      expect(update['status'], 'completed');
      expect(update['completedAt'], isNotNull);
    });

    test('los enums viajan por su wireValue, no por su nombre de Dart', () {
      final create = GoalDto.toCreate(_goal());

      expect(create['status'], 'active');
      expect(create['difficulty'], 'medium');
    });

    test('las fechas se serializan como Timestamp de Firestore', () {
      final create = GoalDto.toCreate(
        _goal(targetDate: DateTime.utc(2026, 12, 31)),
      );

      expect(create['targetDate'], isA<Timestamp>());
    });

    test('los hitos viajan como lista de mapas planos', () {
      final create = GoalDto.toCreate(
        _goal(
          milestones: <Milestone>[
            const Milestone(id: 'm1', title: 'Vocabulario base', order: 0),
          ],
        ),
      );

      final milestones = create['milestones']! as List<Object?>;
      expect(milestones, hasLength(1));
      expect((milestones.first! as Map)['title'], 'Vocabulario base');
      expect((milestones.first! as Map)['done'], isFalse);
    });
  });

  group('GoalDto — lectura tolerante', () {
    test('mapea un documento completo', () {
      final goal = GoalDto.fromMap(<String, dynamic>{
        'ownerId': 'u1',
        'title': 'Aprender inglés',
        'categoryId': 'languages',
        'description': 'Charlar 20 minutos',
        'status': 'paused',
        'difficulty': 'hard',
        'progress': <String, dynamic>{
          'missionsTotal': 24,
          'missionsCompleted': 9,
        },
        'auraEarned': 450,
        'colorHex': '#3B82F6',
        'icon': 'language',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8)),
        'targetDate': Timestamp.fromDate(DateTime.utc(2026, 12, 31)),
      }, id: 'g1');

      expect(goal.id, 'g1');
      expect(goal.status, GoalStatus.paused);
      expect(goal.difficulty, MissionDifficulty.hard);
      expect(goal.progress.missionsCompleted, 9);
      expect(goal.progress.fraction, closeTo(0.375, 0.0001));
      expect(goal.auraEarned, 450);
      expect(goal.targetDate, DateTime.utc(2026, 12, 31));
    });

    test('un documento vacío no rompe: cae a los valores por defecto', () {
      // Un objetivo a medio escribir tiene que poder abrirse para arreglarlo,
      // no reventar la lista entera.
      final goal = GoalDto.fromMap(const <String, dynamic>{}, id: 'g1');

      expect(goal.title, isEmpty);
      expect(goal.status, GoalStatus.active);
      expect(goal.progress.missionsTotal, 0);
      expect(goal.milestones, isEmpty);
      expect(goal.createdAt, isNotNull);
    });

    test('tolera campos con el tipo equivocado', () {
      final goal = GoalDto.fromMap(<String, dynamic>{
        'title': 42,
        'progress': 'no soy un mapa',
        'milestones': 'tampoco soy una lista',
        'auraEarned': 12.7,
      }, id: 'g1');

      expect(goal.title, isEmpty);
      expect(goal.progress.missionsTotal, 0);
      expect(goal.milestones, isEmpty);
      expect(goal.auraEarned, 12);
    });

    test('un estado desconocido degrada a activo en vez de romper', () {
      final goal = GoalDto.fromMap(<String, dynamic>{
        'status': 'un_estado_del_futuro',
      }, id: 'g1');

      expect(goal.status, GoalStatus.active);
    });

    test('los hitos se devuelven ordenados por order', () {
      // Son un array dentro del documento: Firestore no puede ordenarlos y la
      // pantalla los necesita en orden.
      final goal = GoalDto.fromMap(<String, dynamic>{
        'milestones': <Object?>[
          <String, dynamic>{'id': 'm3', 'title': 'Tercero', 'order': 2},
          <String, dynamic>{'id': 'm1', 'title': 'Primero', 'order': 0},
          <String, dynamic>{'id': 'm2', 'title': 'Segundo', 'order': 1},
        ],
      }, id: 'g1');

      expect(goal.milestones.map((m) => m.id), <String>['m1', 'm2', 'm3']);
    });

    test(
      'descarta hitos sin id o sin título en vez de pintar filas vacías',
      () {
        final goal = GoalDto.fromMap(<String, dynamic>{
          'milestones': <Object?>[
            <String, dynamic>{'id': 'm1', 'title': 'Válido', 'order': 0},
            <String, dynamic>{'title': 'Sin id', 'order': 1},
            <String, dynamic>{'id': 'm3', 'order': 2},
            'ni siquiera es un mapa',
          ],
        }, id: 'g1');

        expect(goal.milestones, hasLength(1));
        expect(goal.milestones.single.id, 'm1');
      },
    );

    test('un timestamp pendiente de servidor se lee como nulo, no falla', () {
      // Entre que se escribe con `serverTimestamp()` y que el servidor
      // confirma, la caché local devuelve null.
      final goal = GoalDto.fromMap(<String, dynamic>{
        'updatedAt': null,
      }, id: 'g1');

      expect(goal.updatedAt, isNull);
      expect(goal.createdAt, isNotNull);
    });

    test('las fechas entran al dominio en UTC', () {
      // `Timestamp.toDate()` devuelve hora local; mezclarlo con el resto del
      // dominio daría resultados distintos según el huso del dispositivo.
      final goal = GoalDto.fromMap(<String, dynamic>{
        'targetDate': Timestamp.fromDate(DateTime.utc(2026, 12, 31)),
      }, id: 'g1');

      expect(goal.targetDate?.isUtc, isTrue);
    });
  });

  group('CategoryDto', () {
    test('mapea nombres y descripciones por idioma', () {
      final category = CategoryDto.fromMap(<String, dynamic>{
        'name': <String, dynamic>{'es': 'Idiomas', 'en': 'Languages'},
        'description': <String, dynamic>{'es': 'Aprender un idioma'},
        'icon': 'translate',
        'colorHex': '#3B82F6',
        'order': 2,
        'active': true,
        'goalsCount': 1284,
      }, id: 'languages');

      expect(category.nameFor('en'), 'Languages');
      expect(category.nameFor('es'), 'Idiomas');
      expect(category.descriptionFor('es'), 'Aprender un idioma');
      expect(category.goalsCount, 1284);
    });

    test('un idioma sin traducir cae a español y luego al id', () {
      final category = CategoryDto.fromMap(<String, dynamic>{
        'name': <String, dynamic>{'es': 'Idiomas'},
      }, id: 'languages');

      expect(category.nameFor('pt'), 'Idiomas');

      final sinNombre = CategoryDto.fromMap(
        const <String, dynamic>{},
        id: 'languages',
      );
      expect(sinNombre.nameFor('es'), 'languages');
    });

    test('sin el campo active la categoría se considera activa', () {
      // Un documento viejo del catálogo no es una categoría dada de baja.
      final category = CategoryDto.fromMap(
        const <String, dynamic>{},
        id: 'fitness',
      );

      expect(category.active, isTrue);
    });

    test('descarta traducciones que no sean texto', () {
      final category = CategoryDto.fromMap(<String, dynamic>{
        'name': <String, dynamic>{'es': 'Idiomas', 'en': 42, 'pt': null},
      }, id: 'languages');

      expect(category.names.keys, <String>['es']);
    });
  });
}
