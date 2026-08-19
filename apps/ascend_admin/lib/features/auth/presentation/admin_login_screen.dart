import 'package:ascend_admin/features/auth/application/admin_session.dart';
import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Acceso al panel.
///
/// No tiene alta de cuenta ni acceso con Google: el backoffice se entra con una
/// cuenta que ya existe y a la que otro administrador le asignó el rol. Un
/// botón de "crear cuenta" acá sería una puerta pública al panel interno.
class AdminLoginScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  String? _emailError;
  String? _passwordError;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Valida en el cliente antes de gastar una llamada a Auth.
  ///
  /// No reemplaza la validación del servidor: la adelanta, para que un email
  /// mal escrito se corrija sin esperar un viaje de red.
  bool _validate(BuildContext context) {
    final email = Validators.email(_email.text).failureOrNull;
    final hasPassword = _password.text.isNotEmpty;
    setState(() {
      _emailError = email == null
          ? null
          : AscendFailureMessages.of(context)(context, email);
      _passwordError = hasPassword ? null : 'Escribí tu contraseña.';
    });
    return email == null && hasPassword;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_validate(context)) {
      return;
    }
    // El router redirige solo al detectar la sesión: no hace falta navegar acá.
    await ref
        .read(adminAuthControllerProvider.notifier)
        .signIn(email: _email.text.trim(), password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminAuthControllerProvider);
    final isBusy = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AscendSpacing.lg),
          child: ContentContainer(
            maxWidth: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.trending_up_rounded,
                      color: context.colors.primary,
                      size: 32,
                    ),
                    const SizedBox(width: AscendSpacing.sm),
                    Text('Ascend', style: context.texts.headlineSmall),
                  ],
                ),
                const SizedBox(height: AscendSpacing.xs),
                Text(
                  'Panel de administración',
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.ascend.textSecondary,
                  ),
                ),
                const SizedBox(height: AscendSpacing.xl),
                if (failure != null) ...<Widget>[
                  ErrorStateView(failure: failure, compact: true),
                  const SizedBox(height: AscendSpacing.lg),
                ],
                AscendTextField(
                  controller: _email,
                  label: 'Email',
                  prefixIcon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.email],
                  errorText: _emailError,
                  enabled: !isBusy,
                  autofocus: true,
                  onChanged: (_) {
                    ref.read(adminAuthControllerProvider.notifier).clearError();
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                ),
                AscendTextField(
                  controller: _password,
                  label: 'Contraseña',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscure: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.password],
                  errorText: _passwordError,
                  enabled: !isBusy,
                  suffix: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                  ),
                  onChanged: (_) {
                    ref.read(adminAuthControllerProvider.notifier).clearError();
                    if (_passwordError != null) {
                      setState(() => _passwordError = null);
                    }
                  },
                  onSubmitted: (_) => isBusy ? null : _submit(),
                ),
                const SizedBox(height: AscendSpacing.lg),
                AscendButton(
                  label: 'Entrar',
                  isLoading: isBusy,
                  onPressed: isBusy ? null : _submit,
                ),
                const SizedBox(height: AscendSpacing.lg),
                Text(
                  'El acceso requiere una cuenta con rol de administrador. '
                  'Se solicita a otro administrador desde este mismo panel.',
                  textAlign: TextAlign.center,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.ascend.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla para una sesión válida que no puede administrar.
///
/// Existe separada del login porque el problema es distinto y la salida
/// también: acá volver a escribir la contraseña no sirve de nada. Lo único que
/// se puede hacer es salir y entrar con otra cuenta.
class AdminUnauthorizedScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const AdminUnauthorizedScreen({required this.reason, super.key});

  /// Por qué no puede entrar.
  final AdminSessionState reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuspended = reason == AdminSessionState.suspended;

    return Scaffold(
      body: Center(
        child: ContentContainer(
          maxWidth: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isSuspended
                    ? Icons.pause_circle_outline_rounded
                    : Icons.gpp_bad_rounded,
                size: 64,
                color: context.colors.error,
              ),
              const SizedBox(height: AscendSpacing.lg),
              Text(
                isSuspended ? 'Cuenta suspendida' : 'Acceso restringido',
                style: context.texts.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AscendSpacing.sm),
              Text(
                isSuspended
                    ? 'Esta cuenta está suspendida y no puede administrar '
                          'nada mientras lo esté.'
                    : 'Tu cuenta no tiene rol de administrador. Pedile a un '
                          'administrador que te lo asigne.',
                style: context.texts.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AscendSpacing.xl),
              AscendButton.secondary(
                label: 'Salir',
                icon: Icons.logout_rounded,
                onPressed: () =>
                    ref.read(adminAuthControllerProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
