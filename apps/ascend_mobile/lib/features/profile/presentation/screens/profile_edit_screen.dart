import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:ascend_mobile/features/profile/application/profile_controller.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Edición del perfil.
class ProfileEditScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _bio = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// Carga los valores actuales una sola vez.
  ///
  /// El perfil llega por streaming: reasignar los controladores en cada emisión
  /// borraría lo que la persona está escribiendo justo en ese momento.
  void _seed(AppUser user) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _name.text = user.displayName;
    _bio.text = user.bio ?? '';
  }

  Future<void> _save(String uid) async {
    FocusScope.of(context).unfocus();
    final saved = await ref
        .read(profileControllerProvider.notifier)
        .save(uid: uid, displayName: _name.text, bio: _bio.text);

    if (!mounted) {
      return;
    }
    if (saved) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final state = ref.watch(profileControllerProvider);
    final isSaving = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: AsyncStateBuilder<Result<AppUser>>(
        value: profile,
        onRetry: () => ref.invalidate(profileProvider),
        data: (result) => result.fold(
          onFailure: (f) => ErrorStateView(
            failure: f,
            onRetry: () => ref.invalidate(profileProvider),
          ),
          onSuccess: (user) {
            _seed(user);
            return ListView(
              padding: const EdgeInsets.all(AscendSpacing.xl),
              children: <Widget>[
                if (failure != null) AuthErrorBanner(failure: failure),
                AuthField(
                  controller: _name,
                  label: 'Tu nombre',
                  prefixIcon: Icons.person_outline_rounded,
                  maxLength: Validators.maxDisplayNameLength,
                  enabled: !isSaving,
                  onChanged: (_) =>
                      ref.read(profileControllerProvider.notifier).clearError(),
                ),
                AuthField(
                  controller: _bio,
                  label: 'Biografía',
                  hint: '¿En qué estás trabajando?',
                  prefixIcon: Icons.notes_rounded,
                  textInputAction: TextInputAction.done,
                  maxLength: kMaxBioLength,
                  enabled: !isSaving,
                  onChanged: (_) =>
                      ref.read(profileControllerProvider.notifier).clearError(),
                ),
                // El handle no se edita: cambiarlo obliga a liberar el anterior
                // y reclamar el nuevo en una transacción del servidor, y rompe
                // los enlaces @handle que otras personas ya compartieron.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.alternate_email_rounded),
                  title: Text(user.displayHandle),
                  subtitle: const Text(
                    'El nombre de usuario no se puede cambiar por ahora.',
                  ),
                ),
                const SizedBox(height: AscendSpacing.xl),
                AscendButton(
                  label: 'Guardar cambios',
                  isLoading: isSaving,
                  onPressed: isSaving ? null : () => _save(user.uid),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
