import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/notifications/application/notifications_controller.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Preferencias de notificación.
///
/// Cada interruptor **detiene de verdad** el envío: la decisión la toma el
/// servidor leyendo estos mismos campos antes de mandar nada. No es una
/// preferencia local que filtre lo que ya llegó.
class NotificationSettingsScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final saving = ref.watch(notificationSettingsControllerProvider);
    final failure = saving.error is Failure ? saving.error! as Failure : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: AsyncStateBuilder<Result<AppUser>>(
        value: profile,
        onRetry: () => ref.invalidate(profileProvider),
        data: (Result<AppUser> result) => result.fold<Widget>(
          onFailure: (Failure f) => ErrorStateView(
            failure: f,
            onRetry: () => ref.invalidate(profileProvider),
          ),
          onSuccess: (AppUser user) => _Form(
            settings: user.settings.notifications,
            isSaving: saving.isLoading,
            failure: failure,
          ),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({
    required this.settings,
    required this.isSaving,
    required this.failure,
  });

  final NotificationSettings settings;
  final bool isSaving;
  final Failure? failure;

  Future<void> _save(WidgetRef ref, NotificationSettings updated) =>
      ref.read(notificationSettingsControllerProvider.notifier).save(updated);

  /// Elige una hora y devuelve el `HH:mm` que guarda el perfil.
  Future<String?> _pickTime(BuildContext context, String? current) async {
    final parsed = minutesOfDay(current);
    final picked = await showTimePicker(
      context: context,
      initialTime: parsed == null
          ? const TimeOfDay(hour: 20, minute: 0)
          : TimeOfDay(hour: parsed ~/ 60, minute: parsed % 60),
    );
    if (picked == null) {
      return null;
    }
    final hour = picked.hour.toString().padLeft(2, '0');
    final minute = picked.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(notificationPermissionProvider).value;
    final hasQuietHours =
        settings.quietHoursStart != null && settings.quietHoursEnd != null;

    return ListView(
      padding: const EdgeInsets.all(AscendSpacing.lg),
      children: <Widget>[
        if (failure != null) ...<Widget>[
          ErrorStateView(failure: failure!, compact: true),
          const SizedBox(height: AscendSpacing.lg),
        ],
        // Si el sistema tiene el permiso denegado, los interruptores de acá no
        // cambian nada. Decirlo evita que alguien active todo y siga sin
        // recibir nada, sin entender por qué.
        if (permission != null &&
            permission != NotificationPermission.granted) ...<Widget>[
          Container(
            padding: const EdgeInsets.all(AscendSpacing.md),
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
                    shouldExplainBeforeAsking(permission)
                        ? 'Todavía no diste permiso al sistema. Estas '
                              'preferencias se van a aplicar cuando lo hagas.'
                        : 'El sistema tiene los avisos bloqueados para Ascend. '
                              'Se habilitan desde los ajustes del teléfono.',
                    style: context.texts.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AscendSpacing.lg),
        ],
        Text('Qué querés recibir', style: context.texts.titleMedium),
        const SizedBox(height: AscendSpacing.sm),
        _Toggle(
          title: 'Recordatorio diario',
          subtitle: 'Un aviso por día, solo si te queda algo pendiente.',
          value: settings.dailyReminder,
          enabled: !isSaving,
          onChanged: (bool value) =>
              _save(ref, settings.copyWith(dailyReminder: value)),
        ),
        if (settings.dailyReminder)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('Hora del recordatorio'),
            subtitle: Text(
              '${settings.reminderTime}, en tu hora local.',
              style: context.texts.bodySmall,
            ),
            trailing: Text(
              settings.reminderTime,
              style: context.texts.titleMedium,
            ),
            onTap: isSaving
                ? null
                : () async {
                    final time = await _pickTime(
                      context,
                      settings.reminderTime,
                    );
                    if (time != null) {
                      await _save(ref, settings.copyWith(reminderTime: time));
                    }
                  },
          ),
        _Toggle(
          title: 'Racha en riesgo',
          subtitle: 'Solo el día en que estás por perderla.',
          value: settings.streakAlerts,
          enabled: !isSaving,
          onChanged: (bool value) =>
              _save(ref, settings.copyWith(streakAlerts: value)),
        ),
        _Toggle(
          title: 'Actividad de la comunidad',
          subtitle:
              'Likes y comentarios, agrupados: uno por publicación y día.',
          value: settings.socialActivity,
          enabled: !isSaving,
          onChanged: (bool value) =>
              _save(ref, settings.copyWith(socialActivity: value)),
        ),
        _Toggle(
          title: 'Sugerencias de la IA',
          subtitle: 'Ideas de misiones para tus objetivos.',
          value: settings.aiSuggestions,
          enabled: !isSaving,
          onChanged: (bool value) =>
              _save(ref, settings.copyWith(aiSuggestions: value)),
        ),
        const SizedBox(height: AscendSpacing.xl),
        Text('Horario de silencio', style: context.texts.titleMedium),
        const SizedBox(height: AscendSpacing.xs),
        Text(
          'Durante estas horas no suena nada. Los avisos igual quedan en la '
          'bandeja: no se pierde nada, solo no te despierta.',
          style: context.texts.bodySmall?.copyWith(
            color: context.ascend.textSecondary,
          ),
        ),
        const SizedBox(height: AscendSpacing.sm),
        _Toggle(
          title: 'Activar horario de silencio',
          value: hasQuietHours,
          enabled: !isSaving,
          onChanged: (bool value) => _save(
            ref,
            // `copyWith` no puede poner `null` —significa "no lo cambies"—, así
            // que apagar el silencio construye los ajustes explícitamente.
            value
                ? settings.copyWith(
                    quietHoursStart: '22:00',
                    quietHoursEnd: '07:00',
                  )
                : NotificationSettings(
                    dailyReminder: settings.dailyReminder,
                    reminderTime: settings.reminderTime,
                    streakAlerts: settings.streakAlerts,
                    socialActivity: settings.socialActivity,
                    aiSuggestions: settings.aiSuggestions,
                  ),
          ),
        ),
        if (hasQuietHours)
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final time = await _pickTime(
                            context,
                            settings.quietHoursStart,
                          );
                          if (time != null) {
                            await _save(
                              ref,
                              settings.copyWith(quietHoursStart: time),
                            );
                          }
                        },
                  child: Text('Desde ${settings.quietHoursStart}'),
                ),
              ),
              const SizedBox(width: AscendSpacing.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final time = await _pickTime(
                            context,
                            settings.quietHoursEnd,
                          );
                          if (time != null) {
                            await _save(
                              ref,
                              settings.copyWith(quietHoursEnd: time),
                            );
                          }
                        },
                  child: Text('Hasta ${settings.quietHoursEnd}'),
                ),
              ),
            ],
          ),
        const SizedBox(height: AscendSpacing.xl),
        Text(
          'Los avisos de moderación sobre tu contenido llegan siempre: si algo '
          'tuyo se oculta, tenés que poder enterarte.',
          style: context.texts.bodySmall?.copyWith(
            color: context.ascend.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: enabled ? onChanged : null,
    title: Text(title),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            style: context.texts.bodySmall?.copyWith(
              color: context.ascend.textSecondary,
            ),
          ),
  );
}
