import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/goals/application/goals_controller.dart';
import 'package:ascend_mobile/features/goals/presentation/widgets/goal_widgets.dart';
import 'package:ascend_mobile/features/integrations/presentation/widgets/book_picker.dart';
import 'package:ascend_mobile/features/missions/application/missions_controller.dart';
import 'package:ascend_mobile/features/missions/presentation/widgets/mission_widgets.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Alta de una misión dentro de un objetivo.
///
/// Necesita el objetivo completo y no solo su id: la misión guarda `goalTitle`
/// y `categoryId` desnormalizados para que la pantalla "Hoy" los muestre sin
/// pagar una lectura extra por misión.
class MissionFormScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const MissionFormScreen({required this.goalId, super.key});

  /// Objetivo al que pertenece la misión.
  final String goalId;

  @override
  ConsumerState<MissionFormScreen> createState() => _MissionFormScreenState();
}

class _MissionFormScreenState extends ConsumerState<MissionFormScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _minutes = TextEditingController();

  MissionDifficulty _difficulty = MissionDifficulty.medium;
  MissionBudget _budget = MissionBudget.free;
  DateTime? _dueDate;
  bool _requiresEvidence = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: '¿Para cuándo?',
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  /// Rellena el formulario con un libro del catálogo abierto.
  ///
  /// No guarda nada ni cierra la pantalla: deja el formulario cargado para que
  /// se pueda corregir el título, la duración o la exigencia antes de crear.
  /// La sugerencia asiste, no decide.
  Future<void> _pickBook() async {
    final book = await showBookPicker(context);
    if (book == null || !mounted) {
      return;
    }

    setState(() {
      _title.text = book.missionTitle;
      _difficulty = difficultyForBook(book);
      final minutes = book.estimatedReadingMinutes;
      if (minutes != null) {
        _minutes.text = '$minutes';
      }
    });
    ref.read(missionControllerProvider.notifier).clearError();
  }

  Future<void> _submit(Goal goal) async {
    FocusScope.of(context).unfocus();

    final missionId = await ref
        .read(missionControllerProvider.notifier)
        .create(
          goal: goal,
          title: _title.text,
          description: _description.text,
          difficulty: _difficulty,
          budget: _budget,
          estimatedMinutes: int.tryParse(_minutes.text.trim()),
          dueDate: _dueDate,
          requiresEvidence: _requiresEvidence,
        );

    if (missionId != null && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalAsync = ref.watch(goalDetailProvider(widget.goalId));
    final state = ref.watch(missionControllerProvider);
    final isSaving = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva misión')),
      body: AsyncStateBuilder<Result<Goal>>(
        value: goalAsync,
        onRetry: () => ref.invalidate(goalDetailProvider(widget.goalId)),
        data: (Result<Goal> result) => result.fold<Widget>(
          onFailure: (Failure f) => ErrorStateView(
            failure: f,
            onRetry: () => ref.invalidate(goalDetailProvider(widget.goalId)),
          ),
          onSuccess: (Goal goal) => ListView(
            padding: const EdgeInsets.all(AscendSpacing.lg),
            children: <Widget>[
              // Recordar a qué objetivo pertenece evita crear la misión en el
              // lugar equivocado cuando se llega desde "Hoy".
              Text(
                goal.title,
                style: context.texts.labelLarge?.copyWith(
                  color: context.ascend.textSecondary,
                ),
              ),
              const SizedBox(height: AscendSpacing.lg),
              if (failure != null) ...<Widget>[
                ErrorStateView(failure: failure, compact: true),
                const SizedBox(height: AscendSpacing.lg),
              ],
              // Solo en objetivos de lectura o idiomas: en el resto sería un
              // botón que nadie va a tocar, ensuciando el formulario.
              if (suggestsBooks(goal.categoryId)) ...<Widget>[
                OutlinedButton.icon(
                  onPressed: isSaving ? null : _pickBook,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Elegir un libro del catálogo'),
                ),
                const SizedBox(height: AscendSpacing.md),
              ],
              AscendTextField(
                controller: _title,
                label: '¿Qué vas a hacer?',
                hint: 'Ver un capítulo con subtítulos en inglés',
                prefixIcon: Icons.task_alt_rounded,
                maxLength: Validators.maxTitleLength,
                enabled: !isSaving,
                autofocus: true,
                onChanged: (_) =>
                    ref.read(missionControllerProvider.notifier).clearError(),
              ),
              AscendTextField(
                controller: _description,
                label: 'Detalle (opcional)',
                hint: '20-25 minutos, anotar 5 palabras nuevas',
                maxLength: kMaxMissionDescriptionLength,
                maxLines: 3,
                minLines: 2,
                textInputAction: TextInputAction.newline,
                enabled: !isSaving,
              ),
              _ChipGroup<MissionDifficulty>(
                label: '¿Qué tan exigente es?',
                values: MissionDifficulty.values,
                selected: _difficulty,
                labelOf: (d) => d.label,
                enabled: !isSaving,
                onSelected: (value) => setState(() => _difficulty = value),
              ),
              const SizedBox(height: AscendSpacing.lg),
              _ChipGroup<MissionBudget>(
                label: '¿Cuánto cuesta?',
                values: MissionBudget.values,
                selected: _budget,
                labelOf: (b) => b.label,
                enabled: !isSaving,
                onSelected: (value) => setState(() => _budget = value),
              ),
              const SizedBox(height: AscendSpacing.lg),
              AscendTextField(
                controller: _minutes,
                label: 'Duración estimada en minutos (opcional)',
                prefixIcon: Icons.schedule_rounded,
                keyboardType: TextInputType.number,
                enabled: !isSaving,
                helperText: 'Entre 1 y $kMaxEstimatedMinutes.',
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isSaving ? null : _pickDueDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _dueDate == null
                            ? 'Sin fecha'
                            : MaterialLocalizations.of(
                                context,
                              ).formatMediumDate(_dueDate!),
                      ),
                    ),
                  ),
                  if (_dueDate != null)
                    IconButton(
                      onPressed: isSaving
                          ? null
                          : () => setState(() => _dueDate = null),
                      icon: const Icon(Icons.clear_rounded),
                      tooltip: 'Quitar fecha',
                    ),
                ],
              ),
              // Sin fecha, la misión no aparece en "Hoy". Decirlo evita que
              // alguien la cree y crea que la app la perdió.
              if (_dueDate == null)
                Padding(
                  padding: const EdgeInsets.only(top: AscendSpacing.xs),
                  child: Text(
                    'Sin fecha no va a aparecer en la pantalla "Hoy".',
                    style: context.texts.bodySmall?.copyWith(
                      color: context.ascend.textSecondary,
                    ),
                  ),
                ),
              CheckboxListTile(
                value: _requiresEvidence,
                onChanged: isSaving
                    ? null
                    : (value) =>
                          setState(() => _requiresEvidence = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('Pedir una foto para completarla'),
                subtitle: Text(
                  'La captura de evidencias llega en la Fase 3.',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.ascend.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: AscendSpacing.xl),
              AscendButton(
                label: 'Crear misión',
                isLoading: isSaving,
                onPressed: isSaving ? null : () => _submit(goal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grupo de chips de selección única.
class _ChipGroup<T> extends StatelessWidget {
  const _ChipGroup({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    required this.enabled,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: context.texts.labelLarge),
      const SizedBox(height: AscendSpacing.sm),
      Wrap(
        spacing: AscendSpacing.sm,
        runSpacing: AscendSpacing.sm,
        children: <Widget>[
          for (final value in values)
            ChoiceChip(
              label: Text(labelOf(value)),
              selected: selected == value,
              onSelected: enabled ? (_) => onSelected(value) : null,
            ),
        ],
      ),
    ],
  );
}
