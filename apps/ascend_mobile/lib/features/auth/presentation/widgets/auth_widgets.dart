import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';

/// Estructura común de las pantallas de cuenta.
///
/// Centra el contenido y le pone un ancho máximo: en una tablet o en la web un
/// formulario de 900px de ancho es ilegible, y esta app corre en las tres.
class AuthScaffold extends StatelessWidget {
  /// Crea la estructura.
  const AuthScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.showBack = true,
    super.key,
  });

  /// Título grande de la pantalla.
  final String title;

  /// Explicación breve debajo del título.
  final String? subtitle;

  /// Contenido del formulario.
  final List<Widget> children;

  /// Si se muestra la flecha de volver.
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: showBack,
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AscendSpacing.xl,
            vertical: AscendSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(title, style: context.texts.headlineMedium),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: AscendSpacing.sm),
                  Text(
                    subtitle!,
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AscendSpacing.xl),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Campo de texto de Ascend con validación en línea.
class AuthField extends StatelessWidget {
  /// Crea el campo.
  const AuthField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.prefixIcon,
    this.suffix,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.autofocus = false,
    this.obscure = false,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  /// Controlador del texto.
  final TextEditingController controller;

  /// Etiqueta.
  final String label;

  /// Texto de ayuda dentro del campo.
  final String? hint;

  /// Tipo de teclado.
  final TextInputType? keyboardType;

  /// Acción del teclado.
  final TextInputAction textInputAction;

  /// Pistas de autocompletado del sistema.
  final Iterable<String>? autofillHints;

  /// Icono inicial.
  final IconData? prefixIcon;

  /// Widget al final del campo.
  final Widget? suffix;

  /// Mensaje de error bajo el campo.
  final String? errorText;

  /// Mensaje de ayuda bajo el campo.
  final String? helperText;

  /// Si el campo acepta edición.
  final bool enabled;

  /// Si toma el foco al abrir la pantalla.
  final bool autofocus;

  /// Si el texto se muestra oculto.
  final bool obscure;

  /// Longitud máxima.
  final int? maxLength;

  /// Se dispara en cada cambio.
  final ValueChanged<String>? onChanged;

  /// Se dispara al confirmar desde el teclado.
  final ValueChanged<String>? onSubmitted;

  // El campo se promovió al design system como `AscendTextField` cuando el
  // alta de objetivos lo necesitó. Este widget queda como envoltorio para no
  // tocar las pantallas de la Fase 1 ni sus tests, pero ya no duplica nada.
  @override
  Widget build(BuildContext context) => AscendTextField(
    controller: controller,
    label: label,
    hint: hint,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    autofillHints: autofillHints,
    prefixIcon: prefixIcon,
    suffix: suffix,
    errorText: errorText,
    helperText: helperText,
    enabled: enabled,
    autofocus: autofocus,
    obscure: obscure,
    maxLength: maxLength,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
}

/// Campo de contraseña con alternancia de visibilidad.
///
/// Poder ver lo que se escribe reduce errores de tipeo, que es la causa número
/// uno de los "no me anda la contraseña".
class PasswordField extends StatefulWidget {
  /// Crea el campo.
  const PasswordField({
    required this.controller,
    required this.label,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  /// Controlador del texto.
  final TextEditingController controller;

  /// Etiqueta.
  final String label;

  /// Mensaje de error.
  final String? errorText;

  /// Mensaje de ayuda.
  final String? helperText;

  /// Si acepta edición.
  final bool enabled;

  /// Acción del teclado.
  final TextInputAction textInputAction;

  /// Pistas de autocompletado.
  final Iterable<String>? autofillHints;

  /// Se dispara en cada cambio.
  final ValueChanged<String>? onChanged;

  /// Se dispara al confirmar.
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) => AuthField(
    controller: widget.controller,
    label: widget.label,
    errorText: widget.errorText,
    helperText: widget.helperText,
    enabled: widget.enabled,
    textInputAction: widget.textInputAction,
    autofillHints: widget.autofillHints,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    prefixIcon: Icons.lock_outline_rounded,
    suffix: IconButton(
      onPressed: () => setState(() => _obscured = !_obscured),
      icon: Icon(
        _obscured ? Icons.visibility_rounded : Icons.visibility_off_rounded,
      ),
      tooltip: _obscured ? 'Mostrar contraseña' : 'Ocultar contraseña',
    ),
    obscure: _obscured,
  );
}

/// Aviso de error de una acción, en línea con el formulario.
///
/// No usa un `SnackBar`: un mensaje que se va solo a los 4 segundos obliga a
/// leer rápido y desaparece justo cuando la persona vuelve a mirar el campo.
class AuthErrorBanner extends StatelessWidget {
  /// Crea el aviso.
  const AuthErrorBanner({required this.failure, super.key});

  /// Fallo a comunicar.
  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final display = AscendFailureMessages.describe(failure);
    return Container(
      margin: const EdgeInsets.only(bottom: AscendSpacing.lg),
      padding: const EdgeInsets.all(AscendSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.errorContainer,
        borderRadius: BorderRadius.circular(AscendRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: context.colors.onErrorContainer,
          ),
          const SizedBox(width: AscendSpacing.md),
          Expanded(
            child: Text(
              display.message,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
