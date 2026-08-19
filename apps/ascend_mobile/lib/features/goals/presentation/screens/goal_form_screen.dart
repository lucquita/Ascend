import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/goals/application/goals_controller.dart';
import 'package:ascend_mobile/features/goals/presentation/widgets/goal_widgets.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Alta y edición de un objetivo.
///
/// Es la misma pantalla para los dos casos: los campos, las validaciones y el
/// límite de hitos son idénticos, y tener dos formularios garantiza que tarde o
/// temprano se separen y uno acepte algo que el otro rechaza.
class GoalFormScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla en modo alta.
  const GoalFormScreen({super.key}) : goalId = null;

  /// Crea la pantalla en modo edición.
  const GoalFormScreen.edit({required String this.goalId, super.key});

  /// Id del objetivo a editar, o `null` si es un alta.
  final String? goalId;

  /// `true` si está editando un objetivo existente.
  bool get isEditing => goalId != null;

  @override
  ConsumerState<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends ConsumerState<GoalFormScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _milestoneInput = TextEditingController();

  String? _categoryId;
  MissionDifficulty _difficulty = MissionDifficulty.medium;
  DateTime? _targetDate;
  List<Milestone> _milestones = const <Milestone>[];

  /// Objetivo original en modo edición. Se usa para conservar los campos que el
  /// formulario no toca (progreso, aura, fechas de creación).
  Goal? _original;
  bool _hydrated = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _milestoneInput.dispose();
    super.dispose();
  }

  /// Carga los datos del objetivo una sola vez.
  ///
  /// El stream sigue emitiendo mientras se edita; volver a copiar sus valores
  /// en cada emisión pisaría lo que la persona está escribiendo.
  void _hydrate(Goal goal) {
    if (_hydrated) {
      return;
    }
    _hydrated = true;
    _original = goal;
    _title.text = goal.title;
    _description.text = goal.description ?? '';
    _categoryId = goal.categoryId;
    _difficulty = goal.difficulty;
    _targetDate = goal.targetDate;
    _milestones = goal.milestones;
  }

  void _addMilestone() {
    final text = _milestoneInput.text.trim();
    if (text.isEmpty || _milestones.length >= kMaxMilestones) {
      return;
    }
    setState(() {
      _milestones = <Milestone>[
        ..._milestones,
        Milestone(
          id: IdGenerator.generate(),
          title: text,
          order: _milestones.length,
        ),
      ];
      _milestoneInput.clear();
    });
  }

  void _removeMilestone(String id) {
    setState(() {
      final remaining = _milestones.where((m) => m.id != id).toList();
      // Se reindexa el orden: dejar huecos haría que un hito agregado después
      // apareciera en medio de la lista.
      _milestones = <Milestone>[
        for (var i = 0; i < remaining.length; i++)
          Milestone(
            id: remaining[i].id,
            title: remaining[i].title,
            order: i,
            done: remaining[i].done,
            completedAt: remaining[i].completedAt,
          ),
      ];
    });
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: '¿Para cuándo querés lograrlo?',
    );
    if (picked != null) {
      setState(() => _targetDate = picked);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final controller = ref.read(goalControllerProvider.notifier);

    if (widget.isEditing) {
      final original = _original;
      if (original == null) {
        return;
      }
      // Se construye la entidad en lugar de usar `copyWith`: ese método
      // resuelve `targetDate ?? this.targetDate`, así que quitar la fecha
      // objetivo con el botón de limpiar no tendría ningún efecto.
      final saved = await controller.update(
        Goal(
          id: original.id,
          ownerId: original.ownerId,
          title: _title.text,
          categoryId: _categoryId ?? original.categoryId,
          createdAt: original.createdAt,
          description: _description.text,
          status: original.status,
          difficulty: _difficulty,
          // Progreso y aura se conservan tal cual vinieron: son del servidor y
          // el DTO ni siquiera los manda.
          progress: original.progress,
          auraEarned: original.auraEarned,
          milestones: _milestones,
          ai: original.ai,
          colorHex: original.colorHex,
          icon: original.icon,
          startDate: original.startDate,
          targetDate: _targetDate,
          completedAt: original.completedAt,
          updatedAt: original.updatedAt,
        ),
      );
      if (saved && mounted) {
        context.pop();
      }
      return;
    }

    final goalId = await controller.create(
      title: _title.text,
      categoryId: _categoryId ?? '',
      description: _description.text,
      difficulty: _difficulty,
      milestones: _milestones,
      targetDate: _targetDate,
    );
    if (goalId != null && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(goalControllerProvider);
    final isSaving = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;

    // En edición hay que esperar a que llegue el objetivo antes de pintar el
    // formulario: rellenarlo después de que la persona empezó a escribir sería
    // pisarle el texto.
    if (widget.isEditing && !_hydrated) {
      final goal = ref.watch(goalDetailProvider(widget.goalId!));
      final loaded = goal.value?.valueOrNull;
      if (loaded == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Editar objetivo')),
          body: goal.value?.failureOrNull != null
              ? ErrorStateView(
                  failure: goal.value!.failureOrNull!,
                  onRetry: () =>
                      ref.invalidate(goalDetailProvider(widget.goalId!)),
                )
              : const AscendSkeletonList(),
        );
      }
      _hydrate(loaded);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar objetivo' : 'Nuevo objetivo'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AscendSpacing.lg),
        children: <Widget>[
          if (failure != null) ...<Widget>[
            ErrorStateView(failure: failure, compact: true),
            const SizedBox(height: AscendSpacing.lg),
          ],
          AscendTextField(
            controller: _title,
            label: '¿Qué querés lograr?',
            hint: 'Aprender inglés conversacional',
            prefixIcon: Icons.flag_outlined,
            maxLength: Validators.maxTitleLength,
            enabled: !isSaving,
            autofocus: !widget.isEditing,
            onChanged: (_) =>
                ref.read(goalControllerProvider.notifier).clearError(),
          ),
          AscendTextField(
            controller: _description,
            label: 'Detalle (opcional)',
            hint: 'Poder mantener una charla de 20 minutos',
            maxLength: kMaxGoalDescriptionLength,
            maxLines: 4,
            minLines: 2,
            textInputAction: TextInputAction.newline,
            enabled: !isSaving,
          ),
          _CategoryPicker(
            selected: _categoryId,
            enabled: !isSaving,
            onSelected: (id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: AscendSpacing.lg),
          _DifficultyPicker(
            selected: _difficulty,
            enabled: !isSaving,
            onSelected: (value) => setState(() => _difficulty = value),
          ),
          const SizedBox(height: AscendSpacing.lg),
          _TargetDateField(
            value: _targetDate,
            enabled: !isSaving,
            onPick: _pickTargetDate,
            onClear: () => setState(() => _targetDate = null),
          ),
          const SizedBox(height: AscendSpacing.xl),
          _MilestonesEditor(
            milestones: _milestones,
            controller: _milestoneInput,
            enabled: !isSaving,
            onAdd: _addMilestone,
            onRemove: _removeMilestone,
          ),
          const SizedBox(height: AscendSpacing.xl),
          AscendButton(
            label: widget.isEditing ? 'Guardar cambios' : 'Crear objetivo',
            isLoading: isSaving,
            onPressed: isSaving ? null : _submit,
          ),
        ],
      ),
    );
  }
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
          loading: const _ChipsSkeleton(),
          onRetry: () => ref.invalidate(categoriesProvider),
          data: (Result<List<Category>> result) => result.fold<Widget>(
            onSuccess: (List<Category> items) {
              if (items.isEmpty) {
                // El catálogo se siembra desde el panel. Sin categorías no se
                // puede crear un objetivo, y hay que decirlo con claridad en
                // vez de mostrar una fila vacía.
                return Text(
                  'El catálogo de categorías está vacío. Avisale al equipo.',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.error,
                  ),
                );
              }
              return Wrap(
                spacing: AscendSpacing.sm,
                runSpacing: AscendSpacing.sm,
                children: <Widget>[
                  for (final category in items)
                    ChoiceChip(
                      label: Text(category.nameFor('es')),
                      selected: selected == category.id,
                      onSelected: enabled
                          ? (_) => onSelected(category.id)
                          : null,
                    ),
                ],
              );
            },
            onFailure: (Failure failure) =>
                ErrorStateView(failure: failure, compact: true),
          ),
        ),
      ],
    );
  }
}

class _ChipsSkeleton extends StatelessWidget {
  const _ChipsSkeleton();

  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: AscendSpacing.sm,
    runSpacing: AscendSpacing.sm,
    children: <Widget>[
      AscendSkeleton(width: 90, height: 32),
      AscendSkeleton(width: 110, height: 32),
      AscendSkeleton(width: 80, height: 32),
    ],
  );
}

/// Selector de dificultad percibida.
class _DifficultyPicker extends StatelessWidget {
  const _DifficultyPicker({
    required this.selected,
    required this.onSelected,
    required this.enabled,
  });

  final MissionDifficulty selected;
  final ValueChanged<MissionDifficulty> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('¿Qué tan exigente es?', style: context.texts.labelLarge),
      const SizedBox(height: AscendSpacing.sm),
      Wrap(
        spacing: AscendSpacing.sm,
        children: <Widget>[
          for (final difficulty in MissionDifficulty.values)
            ChoiceChip(
              label: Text(difficulty.label),
              selected: selected == difficulty,
              onSelected: enabled ? (_) => onSelected(difficulty) : null,
            ),
        ],
      ),
    ],
  );
}

/// Campo de fecha objetivo.
class _TargetDateField extends StatelessWidget {
  const _TargetDateField({
    required this.value,
    required this.onPick,
    required this.onClear,
    required this.enabled,
  });

  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('Fecha objetivo (opcional)', style: context.texts.labelLarge),
      const SizedBox(height: AscendSpacing.sm),
      Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: enabled ? onPick : null,
              icon: const Icon(Icons.event_outlined),
              // `MaterialLocalizations` formatea según el idioma del
              // dispositivo y ya viene con Flutter: no hace falta sumar `intl`
              // a la app móvil solo para pintar una fecha.
              label: Text(
                value == null
                    ? 'Elegir fecha'
                    : MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(value!),
              ),
            ),
          ),
          if (value != null)
            IconButton(
              onPressed: enabled ? onClear : null,
              icon: const Icon(Icons.clear_rounded),
              tooltip: 'Quitar fecha',
            ),
        ],
      ),
    ],
  );
}

/// Editor de hitos embebidos.
class _MilestonesEditor extends StatelessWidget {
  const _MilestonesEditor({
    required this.milestones,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
    required this.enabled,
  });

  final List<Milestone> milestones;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final atLimit = milestones.length >= kMaxMilestones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Hitos (opcional)', style: context.texts.labelLarge),
        const SizedBox(height: AscendSpacing.xs),
        Text(
          'Puntos intermedios que marcan que vas bien. Hasta $kMaxMilestones.',
          style: context.texts.bodySmall?.copyWith(
            color: context.ascend.textSecondary,
          ),
        ),
        const SizedBox(height: AscendSpacing.md),
        for (final milestone in milestones)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.flag_outlined, size: 20),
            title: Text(milestone.title, style: context.texts.bodyMedium),
            trailing: IconButton(
              onPressed: enabled ? () => onRemove(milestone.id) : null,
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Quitar hito',
            ),
          ),
        if (!atLimit)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: AscendTextField(
                  controller: controller,
                  label: 'Agregar un hito',
                  textInputAction: TextInputAction.done,
                  enabled: enabled,
                  maxLength: Validators.maxTitleLength,
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: AscendSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: AscendSpacing.sm),
                child: IconButton.filledTonal(
                  onPressed: enabled ? onAdd : null,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Agregar hito',
                ),
              ),
            ],
          ),
      ],
    );
  }
}
