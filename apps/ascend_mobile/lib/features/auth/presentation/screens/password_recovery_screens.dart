import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_mobile/features/auth/application/auth_controller.dart';
import 'package:ascend_mobile/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Solicitud del correo de recuperación de contraseña.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final TextEditingController _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final sent = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(_email.text);
    if (sent && mounted) {
      context.go(Routes.resetSent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final isLoading = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;

    return AuthScaffold(
      title: 'Recuperar contraseña',
      subtitle:
          'Escribí tu email y te mandamos un enlace para elegir una nueva.',
      children: <Widget>[
        if (failure != null) AuthErrorBanner(failure: failure),
        AuthField(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.email],
          prefixIcon: Icons.mail_outline_rounded,
          enabled: !isLoading,
          autofocus: true,
          onChanged: (_) =>
              ref.read(authControllerProvider.notifier).clearError(),
          onSubmitted: (_) => _submit(),
        ),
        AscendButton(
          label: 'Enviar enlace',
          isLoading: isLoading,
          onPressed: isLoading ? null : _submit,
        ),
      ],
    );
  }
}

/// Confirmación de que el correo de recuperación salió.
///
/// El mensaje es deliberadamente ambiguo respecto de si el email existe. Decir
/// "no encontramos esa cuenta" convertiría la pantalla en un verificador de
/// qué direcciones están registradas en Ascend.
class ResetSentScreen extends StatelessWidget {
  /// Crea la pantalla.
  const ResetSentScreen({super.key});

  @override
  Widget build(BuildContext context) => AuthScaffold(
    title: 'Revisá tu correo',
    subtitle:
        'Si ese email tiene una cuenta en Ascend, va a recibir un enlace para '
        'cambiar la contraseña. Puede tardar un par de minutos, y a veces cae '
        'en correo no deseado.',
    children: <Widget>[
      const SizedBox(height: AscendSpacing.lg),
      AscendButton(
        label: 'Volver al inicio de sesión',
        onPressed: () => context.go(Routes.login),
      ),
    ],
  );
}

/// Espera de la verificación de email.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _justResent = false;

  Future<void> _resend() async {
    final sent = await ref
        .read(authControllerProvider.notifier)
        .sendEmailVerification();
    if (sent && mounted) {
      setState(() => _justResent = true);
    }
  }

  /// Relee el usuario para ver si ya verificó.
  ///
  /// Hace falta un refresco explícito: `emailVerified` no se actualiza solo en
  /// el cliente cuando alguien hace clic en el enlace desde otro dispositivo.
  Future<void> _check() => ref.read(authControllerProvider.notifier).reload();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final isLoading = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;

    return AuthScaffold(
      title: 'Verificá tu email',
      subtitle:
          'Te mandamos un enlace de confirmación. Abrilo y volvé acá para '
          'seguir.',
      showBack: false,
      children: <Widget>[
        if (failure != null) AuthErrorBanner(failure: failure),
        if (_justResent)
          Container(
            margin: const EdgeInsets.only(bottom: AscendSpacing.lg),
            padding: const EdgeInsets.all(AscendSpacing.md),
            decoration: BoxDecoration(
              color: context.ascend.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AscendRadius.md),
            ),
            child: Text(
              'Listo, reenviamos el correo.',
              style: context.texts.bodySmall,
            ),
          ),
        AscendButton(
          label: 'Ya lo verifiqué',
          isLoading: isLoading,
          onPressed: isLoading ? null : _check,
        ),
        const SizedBox(height: AscendSpacing.md),
        AscendButton.secondary(
          label: 'Reenviar correo',
          onPressed: isLoading ? null : _resend,
        ),
        const SizedBox(height: AscendSpacing.xl),
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

/// Cuenta suspendida por moderación.
class BlockedScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AuthScaffold(
    title: 'Tu cuenta está suspendida',
    subtitle:
        'Se suspendió por incumplir las normas de la comunidad. Si creés que '
        'es un error, escribinos y lo revisamos.',
    showBack: false,
    children: <Widget>[
      const SizedBox(height: AscendSpacing.lg),
      AscendButton.secondary(
        label: 'Cerrar sesión',
        onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
      ),
    ],
  );
}
