import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

/// Doble del repositorio que registra lo que recibe.
///
/// No es un mock generado: el contrato es del dominio y no menciona Firebase,
/// así que un doble a mano alcanza y deja ver exactamente qué se verificó.
class _FakeGoalRepository implements GoalRepository {
  Goal? createdGoal;
  Goal? updatedGoal;
  GoalStatus? statusWritten;
  String? deletedGoalId;
  ({String milestoneId, bool done})? toggled;
  int writeCount = 0;

  @override
  Future<Result<Goal>> createGoal(Goal goal) async {
    writeCount++;
    createdGoal = goal;
    return Success<Goal>(goal);
  }

  @override
  Future<Result<Goal>> createGoalWithMissions({
    required Goal goal,
    required List<Mission> missions,
  }) async => Success<Goal>(goal);

  @override
  Future<Result<void>> updateGoal(Goal goal) async {
    writeCount++;
    updatedGoal = goal;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> updateStatus({
    required String uid,
    required String goalId,
    required GoalStatus status,
  }) async {
    writeCount++;
    statusWritten = status;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> deleteGoal({
    required String uid,
    required String goalId,
  }) async {
    writeCount++;
    deletedGoalId = goalId;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> toggleMilestone({
    required String uid,
    required String goalId,
    required String milestoneId,
    required bool done,
  }) async {
    writeCount++;
    toggled = (milestoneId: milestoneId, done: done);
    return const Success<void>(null);
  }

  @override
  Stream<Result<List<Goal>>> watchGoals({
    required String uid,
    GoalStatus? status,
    String? categoryId,
  }) => const Stream<Result<List<Goal>>>.empty();

  @override
  Stream<Result<Goal>> watchGoal({
    required String uid,
    required String goalId,
  }) => const Stream<Result<Goal>>.empty();
}

Goal _goal({
  GoalStatus status = GoalStatus.active,
  String title = 'Aprender inglés',
  String categoryId = 'languages',
  String? description,
  List<Milestone> milestones = const <Milestone>[],
  DateTime? startDate,
  DateTime? targetDate,
}) => Goal(
  id: 'g1',
  ownerId: 'u1',
  title: title,
  categoryId: categoryId,
  createdAt: DateTime.utc(2026, 8),
  status: status,
  description: description,
  milestones: milestones,
  startDate: startDate,
  targetDate: targetDate,
);

void main() {
  late _FakeGoalRepository repository;

  setUp(() => repository = _FakeGoalRepository());

  group('CreateGoalUseCase — validación', () {
    test('crea el objetivo con los datos normalizados', () async {
      final result = await CreateGoalUseCase(repository).call(
        uid: 'u1',
        title: '  Aprender inglés  ',
        categoryId: 'languages',
        description: '  Charlar 20 minutos  ',
      );

      expect(result.isSuccess, isTrue);
      expect(repository.createdGoal?.title, 'Aprender inglés');
      expect(repository.createdGoal?.description, 'Charlar 20 minutos');
      expect(repository.createdGoal?.ownerId, 'u1');
    });

    test(
      'genera un id en el cliente para que el alta sea idempotente',
      () async {
        await CreateGoalUseCase(
          repository,
        ).call(uid: 'u1', title: 'Correr 5k', categoryId: 'fitness');

        // Sin id de cliente, un reintento tras un corte de red crearía un
        // segundo objetivo idéntico.
        expect(repository.createdGoal?.id, isNotEmpty);
      },
    );

    test('un título vacío no llega al repositorio', () async {
      final result = await CreateGoalUseCase(
        repository,
      ).call(uid: 'u1', title: '   ', categoryId: 'languages');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull?.messageKey, 'validation.title.required');
      expect(repository.writeCount, 0);
    });

    test('un título de más de 80 caracteres se rechaza en el cliente', () async {
      // El mismo límite que aplica `isValidString('title', 80)` en las reglas.
      // Validar acá evita una escritura que el servidor va a rechazar igual.
      final result = await CreateGoalUseCase(
        repository,
      ).call(uid: 'u1', title: 'a' * 81, categoryId: 'languages');

      expect(result.failureOrNull?.messageKey, 'validation.title.tooLong');
      expect(repository.writeCount, 0);
    });

    test('sin categoría no se crea', () async {
      final result = await CreateGoalUseCase(
        repository,
      ).call(uid: 'u1', title: 'Leer más', categoryId: '  ');

      expect(result.failureOrNull?.messageKey, 'validation.category.required');
      expect(repository.writeCount, 0);
    });

    test('una descripción larguísima se rechaza', () async {
      final result = await CreateGoalUseCase(repository).call(
        uid: 'u1',
        title: 'Leer más',
        categoryId: 'reading',
        description: 'a' * (kMaxGoalDescriptionLength + 1),
      );

      expect(
        result.failureOrNull?.messageKey,
        'validation.description.tooLong',
      );
      expect(repository.writeCount, 0);
    });

    test('más de 8 hitos se rechazan', () async {
      // Los hitos van embebidos: si crecieran sin techo, cada lectura de la
      // lista de objetivos se volvería cara.
      final result = await CreateGoalUseCase(repository).call(
        uid: 'u1',
        title: 'Aprender inglés',
        categoryId: 'languages',
        milestones: <Milestone>[
          for (var i = 0; i <= kMaxMilestones; i++)
            Milestone(id: 'm$i', title: 'Hito $i', order: i),
        ],
      );

      expect(result.failureOrNull?.messageKey, 'validation.milestones.tooMany');
      expect(repository.writeCount, 0);
    });

    test('una fecha objetivo anterior al inicio se rechaza', () async {
      final result = await CreateGoalUseCase(repository).call(
        uid: 'u1',
        title: 'Correr 5k',
        categoryId: 'fitness',
        startDate: DateTime.utc(2026, 9),
        targetDate: DateTime.utc(2026, 8),
      );

      expect(
        result.failureOrNull?.messageKey,
        'validation.targetDate.beforeStart',
      );
      expect(repository.writeCount, 0);
    });

    test(
      'una descripción vacía se guarda como nula, no como cadena vacía',
      () async {
        await CreateGoalUseCase(repository).call(
          uid: 'u1',
          title: 'Correr 5k',
          categoryId: 'fitness',
          description: '   ',
        );

        expect(repository.createdGoal?.description, isNull);
      },
    );
  });

  group('UpdateGoalUseCase', () {
    test('guarda los cambios de un objetivo editable', () async {
      final result = await UpdateGoalUseCase(
        repository,
      ).call(_goal(title: 'Aprender alemán'));

      expect(result.isSuccess, isTrue);
      expect(repository.updatedGoal?.title, 'Aprender alemán');
    });

    test('un objetivo completado NO se puede editar', () async {
      // Cambiarle el título después de completarlo reescribe la historia que
      // la comunidad ya vio.
      final result = await UpdateGoalUseCase(
        repository,
      ).call(_goal(status: GoalStatus.completed));

      expect(result.failureOrNull?.messageKey, 'validation.goal.notEditable');
      expect(repository.writeCount, 0);
    });

    test('un objetivo archivado tampoco', () async {
      final result = await UpdateGoalUseCase(
        repository,
      ).call(_goal(status: GoalStatus.archived));

      expect(result.failureOrNull?.messageKey, 'validation.goal.notEditable');
    });

    test('aplica la MISMA validación que el alta', () async {
      // Si la edición validara distinto, se podría guardar por edición un
      // objetivo que el alta habría rechazado.
      final result = await UpdateGoalUseCase(
        repository,
      ).call(_goal(title: 'a' * 81));

      expect(result.failureOrNull?.messageKey, 'validation.title.tooLong');
      expect(repository.writeCount, 0);
    });
  });

  group('ChangeGoalStatusUseCase — transiciones', () {
    Future<Result<void>> change(GoalStatus from, GoalStatus to) =>
        ChangeGoalStatusUseCase(
          repository,
        ).call(uid: 'u1', goalId: 'g1', from: from, to: to);

    test('las transiciones normales se permiten', () async {
      for (final transition in <(GoalStatus, GoalStatus)>[
        (GoalStatus.draft, GoalStatus.active),
        (GoalStatus.active, GoalStatus.paused),
        (GoalStatus.active, GoalStatus.completed),
        (GoalStatus.paused, GoalStatus.active),
        (GoalStatus.completed, GoalStatus.archived),
        (GoalStatus.archived, GoalStatus.active),
      ]) {
        final result = await change(transition.$1, transition.$2);
        expect(
          result.isSuccess,
          isTrue,
          reason: '${transition.$1} → ${transition.$2} debería permitirse',
        );
      }
    });

    test('completar un objetivo pausado de un salto se rechaza', () async {
      // Habría que reactivarlo primero: completar desde pausa saltea el
      // trabajo real y es la vía obvia para inflar objetivos completados.
      final result = await change(GoalStatus.paused, GoalStatus.completed);

      expect(
        result.failureOrNull?.messageKey,
        'validation.goal.invalidTransition',
      );
      expect(repository.writeCount, 0);
    });

    test('un objetivo completado no se "descompleta"', () async {
      // El Aura ya se otorgó; revertirla es una operación de servidor.
      final result = await change(GoalStatus.completed, GoalStatus.active);

      expect(
        result.failureOrNull?.messageKey,
        'validation.goal.invalidTransition',
      );
    });

    test('pedir el estado que ya tiene no escribe ni falla', () async {
      final result = await change(GoalStatus.active, GoalStatus.active);

      expect(result.isSuccess, isTrue);
      expect(repository.writeCount, 0, reason: 'No hay nada que escribir.');
    });
  });

  group('ToggleMilestoneUseCase y DeleteGoalUseCase', () {
    test('marcar un hito delega con los datos correctos', () async {
      await ToggleMilestoneUseCase(
        repository,
      ).call(uid: 'u1', goalId: 'g1', milestoneId: 'm2', done: true);

      expect(repository.toggled?.milestoneId, 'm2');
      expect(repository.toggled?.done, isTrue);
    });

    test('borrar delega en el repositorio', () async {
      await DeleteGoalUseCase(repository).call(uid: 'u1', goalId: 'g1');

      expect(repository.deletedGoalId, 'g1');
    });
  });
}
