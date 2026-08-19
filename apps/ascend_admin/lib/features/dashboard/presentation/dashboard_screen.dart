import 'package:ascend_admin/router/admin_router.dart';
import 'package:ascend_admin/shared/admin_widgets.dart';
import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// KPIs de la plataforma.
///
/// Lee **un solo documento** (`adminStats/latest`), que escribe una función
/// programada todas las madrugadas. No recorre colecciones: contar usuarios en
/// vivo costaría una lectura facturada por cada mil documentos cada vez que
/// alguien abre esta pantalla.
class DashboardScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AscendSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AdminSectionHeader(
            title: 'Dashboard',
            subtitle: 'Métricas agregadas de la plataforma.',
          ),
          AsyncStateBuilder<Result<AdminStats>>(
            value: stats,
            onRetry: () => ref.invalidate(adminStatsProvider),
            data: (Result<AdminStats> result) => result.fold<Widget>(
              onFailure: (Failure failure) => ErrorStateView(
                failure: failure,
                onRetry: () => ref.invalidate(adminStatsProvider),
              ),
              onSuccess: (AdminStats value) => _Kpis(stats: value),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.stats});

  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // La época significa que el documento nunca se escribió: la función
    // programada todavía no corrió, o no está desplegada.
    final neverRan = stats.generatedAt.millisecondsSinceEpoch == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (neverRan)
          const _Notice(
            icon: Icons.schedule_rounded,
            text:
                'Todavía no hay métricas calculadas. La función aggregateStats '
                'corre a las 04:00 UTC; hasta su primera ejecución esta '
                'pantalla muestra ceros.',
          )
        else if (stats.isStaleAt(now))
          _Notice(
            icon: Icons.warning_amber_rounded,
            text:
                'Las métricas son de hace ${now.difference(stats.generatedAt).inDays} '
                'días. La agregación diaria puede haber fallado.',
          ),
        if (neverRan || stats.isStaleAt(now))
          const SizedBox(height: AscendSpacing.lg),
        // `Wrap` en vez de `GridView`: las tarjetas se acomodan solas a
        // cualquier ancho sin tener que calcular cuántas columnas entran, y el
        // panel tiene que servir igual en 1280px que en una tablet.
        Wrap(
          spacing: AscendSpacing.md,
          runSpacing: AscendSpacing.md,
          children: <Widget>[
            _KpiCard(
              label: 'Cuentas registradas',
              value: '${stats.usersTotal}',
              icon: Icons.people_rounded,
            ),
            _KpiCard(
              label: 'Activas (7 días)',
              value: '${stats.usersActive7d}',
              icon: Icons.bolt_rounded,
              hint: stats.usersTotal == 0
                  ? null
                  : '${_percent(stats.usersActive7d, stats.usersTotal)}% del total',
            ),
            _KpiCard(
              label: 'Altas (7 días)',
              value: '${stats.usersNew7d}',
              icon: Icons.person_add_alt_rounded,
            ),
            _KpiCard(
              label: 'Objetivos en curso',
              value: '${stats.goalsActive}',
              icon: Icons.flag_rounded,
            ),
            _KpiCard(
              label: 'Misiones completadas (7 días)',
              value: '${stats.missionsCompleted7d}',
              icon: Icons.task_alt_rounded,
            ),
            _KpiCard(
              label: 'Aura otorgada (7 días)',
              value: '${stats.auraGranted7d}',
              icon: Icons.auto_awesome_rounded,
            ),
            _KpiCard(
              label: 'Publicaciones',
              value: '${stats.postsTotal}',
              icon: Icons.article_rounded,
            ),
            _KpiCard(
              label: 'Costo de IA (hoy)',
              value: '\$${stats.aiCostUsdToday.toStringAsFixed(2)}',
              icon: Icons.smart_toy_rounded,
              hint: '${stats.aiCallsToday} llamadas',
            ),
          ],
        ),
        const SizedBox(height: AscendSpacing.lg),
        // Los reportes abiertos van aparte y con acción directa: es el único
        // número del dashboard que significa trabajo pendiente para alguien.
        _PendingWork(open: stats.reportsOpen),
        const SizedBox(height: AscendSpacing.lg),
        Text(
          neverRan
              ? 'Sin datos calculados todavía.'
              : 'Calculado el '
                    '${MaterialLocalizations.of(context).formatMediumDate(stats.generatedAt)}.',
          style: context.texts.bodySmall?.copyWith(
            color: context.ascend.textSecondary,
          ),
        ),
      ],
    );
  }

  static int _percent(int part, int total) =>
      total == 0 ? 0 : ((part / total) * 100).round();
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? hint;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: context.ascend.textSecondary),
              const SizedBox(width: AscendSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: context.texts.labelMedium?.copyWith(
                    color: context.ascend.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AscendSpacing.sm),
          Text(value, style: context.texts.headlineMedium),
          if (hint != null) ...<Widget>[
            const SizedBox(height: AscendSpacing.xxs),
            Text(
              hint!,
              style: context.texts.bodySmall?.copyWith(
                color: context.ascend.textSecondary,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _PendingWork extends StatelessWidget {
  const _PendingWork({required this.open});

  final int open;

  @override
  Widget build(BuildContext context) {
    final hasWork = open > 0;

    return AdminCard(
      child: Row(
        children: <Widget>[
          Icon(
            hasWork
                ? Icons.flag_circle_rounded
                : Icons.check_circle_outline_rounded,
            color: hasWork ? context.colors.error : context.ascend.success,
          ),
          const SizedBox(width: AscendSpacing.md),
          Expanded(
            child: Text(
              hasWork
                  ? '$open ${open == 1 ? 'reporte espera' : 'reportes esperan'} revisión.'
                  : 'No hay reportes pendientes.',
              style: context.texts.bodyMedium,
            ),
          ),
          if (hasWork)
            AscendButton.secondary(
              label: 'Ir a moderación',
              // Dentro de un `Row` el ancho no está acotado.
              expanded: false,
              onPressed: () => context.go(AdminRoutes.reports),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AscendSpacing.md),
    decoration: BoxDecoration(
      color: context.ascend.warning.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AscendRadius.md),
    ),
    child: Row(
      children: <Widget>[
        Icon(icon, color: context.ascend.warning),
        const SizedBox(width: AscendSpacing.md),
        Expanded(child: Text(text, style: context.texts.bodySmall)),
      ],
    ),
  );
}
