import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/goals/application/goals_controller.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Elige a qué objetivo pertenece la misión nueva.
///
/// ## Por qué existe este paso
///
/// El botón "+" de la pantalla principal no sabe a qué objetivo apunta, y una
/// misión **siempre** cuelga de uno: la entidad guarda `goalId`, `goalTitle` y
/// `categoryId` desnormalizados, y sin ellos la pantalla "Hoy" no puede pintar
/// la fila ni el sistema de Aura sabe qué categoría premiar.
///
/// La alternativa —abrir el formulario con un desplegable de objetivos adentro—
/// mezcla dos decisiones en una pantalla y deja el caso de no tener ningún
/// objetivo sin salida clara. Acá, si no hay objetivos, se ofrece crear uno.
class PickGoalScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const PickGoalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('¿A qué objetivo?')),
      body: AsyncStateBuilder<Result<List<Goal>>>(
        value: goals,
        onRetry: () => ref.invalidate(goalsProvider),
        data: (Result<List<Goal>> result) => result.fold<Widget>(
          onFailure: (Failure failure) => ErrorStateView(
            failure: failure,
            onRetry: () => ref.invalidate(goalsProvider),
          ),
          onSuccess: (List<Goal> items) => items.isEmpty
              ? EmptyStateView(
                  title: 'Todavía no tenés objetivos',
                  message:
                      'Una misión es un paso hacia algo. Creá primero el '
                      'objetivo y después las misiones que te llevan ahí.',
                  icon: Icons.flag_outlined,
                  actionLabel: 'Crear un objetivo',
                  onAction: () => context.pushReplacement(Routes.goalNew),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AscendSpacing.lg),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AscendSpacing.sm),
                  itemBuilder: (BuildContext context, int index) {
                    final goal = items[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AscendRadius.md),
                        side: BorderSide(color: context.colors.outlineVariant),
                      ),
                      title: Text(goal.title),
                      subtitle: Text(
                        '${(goal.progress.fraction * 100).round()}% completado',
                        style: context.texts.bodySmall,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      // `pushReplacement`: al volver desde el formulario, la
                      // persona tiene que llegar a "Hoy", no a esta lista
                      // intermedia que ya cumplió su función.
                      onTap: () => context.pushReplacement(
                        Routes.goalMissionNew(goal.id),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
