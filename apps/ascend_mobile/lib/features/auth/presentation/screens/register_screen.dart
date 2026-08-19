import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_mobile/features/auth/application/auth_controller.dart';
import 'package:ascend_mobile/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Creación de cuenta.
class RegisterScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _handle = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();

  final Debouncer _handleDebouncer = Debouncer(
    duration: const Duration(milliseconds: 400),
  );

  String _handleQuery = '';
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _handleDebouncer.dispose();
    _name.dispose();
    _handle.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  /// Consulta la disponibilidad con retardo.
  ///
  /// Sin el debounce se dispararía una lectura de Firestore por cada tecla:
  /// veinte lecturas para escribir un nombre de usuario, multiplicado por cada
  /// persona que se registra.
  void _onHandleChanged(String value) {
    ref.read(authControllerProvider.notifier).clearError();
    _handleDebouncer.run(() {
      if (mounted) {
        setState(() => _handleQuery = value.trim().toLowerCase());
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref
        .read(authControllerProvider.notifier)
        .signUp(
          email: _email.text,
          password: _password.text,
          passwordConfirmation: _confirmation.text,
          displayName: _name.text,
          handle: _handle.text,
          acceptedTerms: _acceptedTerms,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final isLoading = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;

    final handleCheck = _handleQuery.length >= 3
        ? ref.watch(handleAvailabilityProvider(_handleQuery))
        : null;

    return AuthScaffold(
      title: 'Creá tu cuenta',
      subtitle: 'Un minuto ahora, y arrancás con tu primer objetivo.',
      children: <Widget>[
        if (failure != null) AuthErrorBanner(failure: failure),
        AuthField(
          controller: _name,
          label: 'Tu nombre',
          prefixIcon: Icons.person_outline_rounded,
          autofillHints: const <String>[AutofillHints.name],
          maxLength: Validators.maxDisplayNameLength,
          enabled: !isLoading,
          autofocus: true,
          onChanged: (_) =>
              ref.read(authControllerProvider.notifier).clearError(),
        ),
        AuthField(
          controller: _handle,
          label: 'Nombre de usuario',
          hint: 'santino',
          prefixIcon: Icons.alternate_email_rounded,
          maxLength: 20,
          enabled: !isLoading,
          helperText: _handleHelper(handleCheck),
          suffix: _handleSuffix(handleCheck),
          onChanged: _onHandleChanged,
        ),
        AuthField(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          prefixIcon: Icons.mail_outline_rounded,
          enabled: !isLoading,
          onChanged: (_) =>
              ref.read(authControllerProvider.notifier).clearError(),
        ),
        PasswordField(
          controller: _password,
          label: 'Contraseña',
          helperText: 'Al menos 8 caracteres, con letras y números.',
          autofillHints: const <String>[AutofillHints.newPassword],
          enabled: !isLoading,
          onChanged: (_) =>
              ref.read(authControllerProvider.notifier).clearError(),
        ),
        PasswordField(
          controller: _confirmation,
          label: 'Repetí la contraseña',
          textInputAction: TextInputAction.done,
          enabled: !isLoading,
          onChanged: (_) =>
              ref.read(authControllerProvider.notifier).clearError(),
          onSubmitted: (_) => _submit(),
        ),
        CheckboxListTile(
          value: _acceptedTerms,
          onChanged: isLoading
              ? null
              : (value) => setState(() => _acceptedTerms = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Acepto los términos y la política de privacidad.',
            style: context.texts.bodySmall,
          ),
        ),
        const SizedBox(height: AscendSpacing.lg),
        AscendButton(
          label: 'Crear cuenta',
          isLoading: isLoading,
          onPressed: isLoading ? null : _submit,
        ),
      ],
    );
  }

  String? _handleHelper(AsyncValue<bool>? check) {
    if (_handleQuery.isEmpty) {
      return 'Así te van a encontrar: @tuNombre';
    }
    return switch (check) {
      AsyncData<bool>(value: true) => '@$_handleQuery está disponible',
      AsyncData<bool>(value: false) => '@$_handleQuery ya está en uso',
      _ => 'Comprobando disponibilidad…',
    };
  }

  Widget? _handleSuffix(AsyncValue<bool>? check) => switch (check) {
    AsyncData<bool>(value: true) => Icon(
      Icons.check_circle_rounded,
      color: context.ascend.success,
    ),
    AsyncData<bool>(value: false) => Icon(
      Icons.cancel_rounded,
      color: context.colors.error,
    ),
    AsyncLoading<bool>() => const Padding(
      padding: EdgeInsets.all(AscendSpacing.md),
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
    _ => null,
  };
}
