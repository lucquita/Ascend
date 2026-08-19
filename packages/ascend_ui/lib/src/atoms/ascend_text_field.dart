import 'package:ascend_ui/src/tokens/ascend_tokens.dart';
import 'package:flutter/material.dart';

/// Campo de texto del design system.
///
/// Nació dentro de la feature de autenticación como `AuthField`. Al necesitarlo
/// también el alta de objetivos se promovió acá, que es donde el documento de
/// arquitectura lo ubicaba desde el principio (`ascend_ui/atoms`). `AuthField`
/// se mantiene como envoltorio para no tocar las pantallas de la Fase 1 ni sus
/// tests, pero ya no duplica nada: delega en este widget.
class AscendTextField extends StatelessWidget {
  /// Crea el campo.
  const AscendTextField({
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
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  /// Controlador del texto.
  final TextEditingController controller;

  /// Etiqueta flotante.
  final String label;

  /// Texto de ejemplo.
  final String? hint;

  /// Tipo de teclado.
  final TextInputType? keyboardType;

  /// Acción del teclado.
  final TextInputAction textInputAction;

  /// Pistas de autocompletado del sistema.
  final Iterable<String>? autofillHints;

  /// Icono a la izquierda.
  final IconData? prefixIcon;

  /// Widget a la derecha.
  final Widget? suffix;

  /// Mensaje de error bajo el campo.
  final String? errorText;

  /// Mensaje de ayuda bajo el campo.
  final String? helperText;

  /// Si acepta edición.
  final bool enabled;

  /// Si toma el foco al aparecer.
  final bool autofocus;

  /// Si oculta el texto.
  final bool obscure;

  /// Máximo de caracteres.
  ///
  /// El contador nativo se oculta: ocupa una línea permanente y desplaza el
  /// layout. El límite se comunica en el `helperText` cuando importa.
  final int? maxLength;

  /// Máximo de líneas. `null` deja crecer sin techo.
  final int? maxLines;

  /// Mínimo de líneas visibles.
  final int? minLines;

  /// Se dispara en cada cambio.
  final ValueChanged<String>? onChanged;

  /// Se dispara al confirmar.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AscendSpacing.lg),
    child: TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscure,
      maxLength: maxLength,
      // Un campo multilínea con `obscureText` no compila en Flutter; obscure
      // solo se usa en contraseñas, que siempre son de una línea.
      maxLines: obscure ? 1 : maxLines,
      minLines: minLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        helperText: helperText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffix,
        counterText: '',
      ),
    ),
  );
}
