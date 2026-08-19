import 'package:ascend_admin/shared/admin_widgets.dart';
import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Registro de todas las acciones administrativas.
///
/// La colección es **inescribible desde cualquier cliente**, incluido este
/// panel: solo la escribe el Admin SDK dentro de la misma transacción que
/// aplica la acción. Un registro que quien audita puede editar no sirve para
/// auditar.
class AuditScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(auditLogProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AscendSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AsyncStateBuilder<Result<List<AuditEntry>>>(
            value: entries,
            onRetry: () => ref.invalidate(auditLogProvider),
            data: (Result<List<AuditEntry>> result) => result.fold<Widget>(
              onFailure: (Failure failure) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const AdminSectionHeader(title: 'Auditoría'),
                  ErrorStateView(
                    failure: failure,
                    onRetry: () => ref.invalidate(auditLogProvider),
                  ),
                ],
              ),
              onSuccess: (List<AuditEntry> items) => _AuditList(entries: items),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditList extends StatelessWidget {
  const _AuditList({required this.entries});

  final List<AuditEntry> entries;

  Future<void> _exportCsv(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: auditToCsv(entries)));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${entries.length} entradas copiadas como CSV.')),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      AdminSectionHeader(
        title: 'Auditoría',
        subtitle: 'Últimas ${entries.length} acciones, de la más reciente.',
        actions: <Widget>[
          AscendButton.secondary(
            label: 'Exportar CSV',
            icon: Icons.download_rounded,
            expanded: false,
            onPressed: entries.isEmpty ? null : () => _exportCsv(context),
          ),
        ],
      ),
      if (entries.isEmpty)
        const EmptyStateView(
          title: 'Sin acciones registradas',
          message:
              'Cada cambio de rol, suspensión o moderación va a aparecer acá.',
          icon: Icons.receipt_long_rounded,
        )
      else
        AdminCard(
          padding: EdgeInsets.zero,
          child: AdminScrollableTable(
            child: Column(
              children: <Widget>[
                for (final entry in entries) _AuditRow(entry: entry),
              ],
            ),
          ),
        ),
    ],
  );
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AscendSpacing.lg,
      vertical: AscendSpacing.md,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(_iconFor(entry.action), size: 20, color: context.colors.primary),
        const SizedBox(width: AscendSpacing.md),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.actionLabel,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'por ${entry.actorUid}'
                '${entry.targetUid == null ? '' : ' · sobre ${entry.targetUid}'}',
                style: context.texts.bodySmall?.copyWith(
                  color: context.ascend.textSecondary,
                ),
              ),
              if (entry.details.isNotEmpty) ...<Widget>[
                const SizedBox(height: AscendSpacing.xxs),
                Text(
                  _describe(entry.details),
                  style: context.texts.bodySmall?.copyWith(
                    color: context.ascend.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          // Se muestra la fecha y no "hace 3 minutos": en una auditoría el dato
          // exacto es el que importa, y un relativo obliga a hacer la cuenta.
          MaterialLocalizations.of(context).formatMediumDate(entry.createdAt),
          style: context.texts.bodySmall?.copyWith(
            color: context.ascend.textSecondary,
          ),
        ),
      ],
    ),
  );

  static IconData _iconFor(String action) => switch (action) {
    'set_user_role' => Icons.admin_panel_settings_rounded,
    'set_user_status' => Icons.pause_circle_outline_rounded,
    'resolve_report' => Icons.gavel_rounded,
    _ => Icons.circle_outlined,
  };

  /// Resume los campos extra de la acción en una línea legible.
  static String _describe(Map<String, Object?> details) => details.entries
      .map((MapEntry<String, Object?> e) => '${e.key}: ${e.value}')
      .join(' · ');
}
