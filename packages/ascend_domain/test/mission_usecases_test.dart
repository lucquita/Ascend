import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

/// Doble del repositorio que registra lo que recibe.
class _FakeMissionRepository implements MissionRepository {
  Mission? created;
  Mission? updated;
  String? completedId;
  Evidence? completedEvidence;
  String? skippedId;
  List<String>? reordered;
  String? deletedId;
  int writeCount = 0;

  @override
  Future<Result<Mission>> createMission(Mission mission) async {
    writeCount++;
    created = mission;
    return Success<Mission>(mission);
  }

  @override
  Future<Result<void>> updateMission(Mission mission) async {
    writeCount++;
    updated = mission;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> completeMission({
    required String uid,
    required String missionId,
    Evidence? evidence,
  }) async {
    writeCount++;
    completedId = missionId;
    completedEvidence = evidence;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> skipMission({
    required String uid,
    required String missionId,
    String? reason,
  }) async {
    writeCount++;
    skippedId = missionId;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> reorderMissions({
    required String uid,
    required List<String> orderedIds,
  }) async {
    writeCount++;
    reordered = orderedIds;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> deleteMission({
    required String uid,
    required String missionId,
  }) async {
    writeCount++;
    deletedId = missionId;
    return const Success<void>(null);
  }

  @override
  Future<Result<Mission>> getMission({
    required String uid,
    required String missionId,
  }) async => const Failed<Mission>(NotFoundFailure(code: 'mission-missing'));

  @override
  Future<Result<Paginated<Mission>>> getHistory({
    required String uid,
    Object? cursor,
    int limit = 20,
  }) async => const Success<Paginated<Mission>>(Paginated<Mission>.empty());

  @override
  Stream<Result<List<Mission>>> watchByGoal({
    required String uid,
    required String goalId,
  }) => const Stream<Result<List<Mission>>>.empty();

  @override
  Stream<Result<List<Mission>>> watchMissions({
    required String uid,
    MissionStatus? status,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    String? categoryId,
    String? goalId,
  }) => const Stream<Result<List<Mission>>>.empty();

  @override
  Stream<Result<List<Mission>>> watchToday({
    required String uid,
    DateTime? day,
  }) => const Stream<Result<List<Mission>>>.empty();
}

Goal _goal({GoalStatus status = GoalStatus.active}) => Goal(
  id: 'g1',
  ownerId: 'u1',
  title: 'Aprender inglés',
  categoryId: 'languages',
  createdAt: DateTime.utc(2026, 8),
  status: status,
);

Mission _mission({
  MissionStatus status = MissionStatus.pending,
  bool requiresEvidence = false,
  Evidence? evidence,
  String title = 'Ver un capítulo en inglés',
  int? estimatedMinutes,
}) => Mission(
  id: 'm1',
  ownerId: 'u1',
  goalId: 'g1',
  title: title,
  createdAt: DateTime.utc(2026, 8),
  status: status,
  requiresEvidence: requiresEvidence,
  evidence: evidence,
  estimatedMinutes: estimatedMinutes,
);

void main() {
  late _FakeMissionRepository repository;

  setUp(() => repository = _FakeMissionRepository());

  group('CreateMissionUseCase', () {
    test('desnormaliza el título y la categoría del objetivo', () async {
      // Sin esto, la pantalla "Hoy" pagaría una lectura extra por misión solo
      // para saber a qué objetivo pertenece.
      await CreateMissionUseCase(
        repository,
      ).call(uid: 'u1', goal: _goal(), title: 'Ver un capítulo');

      expect(repository.created?.goalId, 'g1');
      expect(repository.created?.goalTitle, 'Aprender inglés');
      expect(repository.created?.categoryId, 'languages');
    });

    test('el presupuesto se guarda y por defecto es gratis', () async {
      await CreateMissionUseCase(
        repository,
      ).call(uid: 'u1', goal: _goal(), title: 'Salir a correr');
      expect(repository.created?.budget, MissionBudget.free);

      await CreateMissionUseCase(repository).call(
        uid: 'u1',
        goal: _goal(),
        title: 'Taller de cerámica',
        budget: MissionBudget.high,
      );
      expect(repository.created?.budget, MissionBudget.high);
    });

    test('deriva scheduledFor de la fecha límite', () async {
      await CreateMissionUseCase(repository).call(
        uid: 'u1',
        goal: _goal(),
        title: 'Leer 20 páginas',
        dueDate: DateTime.utc(2026, 8, 20),
      );

      expect(repository.created?.scheduledFor, '2026-08-20');
    });

    test('NO se pueden agregar misiones a un objetivo completado', () async {
      final result = await CreateMissionUseCase(repository).call(
        uid: 'u1',
        goal: _goal(status: GoalStatus.completed),
        title: 'Tarde para esto',
      );

      expect(
        result.failureOrNull?.messageKey,
        'validation.mission.goalNotEditable',
      );
      expect(repository.writeCount, 0);
    });

    test('un título vacío o larguísimo no llega al repositorio', () async {
      final vacio = await CreateMissionUseCase(
        repository,
      ).call(uid: 'u1', goal: _goal(), title: '   ');
      expect(vacio.failureOrNull?.messageKey, 'validation.title.required');

      final largo = await CreateMissionUseCase(
        repository,
      ).call(uid: 'u1', goal: _goal(), title: 'a' * 81);
      expect(largo.failureOrNull?.messageKey, 'validation.title.tooLong');

      expect(repository.writeCount, 0);
    });

    test('una duración imposible se rechaza', () async {
      // Más de 8 horas no es una misión: es otro objetivo disfrazado.
      final larga = await CreateMissionUseCase(repository).call(
        uid: 'u1',
        goal: _goal(),
        title: 'Maratón de estudio',
        estimatedMinutes: kMaxEstimatedMinutes + 1,
      );
      expect(
        larga.failureOrNull?.messageKey,
        'validation.mission.invalidDuration',
      );

      final cero = await CreateMissionUseCase(
        repository,
      ).call(uid: 'u1', goal: _goal(), title: 'Nada', estimatedMinutes: 0);
      expect(
        cero.failureOrNull?.messageKey,
        'validation.mission.invalidDuration',
      );

      expect(repository.writeCount, 0);
    });
  });

  group('CompleteMissionUseCase — la regla que protege el Aura', () {
    test('una misión pendiente se completa', () async {
      final result = await CompleteMissionUseCase(
        repository,
      ).call(uid: 'u1', mission: _mission());

      expect(result.isSuccess, isTrue);
      expect(repository.completedId, 'm1');
    });

    test('una misión ya completada NO se vuelve a completar', () async {
      // Es el exploit más obvio del sistema de Aura: completar dos veces la
      // misma misión para cobrar dos veces.
      final result = await CompleteMissionUseCase(repository).call(
        uid: 'u1',
        mission: _mission(status: MissionStatus.completed),
      );

      expect(
        result.failureOrNull?.messageKey,
        'validation.mission.alreadyCompleted',
      );
      expect(repository.writeCount, 0);
    });

    test('si exige evidencia y no hay foto, no se completa', () async {
      final result = await CompleteMissionUseCase(
        repository,
      ).call(uid: 'u1', mission: _mission(requiresEvidence: true));

      expect(
        result.failureOrNull?.messageKey,
        'validation.mission.evidenceRequired',
      );
      expect(repository.writeCount, 0);
    });

    test(
      'una evidencia solo local ya habilita completar (flujo offline)',
      () async {
        // Es lo que permite cerrar una misión en modo avión: la foto viaja
        // después, pero la misión se completa en el momento.
        final result = await CompleteMissionUseCase(repository).call(
          uid: 'u1',
          mission: _mission(requiresEvidence: true),
          evidence: Evidence(
            capturedAt: DateTime.utc(2026, 8, 14),
            localPath: '/tmp/foto.jpg',
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(repository.completedEvidence?.localPath, '/tmp/foto.jpg');
      },
    );
  });

  group('SkipMissionUseCase', () {
    test('saltea una misión abierta', () async {
      final result = await SkipMissionUseCase(
        repository,
      ).call(uid: 'u1', mission: _mission());

      expect(result.isSuccess, isTrue);
      expect(repository.skippedId, 'm1');
    });

    test('no se saltea algo ya completado', () async {
      final result = await SkipMissionUseCase(repository).call(
        uid: 'u1',
        mission: _mission(status: MissionStatus.completed),
      );

      expect(result.failureOrNull?.messageKey, 'validation.mission.notOpen');
      expect(repository.writeCount, 0);
    });
  });

  group('UpdateMissionUseCase', () {
    test('una misión completada no se edita', () async {
      // Su logro ya otorgó Aura y puede estar publicado en la comunidad.
      final result = await UpdateMissionUseCase(
        repository,
      ).call(_mission(status: MissionStatus.completed));

      expect(
        result.failureOrNull?.messageKey,
        'validation.mission.completedNotEditable',
      );
      expect(repository.writeCount, 0);
    });

    test('aplica la MISMA validación de título que el alta', () async {
      final result = await UpdateMissionUseCase(
        repository,
      ).call(_mission(title: 'a' * 81));

      expect(result.failureOrNull?.messageKey, 'validation.title.tooLong');
      expect(repository.writeCount, 0);
    });
  });

  group('ReorderMissionsUseCase', () {
    test('guarda el orden nuevo', () async {
      await ReorderMissionsUseCase(
        repository,
      ).call(uid: 'u1', orderedIds: <String>['m3', 'm1', 'm2']);

      expect(repository.reordered, <String>['m3', 'm1', 'm2']);
    });

    test('una lista vacía no escribe ni falla', () async {
      final result = await ReorderMissionsUseCase(
        repository,
      ).call(uid: 'u1', orderedIds: const <String>[]);

      expect(result.isSuccess, isTrue);
      expect(repository.writeCount, 0);
    });

    test('ids repetidos se rechazan', () async {
      // Dejarían dos misiones con la misma posición y un orden no determinista.
      final result = await ReorderMissionsUseCase(
        repository,
      ).call(uid: 'u1', orderedIds: <String>['m1', 'm2', 'm1']);

      expect(
        result.failureOrNull?.messageKey,
        'validation.mission.duplicateOrder',
      );
      expect(repository.writeCount, 0);
    });
  });

  group('Ayudas de presentación del dominio', () {
    test('groupMissionsByGoal agrupa conservando el orden', () {
      final grouped = groupMissionsByGoal(<Mission>[
        _mission(),
        Mission(
          id: 'm2',
          ownerId: 'u1',
          goalId: 'g2',
          title: 'Correr',
          createdAt: DateTime.utc(2026, 8),
        ),
        Mission(
          id: 'm3',
          ownerId: 'u1',
          goalId: 'g1',
          title: 'Escuchar podcast',
          createdAt: DateTime.utc(2026, 8),
        ),
      ]);

      expect(grouped.keys, <String>['g1', 'g2']);
      expect(grouped['g1'], hasLength(2));
    });

    test('DailyProgress resume el avance del día', () {
      final progress = DailyProgress.from(<Mission>[
        _mission(status: MissionStatus.completed),
        _mission(),
        _mission(),
      ]);

      expect(progress.total, 3);
      expect(progress.completed, 1);
      expect(progress.remaining, 2);
      expect(progress.fraction, closeTo(0.333, 0.01));
      expect(progress.isDone, isFalse);
    });

    test('un día sin misiones no divide por cero', () {
      const progress = DailyProgress(total: 0, completed: 0);
      expect(progress.fraction, 0);
      expect(progress.isDone, isFalse);
    });

    test('resolveCategory tolera una categoría dada de baja', () {
      const catalog = <Category>[
        Category(
          id: 'languages',
          names: <String, String>{'es': 'Idiomas'},
          icon: 'translate',
          colorHex: '#3B82F6',
        ),
      ];

      expect(resolveCategory(catalog, 'languages')?.id, 'languages');
      // Un objetivo viejo puede apuntar a una categoría que ya no existe: eso
      // no puede romper la pantalla.
      expect(resolveCategory(catalog, 'borrada'), isNull);
      expect(resolveCategory(catalog, null), isNull);
    });
  });

  group('MissionBudget', () {
    test('un valor desconocido degrada a gratis', () {
      // Sesgo deliberado: mostrar de más en un filtro de presupuesto es mejor
      // que esconder una misión que la persona sí podía hacer.
      expect(MissionBudget.fromWire('carísimo'), MissionBudget.free);
      expect(MissionBudget.fromWire(null), MissionBudget.free);
    });

    test('el ida y vuelta por wireValue es estable', () {
      for (final budget in MissionBudget.values) {
        expect(MissionBudget.fromWire(budget.wireValue), budget);
      }
    });
  });
}
