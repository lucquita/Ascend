import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

/// Repositorio de IA que responde lo que le pidamos.
class _FakeAiRepository implements AiRepository {
  Result<ProposedPlan>? nextPlan;
  int calls = 0;

  @override
  Future<Result<ProposedPlan>> generateGoalPlan({
    required String goalTitle,
    required String categoryId,
    String? description,
    int horizonDays = 90,
    int missionCount = 6,
    MissionBudget budget = MissionBudget.free,
  }) async {
    calls++;
    return nextPlan ??
        const Failed<ProposedPlan>(ServerFailure(code: 'sin configurar'));
  }

  @override
  Future<Result<int>> remainingQuota(String uid) async =>
      const Success<int>(20);
}

class _RecordingGoalRepository implements GoalRepository {
  Goal? createdGoal;
  List<Mission>? createdMissions;

  @override
  Future<Result<Goal>> createGoalWithMissions({
    required Goal goal,
    required List<Mission> missions,
  }) async {
    createdGoal = goal;
    createdMissions = missions;
    return Success<Goal>(goal);
  }

  @override
  Future<Result<Goal>> createGoal(Goal goal) async => Success<Goal>(goal);

  @override
  Future<Result<void>> updateGoal(Goal goal) async => const Success<void>(null);

  @override
  Future<Result<void>> updateStatus({
    required String uid,
    required String goalId,
    required GoalStatus status,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> deleteGoal({
    required String uid,
    required String goalId,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> toggleMilestone({
    required String uid,
    required String goalId,
    required String milestoneId,
    required bool done,
  }) async => const Success<void>(null);

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

void main() {
  late _FakeAiRepository ai;
  late _RecordingGoalRepository goals;

  setUp(() {
    ai = _FakeAiRepository();
    goals = _RecordingGoalRepository();
  });

  group('GenerateGoalPlanUseCase — la IA nunca deja a nadie sin salida', () {
    test('devuelve el plan de la IA cuando funciona', () async {
      ai.nextPlan = const Success<ProposedPlan>(
        ProposedPlan(
          missions: <ProposedMission>[
            ProposedMission(title: 'Generada por la IA'),
          ],
          model: 'gemini-2.0-flash',
          promptVersion: 'goal_plan_v1',
        ),
      );

      final result = await GenerateGoalPlanUseCase(
        ai,
      ).call(goalTitle: 'Aprender inglés', categoryId: 'languages');

      expect(result.isSuccess, isTrue);
      final plan = result.valueOrNull!;
      expect(plan.isGenerated, isTrue);
      expect(plan.missions.single.title, 'Generada por la IA');
    });

    test('con la IA caída cae a la plantilla, NO falla', () async {
      // Es la regla de oro de la fase: un asistente que al fallar deja a
      // alguien mirando un error sin salida es peor que no tener asistente.
      ai.nextPlan = const Failed<ProposedPlan>(TimeoutFailure());

      final result = await GenerateGoalPlanUseCase(
        ai,
      ).call(goalTitle: 'Aprender inglés', categoryId: 'languages');

      expect(result.isSuccess, isTrue);
      final plan = result.valueOrNull!;
      expect(plan.source, PlanSource.template);
      expect(plan.isGenerated, isFalse);
      expect(plan.missions, isNotEmpty);
    });

    test('con la cuota agotada también cae a la plantilla', () async {
      ai.nextPlan = const Failed<ProposedPlan>(
        QuotaFailure(messageKey: 'failure.quota.ai'),
      );

      final result = await GenerateGoalPlanUseCase(
        ai,
      ).call(goalTitle: 'Correr 5k', categoryId: 'fitness');

      expect(result.valueOrNull?.source, PlanSource.template);
      expect(result.valueOrNull?.missions, isNotEmpty);
    });

    test('un título inválido NO llega a gastar una generación', () async {
      final result = await GenerateGoalPlanUseCase(
        ai,
      ).call(goalTitle: '   ', categoryId: 'languages');

      expect(result.failureOrNull?.messageKey, 'validation.title.required');
      expect(ai.calls, 0);
    });
  });

  group('templatePlanFor — la biblioteca de reserva', () {
    test('cada categoría con plantilla propia devuelve misiones', () {
      for (final id in <String>[
        'fitness',
        'languages',
        'reading',
        'finance',
        'mindfulness',
        'creativity',
      ]) {
        expect(hasTemplateFor(id), isTrue, reason: 'Falta plantilla de $id');
        expect(templatePlanFor(id).missions, isNotEmpty);
      }
    });

    test('una categoría sin plantilla usa la genérica, no queda vacía', () {
      // Una hoja en blanco es el peor resultado posible del asistente.
      expect(hasTemplateFor('categoria_inventada'), isFalse);
      expect(templatePlanFor('categoria_inventada').missions, isNotEmpty);
    });

    test('la plantilla respeta el presupuesto pedido', () {
      // Proponerle gastar a quien dijo "gratis" es tan inútil en una plantilla
      // como en una generación.
      final plan = templatePlanFor('fitness');
      expect(
        plan.missions.every((m) => m.budget == MissionBudget.free),
        isTrue,
      );
    });

    test('siempre viene marcada como plantilla, no como generada', () {
      // La pantalla lo usa para avisar que el plan es de reserva: hacerlo pasar
      // por generado sería mentir sobre lo que la persona está viendo.
      expect(templatePlanFor('fitness').source, PlanSource.template);
      expect(templatePlanFor('fitness').isGenerated, isFalse);
    });
  });

  group(
    'MaterializePlanUseCase — el asistente propone, la persona dispone',
    () {
      const plan = ProposedPlan(
        missions: <ProposedMission>[
          ProposedMission(title: 'Primera', difficulty: MissionDifficulty.easy),
          ProposedMission(title: 'Segunda', budget: MissionBudget.low),
        ],
        milestones: <String>['Primer hito'],
        model: 'gemini-2.0-flash',
        promptVersion: 'goal_plan_v1',
      );

      test('crea objetivo y misiones en una sola escritura', () async {
        final result = await MaterializePlanUseCase(goals).call(
          uid: 'u1',
          goalTitle: 'Aprender inglés',
          categoryId: 'languages',
          plan: plan,
        );

        expect(result.isSuccess, isTrue);
        expect(goals.createdGoal?.title, 'Aprender inglés');
        expect(goals.createdMissions, hasLength(2));
      });

      test('las misiones heredan el objetivo y quedan ordenadas', () async {
        await MaterializePlanUseCase(goals).call(
          uid: 'u1',
          goalTitle: 'Aprender inglés',
          categoryId: 'languages',
          plan: plan,
        );

        final missions = goals.createdMissions!;
        expect(missions.every((m) => m.goalTitle == 'Aprender inglés'), isTrue);
        expect(missions.every((m) => m.categoryId == 'languages'), isTrue);
        expect(missions.map((m) => m.order), <int>[0, 1]);
        expect(
          missions.every((m) => m.goalId == goals.createdGoal!.id),
          isTrue,
        );
      });

      test('queda registrado que el plan lo generó la IA', () async {
        // Permite correlacionar después qué objetivos se completan más, los
        // generados o los manuales.
        await MaterializePlanUseCase(goals).call(
          uid: 'u1',
          goalTitle: 'Aprender inglés',
          categoryId: 'languages',
          plan: plan,
        );

        expect(goals.createdGoal?.ai.generated, isTrue);
        expect(goals.createdGoal?.ai.model, 'gemini-2.0-flash');
        expect(goals.createdGoal?.ai.promptVersion, 'goal_plan_v1');
      });

      test('un plan de plantilla NO se marca como generado por IA', () async {
        await MaterializePlanUseCase(goals).call(
          uid: 'u1',
          goalTitle: 'Correr 5k',
          categoryId: 'fitness',
          plan: templatePlanFor('fitness'),
        );

        expect(goals.createdGoal?.ai.generated, isFalse);
        expect(goals.createdGoal?.ai.generatedAt, isNull);
      });

      test('los hitos se numeran en orden', () async {
        await MaterializePlanUseCase(goals).call(
          uid: 'u1',
          goalTitle: 'Aprender inglés',
          categoryId: 'languages',
          plan: plan,
        );

        expect(goals.createdGoal?.milestones.single.title, 'Primer hito');
        expect(goals.createdGoal?.milestones.single.order, 0);
      });

      test('un plan vacío se rechaza', () async {
        final result = await MaterializePlanUseCase(goals).call(
          uid: 'u1',
          goalTitle: 'Aprender inglés',
          categoryId: 'languages',
          plan: const ProposedPlan(missions: <ProposedMission>[]),
        );

        expect(result.failureOrNull?.messageKey, 'validation.plan.empty');
        expect(goals.createdGoal, isNull);
      });
    },
  );

  group('ProposedMission — editable antes de guardar', () {
    test('copyWith permite corregir lo que propuso el modelo', () {
      // La pantalla de revisión existe justamente para esto: el modelo propone
      // y la persona corrige antes de que exista nada en la base.
      const original = ProposedMission(title: 'Vago y genérico');
      final edited = original.copyWith(
        title: 'Concreto y verificable',
        estimatedMinutes: 25,
      );

      expect(edited.title, 'Concreto y verificable');
      expect(edited.estimatedMinutes, 25);
      expect(edited.difficulty, original.difficulty);
    });
  });
}
