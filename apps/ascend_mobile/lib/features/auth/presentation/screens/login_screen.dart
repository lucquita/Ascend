import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_mobile/features/auth/application/auth_controller.dart';
import 'package:ascend_mobile/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Inicio de sesión con email y contraseña.
class LoginScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Se cierra el teclado antes de la llamada: si no, el error aparece tapado.
    FocusScope.of(context).unfocus();
    await ref
        .read(authControllerProvider.notifier)
        .signIn(email: _email.text, password: _password.text);
    // No se navega a mano: al abrirse la sesión cambia `sessionStateProvider` y
    // el `redirect` del router lleva a donde corresponda. Empujar una ruta acá
    // competiría con el guard y produciría parpadeos.
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final isLoading = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;

    return AuthScaffold(
      title: 'Iniciar sesión',
      subtitle: 'Volvé a donde dejaste. Tu progreso te está esperando.',
      showBack: false,
      children: <Widget>[
        if (failure != null) AuthErrorBanner(failure: failure),
        AutofillGroup(
          child: Column(
            children: <Widget>[
              AuthField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                autofillHints: const <String>[AutofillHints.email],
                prefixIcon: Icons.mail_outline_rounded,
                enabled: !isLoading,
                autofocus: true,
                onChanged: (_) =>
                    ref.read(authControllerProvider.notifier).clearError(),
              ),
              PasswordField(
                controller: _password,
                label: 'Contraseña',
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.password],
                enabled: !isLoading,
                onChanged: (_) =>
                    ref.read(authControllerProvider.notifier).clearError(),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: isLoading
                ? null
                : () => context.push(Routes.forgotPassword),
            child: const Text('¿Olvidaste tu contraseña?'),
          ),
        ),
        const SizedBox(height: AscendSpacing.md),
        AscendButton(
          label: 'Entrar',
          isLoading: isLoading,
          onPressed: isLoading ? null : _submit,
        ),
        const SizedBox(height: AscendSpacing.xl),
        // `Wrap` y no `Row`: con el texto escalado a 1.5x por accesibilidad, la
        // frase más el botón no entran en una línea y un `Row` desborda.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text('¿Todavía no tenés cuenta?', style: context.texts.bodyMedium),
            TextButton(
              onPressed: isLoading ? null : () => context.push(Routes.register),
              child: const Text('Creá una'),
            ),
          ],
        ),
      ],
    );
  }
}
