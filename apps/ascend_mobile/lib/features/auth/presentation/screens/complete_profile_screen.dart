import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_mobile/features/auth/application/auth_controller.dart';
import 'package:ascend_mobile/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Completa el perfil de una cuenta que quedó a medio registrar.
///
/// El caso es real y no hipotético: se crea la cuenta en Firebase Auth, la
/// Function que escribe el perfil no llega a terminar —red cortada, app
/// cerrada— y queda una sesión válida sin perfil. Esa persona no puede volver a
/// registrarse, porque su email ya figura tomado por su propia cuenta.
///
/// Sin esta pantalla, el único camino sería borrar la cuenta desde la consola
/// de Firebase. Con ella, se recupera sola.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _handle = TextEditingController();

  AsyncValue<void> _state = const AsyncData<void>(null);

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final validName = Validators.displayName(_name.text);
    if (validName case Failed<String>(:final failure)) {
      setState(() => _state = AsyncError<void>(failure, StackTrace.empty));
      return;
    }
    final validHandle = Validators.handle(_handle.text);
    if (validHandle case Failed<String>(:final failure)) {
      setState(() => _state = AsyncError<void>(failure, StackTrace.empty));
      return;
    }

    setState(() => _state = const AsyncLoading<void>());

    // Se llama al mismo datasource que usa el registro: la Function es
    // idempotente justamente para poder reintentarla desde acá.
    final result = await runGuarded(
      () => ref
          .read(firebaseAuthDataSourceProvider)
          .registerProfile(
            displayName: validName.valueOrNull!,
            handle: validHandle.valueOrNull!,
          ),
    );

    if (!mounted) {
      return;
    }

    await result.fold(
      onSuccess: (_) async {
        // El claim de rol acaba de asignarse: sin refrescar el token, las
        // reglas de Firestore seguirían viendo una sesión sin rol.
        await ref.read(authRepositoryProvider).refreshToken();
        if (mounted) {
          setState(() => _state = const AsyncData<void>(null));
        }
      },
      onFailure: (failure) async {
        if (mounted) {
          setState(() => _state = AsyncError<void>(failure, StackTrace.empty));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _state.isLoading;
    final failure = _state.error is Failure ? _state.error! as Failure : null;

    return AuthScaffold(
      title: 'Falta poco',
      subtitle:
          'Tu cuenta se creó pero quedó sin perfil. Elegí cómo te vamos a '
          'mostrar y seguimos.',
      showBack: false,
      children: <Widget>[
        if (failure != null) AuthErrorBanner(failure: failure),
        AuthField(
          controller: _name,
          label: 'Tu nombre',
          prefixIcon: Icons.person_outline_rounded,
          maxLength: Validators.maxDisplayNameLength,
          enabled: !isLoading,
          autofocus: true,
        ),
        AuthField(
          controller: _handle,
          label: 'Nombre de usuario',
          prefixIcon: Icons.alternate_email_rounded,
          textInputAction: TextInputAction.done,
          maxLength: 20,
          enabled: !isLoading,
          onSubmitted: (_) => _submit(),
        ),
        AscendButton(
          label: 'Completar perfil',
          isLoading: isLoading,
          onPressed: isLoading ? null : _submit,
        ),
        const SizedBox(height: AscendSpacing.lg),
        Center(
          child: TextButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            child: const Text('Cerrar sesión'),
          ),
        ),
      ],
    );
  }
}
