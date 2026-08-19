import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/features/goals/presentation/widgets/goal_widgets.dart';
import 'package:ascend_mobile/features/integrations/application/integrations_controller.dart';
import 'package:ascend_mobile/features/missions/application/missions_controller.dart';
import 'package:ascend_mobile/features/missions/presentation/widgets/mission_widgets.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Una misión concreta, leída una sola vez.
///
/// No es un stream: el detalle se abre, se actúa y se cierra. Mantener una
/// suscripción viva por cada misión que alguien mira cuesta lecturas sin
/// aportar nada, porque quien la modifica es esta misma pantalla.
// Sin anotación de tipo explícita: `FutureProviderFamily` no está exportado.
final missionDetailProvider = FutureProvider.family<Result<Mission>, String>((
  ref,
  missionId,
) async {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) {
    return const Failed<Mission>(
      AuthFailure(
        messageKey: 'failure.auth.sessionExpired',
        code: 'no-session',
      ),
    );
  }
  return ref
      .watch(missionRepositoryProvider)
      .getMission(uid: uid, missionId: missionId);
}, name: 'missionDetail');

/// Detalle de una misión, con sus acciones.
class MissionDetailScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const MissionDetailScreen({required this.missionId, super.key});

  /// Id de la misión.
  final String missionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mission = ref.watch(missionDetailProvider(missionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Misión')),
      body: AsyncStateBuilder<Result<Mission>>(
        value: mission,
        onRetry: () => ref.invalidate(missionDetailProvider(missionId)),
        data: (Result<Mission> result) => result.fold<Widget>(
          onSuccess: (Mission value) => _MissionDetailBody(mission: value),
          onFailure: (Failure failure) => ErrorStateView(
            failure: failure,
            onRetry: () => ref.invalidate(missionDetailProvider(missionId)),
          ),
        ),
      ),
    );
  }
}

class _MissionDetailBody extends ConsumerWidget {
  const _MissionDetailBody({required this.mission});

  final Mission mission;

  /// Ejecuta una acción y, si sale bien, vuelve atrás.
  ///
  /// Solo se sale si la operación tuvo éxito: si falló, el detalle sigue a la
  /// vista mostrando el error en vez de volver como si nada.
  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<bool> Function() action,
  ) async {
    final ok = await action();
    if (ok && context.mounted) {
      ref.invalidate(missionDetailProvider(mission.id));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(missionControllerProvider);
    final isBusy = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;
    final controller = ref.read(missionControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(AscendSpacing.lg),
      children: <Widget>[
        if (failure != null) ...<Widget>[
          ErrorStateView(failure: failure, compact: true),
          const SizedBox(height: AscendSpacing.lg),
        ],
        Text(mission.title, style: context.texts.headlineSmall),
        if (mission.goalTitle != null) ...<Widget>[
          const SizedBox(height: AscendSpacing.xs),
          Text(
            mission.goalTitle!,
            style: context.texts.bodyMedium?.copyWith(
              color: context.ascend.textSecondary,
            ),
          ),
        ],
        if (mission.description != null) ...<Widget>[
          const SizedBox(height: AscendSpacing.lg),
          Text(mission.description!, style: context.texts.bodyMedium),
        ],
        const SizedBox(height: AscendSpacing.xl),
        _Row(label: 'Estado', value: mission.status.label),
        _Row(label: 'Exigencia', value: mission.difficulty.label),
        _Row(label: 'Presupuesto', value: mission.budget.label),
        if (mission.estimatedMinutes != null)
          _Row(label: 'Duración', value: '${mission.estimatedMinutes} min'),
        if (mission.dueDate != null)
          _Row(
            label: 'Fecha límite',
            value: MaterialLocalizations.of(
              context,
            ).formatMediumDate(mission.dueDate!),
            highlight: mission.isOverdue(),
          ),
        // La recompensa solo se muestra cuando el servidor ya la fijó. Mostrar
        // "0" antes de eso haría creer que la misión no otorga nada.
        if (mission.auraReward > 0)
          _Row(label: 'Aura', value: '${mission.auraReward}'),
        _WeatherHint(mission: mission),
        if (mission.requiresEvidence || mission.evidence != null) ...<Widget>[
          const SizedBox(height: AscendSpacing.xl),
          _EvidenceSection(mission: mission),
        ],
        const SizedBox(height: AscendSpacing.xxl),
        if (mission.status.isOpen) ...<Widget>[
          AscendButton(
            label: 'Completar misión',
            icon: Icons.check_rounded,
            isLoading: isBusy,
            onPressed: isBusy
                ? null
                : () => _act(context, ref, () => controller.complete(mission)),
          ),
          const SizedBox(height: AscendSpacing.sm),
          AscendButton.secondary(
            label: 'Saltear por hoy',
            icon: Icons.skip_next_rounded,
            onPressed: isBusy
                ? null
                : () => _act(context, ref, () => controller.skip(mission)),
          ),
        ] else
          Text(
            'Esta misión ya está ${mission.status.label.toLowerCase()}.',
            style: context.texts.bodyMedium?.copyWith(
              color: context.ascend.textSecondary,
            ),
          ),
        const SizedBox(height: AscendSpacing.lg),
        AscendButton.destructive(
          label: 'Eliminar misión',
          icon: Icons.delete_outline_rounded,
          onPressed: isBusy
              ? null
              : () => _act(context, ref, () => controller.delete(mission.id)),
        ),
      ],
    );
  }
}

/// Aviso de clima para una misión al aire libre.
///
/// Solo aparece cuando puede cambiar una decisión: categoría de exterior, fecha
/// dentro de la semana y pronóstico adverso. Si la API no responde no se muestra
/// nada — el clima nunca bloquea ni demora una misión, es información de apoyo.
class _WeatherHint extends ConsumerWidget {
  const _WeatherHint({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(missionWeatherProvider(mission)).value;
    if (forecast == null || !forecast.discouragesOutdoor) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: AscendSpacing.lg),
      padding: const EdgeInsets.all(AscendSpacing.md),
      decoration: BoxDecoration(
        color: context.ascend.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AscendRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.umbrella_outlined, color: context.ascend.warning),
          const SizedBox(width: AscendSpacing.md),
          Expanded(
            child: Text(
              'Ese día se espera '
              '${forecast.precipitationProbability}% de probabilidad de lluvia '
              'y ${forecast.roundedTemperature}°. Quizá te convenga moverla.',
              style: context.texts.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado de la evidencia de una misión.
///
/// Distingue **subida** de **revisión**: son dos cosas distintas y confundirlas
/// haría creer que una foto rechazada por moderación "falló al subir".
class _EvidenceSection extends ConsumerWidget {
  const _EvidenceSection({required this.mission});

  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evidence = mission.evidence;
    final pending = ref.watch(pendingUploadsProvider).value ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Evidencia', style: context.texts.titleMedium),
        const SizedBox(height: AscendSpacing.sm),
        if (evidence == null)
          Text(
            'Esta misión pide una foto para completarse. Todavía no adjuntaste '
            'ninguna.',
            style: context.texts.bodyMedium?.copyWith(
              color: context.ascend.textSecondary,
            ),
          )
        else ...<Widget>[
          if (evidence.note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AscendSpacing.sm),
              child: Text(evidence.note!, style: context.texts.bodyMedium),
            ),
          _Row(label: 'Archivo', value: _uploadLabel(evidence.uploadStatus)),
          if (evidence.reviewStatus != EvidenceReviewStatus.pending)
            _Row(
              label: 'Revisión',
              value: evidence.reviewStatus.isRejected
                  ? 'Rechazada'
                  : 'Aprobada',
              highlight: evidence.reviewStatus.isRejected,
            ),
        ],
        // Mientras Storage no exista, la cola nunca drena. Decirlo es más
        // honesto que mostrar un "subiendo…" que no va a terminar nunca.
        if (pending > 0)
          Padding(
            padding: const EdgeInsets.only(top: AscendSpacing.sm),
            child: Text(
              '$pending ${pending == 1 ? 'foto espera' : 'fotos esperan'} para '
              'subir. El almacenamiento todavía no está habilitado.',
              style: context.texts.bodySmall?.copyWith(
                color: context.ascend.warning,
              ),
            ),
          ),
      ],
    );
  }

  static String _uploadLabel(EvidenceUploadStatus status) => switch (status) {
    EvidenceUploadStatus.pending => 'Guardada en el teléfono',
    EvidenceUploadStatus.uploading => 'Subiendo',
    EvidenceUploadStatus.uploaded => 'Subida',
    EvidenceUploadStatus.failed => 'No se pudo subir',
  };
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AscendSpacing.md),
    child: Row(
      children: <Widget>[
        Text(
          label,
          style: context.texts.bodyMedium?.copyWith(
            color: context.ascend.textSecondary,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: context.texts.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlight ? context.colors.error : null,
            ),
          ),
        ),
      ],
    ),
  );
}
