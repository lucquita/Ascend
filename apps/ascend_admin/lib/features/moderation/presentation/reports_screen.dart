import 'package:ascend_admin/shared/admin_widgets.dart';
import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado de la última acción de moderación.
class ModerationController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Aplica una decisión sobre un reporte.
  ///
  /// No hace falta refrescar la lista: `openReportsProvider` es un stream y el
  /// reporte desaparece solo de la cola en cuanto el servidor lo cierra.
  Future<bool> resolve({
    required String reportId,
    required ModerationAction action,
    String? note,
  }) async {
    state = const AsyncLoading<void>();
    final result = await guardResult(
      () => ref
          .read(resolveReportUseCaseProvider)
          .call(reportId: reportId, action: action, note: note),
    );

    return result.fold(
      onSuccess: (_) {
        state = const AsyncData<void>(null);
        return true;
      },
      onFailure: (Failure failure) {
        state = AsyncError<void>(
          failure,
          failure.stackTrace ?? StackTrace.empty,
        );
        return false;
      },
    );
  }
}

/// Controlador de la moderación.
final NotifierProvider<ModerationController, AsyncValue<void>>
moderationControllerProvider =
    NotifierProvider<ModerationController, AsyncValue<void>>(
      ModerationController.new,
      name: 'moderation',
    );

/// Bandeja de moderación.
///
/// La cola llega **ordenada por gravedad y luego por antigüedad**, no por fecha
/// de llegada. Una bandeja cronológica hace que un caso de violencia espere
/// detrás de veinte reportes de spam.
class ReportsScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(openReportsProvider);
    final action = ref.watch(moderationControllerProvider);
    final failure = action.error is Failure ? action.error! as Failure : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AscendSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AdminSectionHeader(
            title: 'Reportes',
            subtitle: 'Primero lo más grave; a igual gravedad, lo más viejo.',
          ),
          if (failure != null) ...<Widget>[
            ErrorStateView(failure: failure, compact: true),
            const SizedBox(height: AscendSpacing.lg),
          ],
          AsyncStateBuilder<Result<List<Report>>>(
            value: reports,
            onRetry: () => ref.invalidate(openReportsProvider),
            data: (Result<List<Report>> result) => result.fold<Widget>(
              onFailure: (Failure f) => ErrorStateView(
                failure: f,
                onRetry: () => ref.invalidate(openReportsProvider),
              ),
              onSuccess: (List<Report> items) => items.isEmpty
                  ? const EmptyStateView(
                      title: 'Nada pendiente',
                      message:
                          'No hay reportes esperando revisión. Buena señal.',
                      icon: Icons.verified_outlined,
                    )
                  : Column(
                      children: <Widget>[
                        for (final report in items)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AscendSpacing.md,
                            ),
                            child: _ReportCard(
                              report: report,
                              isBusy: action.isLoading,
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.report, required this.isBusy});

  final Report report;
  final bool isBusy;

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    ModerationAction action,
  ) async {
    String? note;

    if (action.needsConfirmation) {
      note = await showAdminReasonDialog(
        context,
        title: 'Ocultar y suspender',
        message:
            'La cuenta va a quedar suspendida y su sesión se cierra al '
            'instante. Escribí por qué.',
        confirmLabel: 'Suspender',
      );
      // Sin motivo no se suspende: el servidor lo rechaza igual, y la nota es
      // lo único que después explica la decisión.
      if (note == null || note.trim().length < 5) {
        return;
      }
    }

    await ref
        .read(moderationControllerProvider.notifier)
        .resolve(reportId: report.id, action: action, note: note);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priority = reportPriority(report);

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AdminBadge(
                label: _reasonLabel(report.reason),
                // Los tres primeros niveles son los que pueden hacer daño real
                // y se pintan en rojo; el resto en gris, para que el color
                // signifique algo cuando la bandeja tiene cuarenta filas.
                color: priority <= 2
                    ? context.colors.error
                    : context.ascend.textSecondary,
              ),
              const SizedBox(width: AscendSpacing.sm),
              AdminBadge(
                label: report.targetType == 'post'
                    ? 'publicación'
                    : 'comentario',
                color: context.colors.primary,
              ),
              const Spacer(),
              Text(
                MaterialLocalizations.of(
                  context,
                ).formatMediumDate(report.createdAt),
                style: context.texts.bodySmall?.copyWith(
                  color: context.ascend.textSecondary,
                ),
              ),
            ],
          ),
          if (report.details != null) ...<Widget>[
            const SizedBox(height: AscendSpacing.md),
            Text(report.details!, style: context.texts.bodyMedium),
          ],
          const SizedBox(height: AscendSpacing.sm),
          Text(
            'Contenido ${report.targetId} · reportado por ${report.reporterId}',
            style: context.texts.bodySmall?.copyWith(
              color: context.ascend.textSecondary,
            ),
          ),
          const SizedBox(height: AscendSpacing.lg),
          Wrap(
            spacing: AscendSpacing.sm,
            runSpacing: AscendSpacing.sm,
            children: <Widget>[
              for (final action in ModerationAction.values)
                OutlinedButton(
                  onPressed: isBusy ? null : () => _apply(context, ref, action),
                  style: action == ModerationAction.suspendAuthor
                      ? OutlinedButton.styleFrom(
                          foregroundColor: context.colors.error,
                        )
                      : null,
                  child: Text(action.label),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _reasonLabel(ReportReason reason) => switch (reason) {
    ReportReason.violence => 'violencia',
    ReportReason.harassment => 'acoso',
    ReportReason.nsfw => 'contenido sexual',
    ReportReason.fakeAchievement => 'logro falso',
    ReportReason.spam => 'spam',
    ReportReason.other => 'otro',
  };
}
