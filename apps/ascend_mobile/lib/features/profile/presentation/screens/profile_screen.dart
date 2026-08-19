import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/auth_controller.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Perfil propio.
///
/// Consume el perfil por streaming: al editarlo, la pantalla se actualiza sola
/// sin recargar a mano ni pasar datos de vuelta por la navegación.
class ProfileScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.push(Routes.settings),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ajustes',
          ),
        ],
      ),
      body: AsyncStateBuilder<Result<AppUser>>(
        value: profile,
        onRetry: () => ref.invalidate(profileProvider),
        data: (Result<AppUser> result) => result.fold<Widget>(
          onSuccess: (AppUser user) => _ProfileBody(user: user),
          // El fallo que viaja dentro del stream se pinta con la misma vista de
          // error que el resto de la app: mensaje traducido y reintento.
          onFailure: (Failure failure) => ErrorStateView(
            failure: failure,
            onRetry: () => ref.invalidate(profileProvider),
          ),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(AscendSpacing.lg),
    children: <Widget>[
      Center(
        child: Column(
          children: <Widget>[
            CircleAvatar(
              radius: 44,
              backgroundColor: context.colors.primaryContainer,
              foregroundImage: user.photoUrl == null
                  ? null
                  : NetworkImage(user.photoUrl!),
              child: Text(
                _initials(user.displayName),
                style: context.texts.headlineSmall,
              ),
            ),
            const SizedBox(height: AscendSpacing.lg),
            Text(user.displayName, style: context.texts.headlineSmall),
            const SizedBox(height: AscendSpacing.xs),
            Text(
              user.displayHandle,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            if (user.bio != null) ...<Widget>[
              const SizedBox(height: AscendSpacing.md),
              Text(user.bio!, textAlign: TextAlign.center),
            ],
            if (user.isAdmin) ...<Widget>[
              const SizedBox(height: AscendSpacing.md),
              Chip(
                avatar: const Icon(Icons.shield_rounded, size: 16),
                label: const Text('Administrador'),
                backgroundColor: context.colors.primaryContainer,
              ),
            ],
            const SizedBox(height: AscendSpacing.lg),
            AscendButton.secondary(
              label: 'Editar perfil',
              icon: Icons.edit_outlined,
              expanded: false,
              onPressed: () => context.push(Routes.profileEdit),
            ),
          ],
        ),
      ),
      const SizedBox(height: AscendSpacing.xl),
      Row(
        children: <Widget>[
          Expanded(
            child: _StatTile(
              label: 'Aura',
              value: '${user.aura.total}',
              icon: Icons.auto_awesome_rounded,
            ),
          ),
          const SizedBox(width: AscendSpacing.md),
          Expanded(
            child: _StatTile(
              label: 'Nivel',
              value: '${user.aura.level}',
              icon: Icons.military_tech_rounded,
            ),
          ),
          const SizedBox(width: AscendSpacing.md),
          Expanded(
            child: _StatTile(
              label: 'Racha',
              value: '${user.stats.currentStreak}',
              icon: Icons.local_fire_department_rounded,
            ),
          ),
        ],
      ),
      const SizedBox(height: AscendSpacing.xl),
      ListTile(
        leading: const Icon(Icons.mail_outline_rounded),
        title: const Text('Email'),
        subtitle: Text(user.email),
        trailing: user.emailVerified
            ? Icon(Icons.verified_rounded, color: context.ascend.success)
            : const Icon(Icons.error_outline_rounded),
      ),
      const Divider(),
      ListTile(
        leading: Icon(Icons.logout_rounded, color: context.colors.error),
        title: Text(
          'Cerrar sesión',
          style: TextStyle(color: context.colors.error),
        ),
        onTap: () => _confirmSignOut(context, ref),
      ),
    ],
  );

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  /// Pide confirmación antes de cerrar sesión.
  ///
  /// Sin la confirmación, un toque accidental en la última fila de la lista
  /// obliga a volver a escribir email y contraseña.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Vas a tener que volver a entrar con tu email.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AscendSpacing.lg),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHighest,
      borderRadius: AscendRadius.cardRadius,
    ),
    child: Column(
      children: <Widget>[
        Icon(icon, color: context.ascend.aura, size: 20),
        const SizedBox(height: AscendSpacing.sm),
        Text(value, style: context.texts.titleLarge),
        Text(
          label,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
