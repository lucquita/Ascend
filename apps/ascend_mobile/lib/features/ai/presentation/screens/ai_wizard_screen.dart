import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/features/goals/presentation/widgets/goal_widgets.dart';
import 'package:ascend_mobile/features/missions/presentation/widgets/mission_widgets.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Asistente que convierte un objetivo general en un plan concreto.
///
/// Dos pasos, y el segundo **no se puede saltear**: la persona revisa y edita
/// antes de que se guarde nada. Un plan generado que se escribe solo es un plan
/// que nadie leyó, y termina siendo seis misiones que no se van a hacer.
///
/// Si la IA no responde, el paso de revisión llega igual con una plantilla de la
/// categoría y un aviso claro. **Nunca se llega a una pantalla sin salida.**
class AiWizardScreen extends ConsumerStatefulWidget {
  /// Crea el asistente.
  const AiWizardScreen({super.key});

  @override
  ConsumerState<AiWizardScreen> createState() => _AiWizardScreenState();
}

class _AiWizardScreenState extends ConsumerState<AiWizardScreen> {
  final TextEditingController _title = TextEditingController();

  String? _categoryId;
  MissionBudget _budget = MissionBudget.free;
  ProposedPlan? _plan;
  bool _busy = false;
  Failure? _failure;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failure = null;
    });

    final result = await ref
        .read(generateGoalPlanUseCaseProvider)
        .call(
          goalTitle: _title.text,
          categoryId: _categoryId ?? '',
          budget: _budget,
        );

    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      result.fold(
        onSuccess: (plan) => _plan = plan,
        onFailure: (failure) => _failure = failure,
      );
    });
  }

  Future<void> _confirm() async {
    final plan = _plan;
    final uid = ref.read(currentUserProvider)?.uid;
    if (plan == null || uid == null) {
      return;
    }

    setState(() => _busy = true);
    final result = await ref
        .read(materializePlanUseCaseProvider)
        .call(
          uid: uid,
          goalTitle: _title.text.trim(),
          categoryId: _categoryId ?? '',
          plan: plan,
        );

    if (!mounted) {
      return;
    }

    result.fold(
      onSuccess: (_) => context.pop(),
      onFailure: (failure) => setState(() {
        _busy = false;
        _failure = failure;
      }),
    );
  }

  void _removeMission(int index) {
    final plan = _plan;
    if (plan == null) {
      return;
    }
    setState(() {
      _plan = ProposedPlan(
        missions: <ProposedMission>[...plan.missions]..removeAt(index),
        milestones: plan.milestones,
        source: plan.source,
        model: plan.model,
        promptVersion: plan.promptVersion,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final canGenerate =
        _title.text.trim().isNotEmpty && _categoryId != null && !_busy;

    return Scaffold(
      appBar: AppBar(
        title: Text(_plan == null ? 'Armar con IA' : 'Revisá el plan'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AscendSpacing.lg),
        children: <Widget>[
          if (_failure != null) ...<Widget>[
            ErrorStateView(failure: _failure!, compact: true),
            const SizedBox(height: AscendSpacing.lg),
          ],
          if (_plan == null)
            ..._buildInputStep(canGenerate)
          else
            ..._buildReviewStep(_plan!),
        ],
      ),
    );
  }

  List<Widget> _buildInputStep(bool canGenerate) => <Widget>[
    Text(
      'Contanos qué querés lograr y armamos un plan de misiones concretas.',
      style: context.texts.bodyMedium,
    ),
    const SizedBox(height: AscendSpacing.xl),
    AscendTextField(
      controller: _title,
      label: '¿Qué querés lograr?',
      hint: 'Aprender inglés conversacional',
      prefixIcon: Icons.auto_awesome_rounded,
      maxLength: Validators.maxTitleLength,
      enabled: !_busy,
      autofocus: true,
      onChanged: (_) => setState(() {}),
    ),
    _CategoryPicker(
      selected: _categoryId,
      enabled: !_busy,
      onSelected: (id) => setState(() => _categoryId = id),
    ),
    const SizedBox(height: AscendSpacing.lg),
    Text('¿Cuánto podés gastar?', style: context.texts.labelLarge),
    const SizedBox(height: AscendSpacing.sm),
    Wrap(
      spacing: AscendSpacing.sm,
      children: <Widget>[
        for (final budget in MissionBudget.values)
          ChoiceChip(
            label: Text(budget.label),
            selected: _budget == budget,
            onSelected: _busy ? null : (_) => setState(() => _budget = budget),
          ),
      ],
    ),
    const SizedBox(height: AscendSpacing.xxl),
    AscendButton(
      label: 'Generar plan',
      icon: Icons.auto_awesome_rounded,
      isLoading: _busy,
      onPressed: canGenerate ? _generate : null,
    ),
  ];

  List<Widget> _buildReviewStep(ProposedPlan plan) => <Widget>[
    // Decir de dónde salió el plan no es un detalle: si la IA falló, la persona
    // tiene que saber que está mirando una plantilla y no una propuesta hecha
    // para su objetivo.
    if (!plan.isGenerated)
      Container(
        padding: const EdgeInsets.all(AscendSpacing.md),
        margin: const EdgeInsets.only(bottom: AscendSpacing.lg),
        decoration: BoxDecoration(
          color: context.ascend.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AscendRadius.md),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline_rounded, color: context.ascend.warning),
            const SizedBox(width: AscendSpacing.md),
            Expanded(
              child: Text(
                'La generación con IA no está disponible ahora. Este es un plan '
                'de arranque para tu categoría: editalo a gusto.',
                style: context.texts.bodySmall,
              ),
            ),
          ],
        ),
      ),
    Text(
      'Estas son las misiones propuestas. Sacá las que no te sirvan antes de '
      'guardar.',
      style: context.texts.bodyMedium,
    ),
    const SizedBox(height: AscendSpacing.lg),
    for (var i = 0; i < plan.missions.length; i++)
      _ProposedTile(
        mission: plan.missions[i],
        enabled: !_busy,
        onRemove: () => _removeMission(i),
      ),
    if (plan.milestones.isNotEmpty) ...<Widget>[
      const SizedBox(height: AscendSpacing.lg),
      Text('Hitos', style: context.texts.titleMedium),
      const SizedBox(height: AscendSpacing.sm),
      for (final milestone in plan.milestones)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.flag_outlined, size: 20),
          title: Text(milestone, style: context.texts.bodyMedium),
        ),
    ],
    const SizedBox(height: AscendSpacing.xxl),
    AscendButton(
      label: 'Crear objetivo con ${plan.missions.length} misiones',
      isLoading: _busy,
      onPressed: _busy || plan.missions.isEmpty ? null : _confirm,
    ),
    const SizedBox(height: AscendSpacing.sm),
    AscendButton.secondary(
      label: 'Empezar de nuevo',
      onPressed: _busy ? null : () => setState(() => _plan = null),
    ),
  ];
}

/// Fila de una misión propuesta, con la opción de descartarla.
class _ProposedTile extends StatelessWidget {
  const _ProposedTile({
    required this.mission,
    required this.onRemove,
    required this.enabled,
  });

  final ProposedMission mission;
  final VoidCallback onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AscendSpacing.sm),
    child: Container(
      padding: const EdgeInsets.all(AscendSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AscendRadius.cardRadius,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(mission.title, style: context.texts.bodyLarge),
                if (mission.description != null) ...<Widget>[
                  const SizedBox(height: AscendSpacing.xxs),
                  Text(
                    mission.description!,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.ascend.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AscendSpacing.sm),
                Wrap(
                  spacing: AscendSpacing.md,
                  children: <Widget>[
                    Text(
                      mission.difficulty.label,
                      style: context.texts.labelSmall?.copyWith(
                        color: context.ascend.textSecondary,
                      ),
                    ),
                    if (!mission.budget.isFree)
                      Text(
                        mission.budget.label,
                        style: context.texts.labelSmall?.copyWith(
                          color: context.ascend.textSecondary,
                        ),
                      ),
                    if (mission.estimatedMinutes != null)
                      Text(
                        '${mission.estimatedMinutes} min',
                        style: context.texts.labelSmall?.copyWith(
                          color: context.ascend.textSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Descartar',
          ),
        ],
      ),
    ),
  );
}

/// Selector de categoría alimentado por el catálogo en vivo.
class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({
    required this.selected,
    required this.onSelected,
    required this.enabled,
  });

  final String? selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Categoría', style: context.texts.labelLarge),
        const SizedBox(height: AscendSpacing.sm),
        AsyncStateBuilder<Result<List<Category>>>(
          value: categories,
          loading: const AscendSkeleton(height: 32),
          data: (Result<List<Category>> result) => result.fold<Widget>(
            onSuccess: (List<Category> items) => Wrap(
              spacing: AscendSpacing.sm,
              runSpacing: AscendSpacing.sm,
              children: <Widget>[
                for (final category in items)
                  ChoiceChip(
                    label: Text(category.nameFor('es')),
                    selected: selected == category.id,
                    onSelected: enabled ? (_) => onSelected(category.id) : null,
                  ),
              ],
            ),
            onFailure: (Failure failure) =>
                ErrorStateView(failure: failure, compact: true),
          ),
        ),
      ],
    );
  }
}
