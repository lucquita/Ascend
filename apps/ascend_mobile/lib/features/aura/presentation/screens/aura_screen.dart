import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/aura/application/aura_controller.dart';
import 'package:ascend_ui/ascend_ui.dart';
// El tipo Page existe en el dominio (paginación del ledger) y en Flutter
// (navegación). Acá se usa el del dominio, así que se oculta el de Flutter.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pantalla de Aura: saldo, nivel, evolución y últimos movimientos.
///
/// Todo lo que se ve acá lo calculó el servidor. La app no escribe ni un número
/// (ADR-003).
class AuraScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const AuraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aura = ref.watch(auraProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tu Aura')),
      body: AsyncStateBuilder<Result<Aura>>(
        value: aura,
        onRetry: () => ref.invalidate(auraProvider),
        data: (Result<Aura> result) => result.fold<Widget>(
          onSuccess: (Aura value) => _AuraBody(aura: value),
          onFailure: (Failure failure) => ErrorStateView(
            failure: failure,
            onRetry: () => ref.invalidate(auraProvider),
          ),
        ),
      ),
    );
  }
}

class _AuraBody extends ConsumerWidget {
  const _AuraBody({required this.aura});

  final Aura aura;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(AscendSpacing.lg),
    children: <Widget>[
      _LevelCard(aura: aura),
      const SizedBox(height: AscendSpacing.xl),
      const _TrendSection(),
      const SizedBox(height: AscendSpacing.xl),
      const _LedgerSection(),
    ],
  );
}

/// Nivel actual y cuánto falta para el siguiente.
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.aura});

  final Aura aura;

  @override
  Widget build(BuildContext context) {
    // El token `aura` (#F59E0B) reprueba AA como texto sobre fondo claro; para
    // texto se usa `auraOnSurface`. El relleno del anillo sí puede usarlo.
    final ascend = context.ascend;

    return Container(
      padding: AscendSpacing.card,
      decoration: BoxDecoration(
        borderRadius: AscendRadius.cardRadius,
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          ProgressRing(
            progress: aura.levelProgress,
            size: 88,
            strokeWidth: 8,
            color: ascend.aura,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${aura.level}',
                  style: context.texts.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ascend.auraOnSurface,
                  ),
                ),
                Text('nivel', style: context.texts.labelSmall),
              ],
            ),
          ),
          const SizedBox(width: AscendSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(aura.levelName, style: context.texts.titleLarge),
                const SizedBox(height: AscendSpacing.xs),
                AuraBadge(amount: aura.total),
                const SizedBox(height: AscendSpacing.sm),
                Text(
                  aura.xpForNextLevel <= 0
                      // En el último nivel no hay "faltan X": decirlo evita
                      // mostrar un progreso que nunca avanza.
                      ? 'Alcanzaste el nivel máximo.'
                      : 'Te faltan ${aura.remainingForNextLevel} para el '
                            'nivel siguiente.',
                  style: context.texts.bodySmall?.copyWith(
                    color: ascend.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Evolución de los últimos 30 días.
class _TrendSection extends ConsumerWidget {
  const _TrendSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(auraTrendProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Últimos 30 días', style: context.texts.titleMedium),
        const SizedBox(height: AscendSpacing.md),
        AsyncStateBuilder<Result<AuraTrend>>(
          value: trend,
          loading: const AscendSkeleton(height: 120),
          onRetry: () => ref.invalidate(auraTrendProvider),
          data: (Result<AuraTrend> result) => result.fold<Widget>(
            onFailure: (Failure f) => ErrorStateView(failure: f, compact: true),
            onSuccess: (AuraTrend value) {
              if (value.total == 0) {
                return Text(
                  'Todavía no ganaste Aura. Completá una misión y aparece acá.',
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.ascend.textSecondary,
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _BarChart(trend: value),
                  const SizedBox(height: AscendSpacing.md),
                  Wrap(
                    spacing: AscendSpacing.xl,
                    runSpacing: AscendSpacing.sm,
                    children: <Widget>[
                      _Stat(label: 'Total', value: '${value.total}'),
                      _Stat(label: 'Mejor día', value: '${value.bestDay}'),
                      _Stat(
                        label: 'Días activos',
                        value: '${value.activeDays}',
                      ),
                      _Stat(
                        label: 'Promedio',
                        value: value.dailyAverage.toStringAsFixed(1),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Gráfico de barras simple.
///
/// Se dibuja con `Container`s y no con una librería de charts: son 30 barras sin
/// ejes ni interacción, y sumar una dependencia de gráficos a la app móvil por
/// esto engordaría el binario sin necesidad.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.trend});

  final AuraTrend trend;

  @override
  Widget build(BuildContext context) {
    final days = trend.byDay.keys.toList();

    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Semantics(
                  label: '$day: ${trend.byDay[day]} de Aura',
                  child: Container(
                    // Mínimo de 2px para que un día en cero se vea como una
                    // marca y no como un hueco: el hueco parece un error de
                    // carga.
                    height: 2 + trend.heightFor(day) * 90,
                    decoration: BoxDecoration(
                      color: trend.byDay[day]! > 0
                          ? context.ascend.aura
                          : context.colors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Últimos movimientos del ledger.
class _LedgerSection extends ConsumerWidget {
  const _LedgerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(auraLedgerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Movimientos', style: context.texts.titleMedium),
        const SizedBox(height: AscendSpacing.md),
        AsyncStateBuilder<Result<Paginated<AuraEntry>>>(
          value: ledger,
          loading: const AscendSkeleton(height: 80),
          onRetry: () => ref.invalidate(auraLedgerProvider),
          isEmpty: (result) => result.valueOrNull?.isEmpty ?? false,
          emptyState: const EmptyStateConfig(
            icon: Icons.receipt_long_outlined,
            title: 'Sin movimientos',
            message: 'Cada misión que completes deja su asiento acá.',
          ),
          data: (Result<Paginated<AuraEntry>> result) => result.fold<Widget>(
            onFailure: (Failure f) => ErrorStateView(failure: f, compact: true),
            onSuccess: (Paginated<AuraEntry> page) => Column(
              children: <Widget>[
                for (final entry in page.items) _LedgerTile(entry: entry),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});

  final AuraEntry entry;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: Icon(
      entry.isGain ? Icons.trending_up_rounded : Icons.trending_down_rounded,
      color: entry.isGain ? context.ascend.success : context.colors.error,
    ),
    title: Text(
      entry.note ?? _reasonLabel(entry.reason),
      style: context.texts.bodyMedium,
    ),
    subtitle: Text(
      MaterialLocalizations.of(context).formatMediumDate(entry.createdAt),
      style: context.texts.labelSmall,
    ),
    trailing: Text(
      '${entry.isGain ? '+' : ''}${entry.amount}',
      style: context.texts.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: entry.isGain
            ? context.ascend.auraOnSurface
            : context.colors.error,
      ),
    ),
  );

  static String _reasonLabel(AuraReason reason) => switch (reason) {
    AuraReason.missionCompleted => 'Misión completada',
    AuraReason.goalCompleted => 'Objetivo completado',
    AuraReason.milestone => 'Hito alcanzado',
    AuraReason.streakBonus => 'Bonificación por racha',
    AuraReason.achievement => 'Logro desbloqueado',
    AuraReason.dailyLogin => 'Ingreso diario',
    AuraReason.penalty => 'Penalización',
    AuraReason.adminAdjustment => 'Ajuste del equipo',
  };
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        value,
        style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      Text(
        label,
        style: context.texts.labelSmall?.copyWith(
          color: context.ascend.textSecondary,
        ),
      ),
    ],
  );
}
