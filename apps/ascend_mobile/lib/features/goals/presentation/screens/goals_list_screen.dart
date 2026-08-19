import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/goals/application/goals_controller.dart';
import 'package:ascend_mobile/features/goals/presentation/widgets/goal_widgets.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Lista de objetivos de la persona.
///
/// Consume el stream de Firestore: crear, editar o borrar desde cualquier
/// pantalla —o desde otro dispositivo— se refleja acá solo, sin recargar a mano
/// ni devolver datos por la navegación.
class GoalsListScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const GoalsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final filter = ref.watch(goalsFilterProvider);
    final categoryNames = ref.watch(_categoryNamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Objetivos'),
        actions: <Widget>[
          // El asistente es un camino alternativo al alta manual, no un
          // reemplazo: quien prefiere escribir su plan sigue usando el FAB.
          IconButton(
            onPressed: () => context.push(Routes.goalGenerating),
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: 'Armar con IA',
          ),
          if (filter.isActive)
            IconButton(
              onPressed: () => ref.read(goalsFilterProvider.notifier).clear(),
              icon: const Icon(Icons.filter_alt_off_rounded),
              tooltip: 'Quitar filtros',
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.goalNew),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo objetivo'),
      ),
      body: Column(
        children: <Widget>[
          _StatusFilterBar(selected: filter.status),
          Expanded(
            child: AsyncStateBuilder<Result<List<Goal>>>(
              value: goals,
              onRetry: () => ref.invalidate(goalsProvider),
              // El vacío se detecta a través del `Result`: sin esto el
              // constructor vería un `Result` —que no es una colección— y
              // nunca mostraría el estado vacío.
              isEmpty: (result) => result.valueOrNull?.isEmpty ?? false,
              emptyState: EmptyStateConfig(
                icon: Icons.flag_outlined,
                title: filter.isActive
                    ? 'Nada con esos filtros'
                    : 'Todavía no tenés objetivos',
                message: filter.isActive
                    ? 'Probá quitando algún filtro para ver el resto.'
                    : 'Un objetivo es lo que querés lograr. Después lo '
                          'partimos en misiones concretas.',
                actionLabel: filter.isActive
                    ? 'Quitar filtros'
                    : 'Crear mi primer objetivo',
                onAction: filter.isActive
                    ? () => ref.read(goalsFilterProvider.notifier).clear()
                    : () => context.push(Routes.goalNew),
              ),
              data: (Result<List<Goal>> result) => result.fold<Widget>(
                onSuccess: (List<Goal> items) => ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AscendSpacing.lg,
                    AscendSpacing.sm,
                    AscendSpacing.lg,
                    // Aire extra abajo para que el FAB no tape la última
                    // tarjeta.
                    AscendSpacing.huge + AscendSpacing.xl,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final goal = items[index];
                    return GoalCard(
                      goal: goal,
                      categoryName: categoryNames[goal.categoryId],
                      onTap: () => context.push(Routes.goalDetail(goal.id)),
                    );
                  },
                ),
                // El fallo que viaja dentro del stream se pinta con la misma
                // vista de error que el resto de la app.
                onFailure: (Failure failure) => ErrorStateView(
                  failure: failure,
                  onRetry: () => ref.invalidate(goalsProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nombres de categoría por id, en el idioma de la app.
///
/// Se deriva del catálogo en vivo para que la lista pueda pintar el nombre sin
/// una lectura por objetivo. Si el catálogo todavía no cargó, devuelve un mapa
/// vacío y las tarjetas simplemente omiten el chip.
final Provider<Map<String, String>> _categoryNamesProvider =
    Provider<Map<String, String>>((ref) {
      final categories = ref.watch(categoriesProvider).value?.valueOrNull;
      if (categories == null) {
        return const <String, String>{};
      }
      return <String, String>{
        for (final category in categories) category.id: category.nameFor('es'),
      };
    }, name: 'categoryNames');

/// Barra de filtros por estado.
class _StatusFilterBar extends ConsumerWidget {
  const _StatusFilterBar({required this.selected});

  final GoalStatus? selected;

  /// Estados que se ofrecen como filtro.
  ///
  /// `draft` queda fuera a propósito: hasta la Fase 6 no hay forma de crear un
  /// borrador, así que sería un filtro que nunca devuelve nada.
  static const List<GoalStatus> _filterable = <GoalStatus>[
    GoalStatus.active,
    GoalStatus.paused,
    GoalStatus.completed,
    GoalStatus.archived,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AscendSpacing.lg),
      children: <Widget>[
        for (final status in _filterable)
          Padding(
            padding: const EdgeInsets.only(right: AscendSpacing.sm),
            child: FilterChip(
              label: Text(status.label),
              selected: selected == status,
              // Tocar el filtro ya activo lo quita: es el gesto que la gente
              // espera y evita tener que buscar el botón de limpiar.
              onSelected: (isSelected) => ref
                  .read(goalsFilterProvider.notifier)
                  .setStatus(isSelected ? status : null),
            ),
          ),
      ],
    ),
  );
}
