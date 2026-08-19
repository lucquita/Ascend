/// Generación de planes con IA y su plan de reserva.
///
/// La regla de oro de esta fase: **con la IA caída, la persona termina su
/// objetivo igual**. Un asistente que, cuando falla, deja a alguien mirando un
/// error sin salida es peor que no tener asistente. Por eso las plantillas por
/// categoría no son un extra: son la mitad del diseño.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/goal.dart';
import 'package:ascend_domain/src/entities/mission.dart';
import 'package:ascend_domain/src/enums/enums.dart';
import 'package:ascend_domain/src/repositories/repositories.dart';
import 'package:meta/meta.dart';

/// Misión propuesta, todavía sin guardar.
///
/// No es una [Mission]: no tiene id, ni dueño, ni objetivo. Es una **sugerencia**
/// que la persona puede editar o descartar antes de que exista algo en la base.
@immutable
class ProposedMission {
  /// Crea una propuesta.
  const ProposedMission({
    required this.title,
    this.description,
    this.difficulty = MissionDifficulty.medium,
    this.budget = MissionBudget.free,
    this.estimatedMinutes,
  });

  /// Qué hacer.
  final String title;

  /// Detalle.
  final String? description;

  /// Exigencia.
  final MissionDifficulty difficulty;

  /// Costo estimado.
  final MissionBudget budget;

  /// Duración estimada.
  final int? estimatedMinutes;

  /// Copia con cambios, para la pantalla de revisión.
  ProposedMission copyWith({
    String? title,
    String? description,
    MissionDifficulty? difficulty,
    MissionBudget? budget,
    int? estimatedMinutes,
  }) => ProposedMission(
    title: title ?? this.title,
    description: description ?? this.description,
    difficulty: difficulty ?? this.difficulty,
    budget: budget ?? this.budget,
    estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
  );
}

/// Plan propuesto para un objetivo.
@immutable
class ProposedPlan {
  /// Crea el plan.
  const ProposedPlan({
    required this.missions,
    this.milestones = const <String>[],
    this.source = PlanSource.ai,
    this.model,
    this.promptVersion,
  });

  /// Misiones sugeridas.
  final List<ProposedMission> missions;

  /// Hitos sugeridos.
  final List<String> milestones;

  /// De dónde salió el plan.
  final PlanSource source;

  /// Modelo que lo generó, si vino de la IA.
  final String? model;

  /// Versión del prompt, para poder auditar la calidad.
  final String? promptVersion;

  /// `true` si el plan lo armó la IA.
  bool get isGenerated => source == PlanSource.ai;
}

/// Origen de un plan propuesto.
enum PlanSource {
  /// Lo generó Gemini.
  ai,

  /// Sale de la biblioteca de plantillas por categoría.
  template,
}

/// Genera un plan, con caída a plantillas.
class GenerateGoalPlanUseCase {
  /// Crea el caso de uso.
  const GenerateGoalPlanUseCase(this._ai);

  final AiRepository _ai;

  /// Pide un plan a la IA y, si falla, devuelve la plantilla de la categoría.
  ///
  /// **Nunca devuelve un fallo por culpa de la IA.** Solo falla si el pedido en
  /// sí es inválido. Cualquier problema del proveedor —cuota, timeout, respuesta
  /// malformada— se resuelve con la plantilla: la persona sigue adelante y la
  /// pantalla le avisa que el plan es de reserva.
  Future<Result<ProposedPlan>> call({
    required String goalTitle,
    required String categoryId,
    String? description,
    int horizonDays = 90,
    int missionCount = 6,
    MissionBudget budget = MissionBudget.free,
  }) async {
    final validTitle = Validators.requiredText(
      goalTitle,
      field: 'title',
      maxLength: Validators.maxTitleLength,
    );
    if (validTitle case Failed<String>(:final failure)) {
      return Failed<ProposedPlan>(failure);
    }

    final result = await _ai.generateGoalPlan(
      goalTitle: validTitle.valueOrNull!,
      categoryId: categoryId,
      description: description,
      horizonDays: horizonDays,
      missionCount: missionCount,
      budget: budget,
    );

    return result.fold(
      onSuccess: Success<ProposedPlan>.new,
      onFailure: (_) =>
          Success<ProposedPlan>(templatePlanFor(categoryId, budget: budget)),
    );
  }
}

/// Convierte un plan revisado en el objetivo y las misiones a guardar.
///
/// Se aplica **después** de que la persona confirmó: el asistente propone, la
/// persona dispone. Un plan que se guarda solo es un plan que nadie leyó.
class MaterializePlanUseCase {
  /// Crea el caso de uso.
  const MaterializePlanUseCase(this._goals);

  final GoalRepository _goals;

  /// Crea el objetivo con sus misiones en una única escritura atómica.
  Future<Result<Goal>> call({
    required String uid,
    required String goalTitle,
    required String categoryId,
    required ProposedPlan plan,
    String? description,
    DateTime? targetDate,
    DateTime? now,
  }) async {
    if (plan.missions.isEmpty) {
      return const Failed<Goal>(
        ValidationFailure(
          messageKey: 'validation.plan.empty',
          field: 'missions',
        ),
      );
    }

    final createdAt = (now ?? DateTime.now()).toUtc();
    final goalId = IdGenerator.generate();

    final goal = Goal(
      id: goalId,
      ownerId: uid,
      title: goalTitle,
      categoryId: categoryId,
      createdAt: createdAt,
      description: description,
      targetDate: targetDate,
      milestones: <Milestone>[
        for (var i = 0; i < plan.milestones.length; i++)
          Milestone(
            id: IdGenerator.generate(),
            title: plan.milestones[i],
            order: i,
          ),
      ],
      // Queda registrado que el plan lo generó la IA: permite correlacionar
      // después qué objetivos se completan más, los generados o los manuales.
      ai: AiMetadata(
        generated: plan.isGenerated,
        model: plan.model,
        promptVersion: plan.promptVersion,
        generatedAt: plan.isGenerated ? createdAt : null,
      ),
    );

    final missions = <Mission>[
      for (var i = 0; i < plan.missions.length; i++)
        Mission(
          id: IdGenerator.generate(),
          ownerId: uid,
          goalId: goalId,
          title: plan.missions[i].title,
          createdAt: createdAt,
          goalTitle: goalTitle,
          categoryId: categoryId,
          description: plan.missions[i].description,
          difficulty: plan.missions[i].difficulty,
          budget: plan.missions[i].budget,
          estimatedMinutes: plan.missions[i].estimatedMinutes,
          order: i,
          ai: AiMetadata(generated: plan.isGenerated),
        ),
    ];

    return _goals.createGoalWithMissions(goal: goal, missions: missions);
  }
}

/// Biblioteca de plantillas por categoría.
///
/// Es el plan de reserva cuando la IA no está disponible, y también el punto de
/// partida para quien prefiere no usarla. Son deliberadamente genéricas y
/// cortas: una plantilla que la persona edita es mejor que una hoja en blanco.
ProposedPlan templatePlanFor(
  String categoryId, {
  MissionBudget budget = MissionBudget.free,
}) {
  final missions = _templates[categoryId] ?? _genericTemplate;
  return ProposedPlan(
    // Se respeta el presupuesto pedido igual que con la IA: una plantilla que
    // propone gastar a quien dijo "gratis" es tan inútil como una generación
    // que lo hace.
    missions: missions
        .where((m) => m.budget.index <= budget.index)
        .toList(growable: false),
    milestones: _milestones[categoryId] ?? _genericMilestones,
    source: PlanSource.template,
  );
}

/// `true` si hay una plantilla propia para la categoría.
bool hasTemplateFor(String categoryId) => _templates.containsKey(categoryId);

const List<ProposedMission> _genericTemplate = <ProposedMission>[
  ProposedMission(
    title: 'Escribir por qué querés lograrlo',
    description: 'Cinco líneas. Sirve para volver a leerlas cuando cueste.',
    difficulty: MissionDifficulty.easy,
    estimatedMinutes: 10,
  ),
  ProposedMission(
    title: 'Dedicarle 20 minutos hoy',
    difficulty: MissionDifficulty.easy,
    estimatedMinutes: 20,
  ),
  ProposedMission(
    title: 'Elegir un día fijo de la semana para avanzar',
    difficulty: MissionDifficulty.easy,
    estimatedMinutes: 10,
  ),
  ProposedMission(
    title: 'Dedicarle una hora sin interrupciones',
    estimatedMinutes: 60,
  ),
];

const List<String> _genericMilestones = <String>[
  'Primera semana constante',
  'Primer mes cumplido',
];

const Map<String, List<ProposedMission>> _templates =
    <String, List<ProposedMission>>{
      'fitness': <ProposedMission>[
        ProposedMission(
          title: 'Salir a caminar 20 minutos',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 20,
        ),
        ProposedMission(
          title: 'Hacer una rutina de 15 minutos en casa',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 15,
        ),
        ProposedMission(title: 'Trotar 3 kilómetros', estimatedMinutes: 30),
        ProposedMission(
          title: 'Entrenar dos días seguidos',
          difficulty: MissionDifficulty.hard,
          estimatedMinutes: 60,
        ),
      ],
      'languages': <ProposedMission>[
        ProposedMission(
          title: 'Ver un capítulo con subtítulos en el idioma',
          description: 'Anotá cinco palabras nuevas.',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 30,
        ),
        ProposedMission(
          title: 'Estudiar 20 palabras nuevas',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 20,
        ),
        ProposedMission(
          title: 'Escribir un texto de 10 líneas',
          estimatedMinutes: 30,
        ),
        ProposedMission(
          title: 'Tener una conversación de 15 minutos',
          difficulty: MissionDifficulty.hard,
          estimatedMinutes: 20,
        ),
      ],
      'reading': <ProposedMission>[
        ProposedMission(
          title: 'Leer 20 páginas',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 30,
        ),
        ProposedMission(
          title: 'Elegir el próximo libro',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 15,
        ),
        ProposedMission(
          title: 'Terminar un libro entero',
          difficulty: MissionDifficulty.hard,
          estimatedMinutes: 120,
        ),
      ],
      'finance': <ProposedMission>[
        ProposedMission(
          title: 'Anotar todos los gastos de una semana',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 20,
        ),
        ProposedMission(
          title: 'Armar un presupuesto mensual',
          estimatedMinutes: 45,
        ),
        ProposedMission(
          title: 'Cancelar una suscripción que no usás',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 15,
        ),
      ],
      'mindfulness': <ProposedMission>[
        ProposedMission(
          title: 'Meditar 10 minutos',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 10,
        ),
        ProposedMission(
          title: 'Acostarte una hora antes',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 60,
        ),
        ProposedMission(
          title: 'Pasar una tarde sin pantallas',
          difficulty: MissionDifficulty.hard,
          estimatedMinutes: 180,
        ),
      ],
      'creativity': <ProposedMission>[
        ProposedMission(
          title: 'Dedicar 30 minutos a crear algo, sin juzgarlo',
          difficulty: MissionDifficulty.easy,
          estimatedMinutes: 30,
        ),
        ProposedMission(
          title: 'Terminar una pieza aunque no te convenza',
          estimatedMinutes: 60,
        ),
        ProposedMission(
          title: 'Mostrarle tu trabajo a alguien',
          difficulty: MissionDifficulty.hard,
          estimatedMinutes: 20,
        ),
      ],
    };

const Map<String, List<String>> _milestones = <String, List<String>>{
  'fitness': <String>['Primera semana entrenando', 'Un mes sin faltar'],
  'languages': <String>['500 palabras de vocabulario', 'Primera conversación'],
  'reading': <String>['Primer libro terminado', 'Tres libros en el año'],
  'finance': <String>['Un mes de gastos registrados', 'Primer ahorro guardado'],
  'mindfulness': <String>['Siete días seguidos', 'Rutina de sueño estable'],
  'creativity': <String>[
    'Primera pieza terminada',
    'Primera vez que la mostrás',
  ],
};
