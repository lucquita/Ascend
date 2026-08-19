import 'package:ascend_ui/src/theme/ascend_theme.dart';
import 'package:ascend_ui/src/tokens/ascend_tokens.dart';
import 'package:flutter/material.dart';

/// Jerarquía visual de un botón.
enum AscendButtonVariant {
  /// Acción principal de la pantalla. Solo una por pantalla.
  primary,

  /// Acción secundaria, con borde.
  secondary,

  /// Acción terciaria, sin fondo ni borde.
  ghost,

  /// Acción destructiva (eliminar, cerrar cuenta).
  destructive,
}

/// Botón de Ascend.
///
/// Envuelve los botones de Material para incorporar el estado de carga, que en
/// esta app no es opcional: casi toda acción va contra la red y dejar el botón
/// activo mientras se procesa produce escrituras duplicadas.
///
/// Mientras [isLoading] es `true` el botón queda deshabilitado y conserva su
/// ancho, así que la pantalla no salta.
class AscendButton extends StatelessWidget {
  /// Crea un botón de acción principal.
  const AscendButton({
    required this.label,
    required this.onPressed,
    this.variant = AscendButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    super.key,
  });

  /// Constructor abreviado para la variante secundaria.
  const AscendButton.secondary({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    super.key,
  }) : variant = AscendButtonVariant.secondary;

  /// Constructor abreviado para la variante sin fondo.
  const AscendButton.ghost({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = false,
    super.key,
  }) : variant = AscendButtonVariant.ghost;

  /// Constructor abreviado para acciones destructivas.
  const AscendButton.destructive({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    super.key,
  }) : variant = AscendButtonVariant.destructive;

  /// Texto del botón.
  final String label;

  /// Acción. `null` deja el botón deshabilitado.
  final VoidCallback? onPressed;

  /// Jerarquía visual.
  final AscendButtonVariant variant;

  /// Icono opcional a la izquierda del texto.
  final IconData? icon;

  /// Si está procesando: muestra indicador y bloquea la pulsación.
  final bool isLoading;

  /// Si ocupa todo el ancho disponible.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;
    final child = _buildChild(context);

    final button = switch (variant) {
      AscendButtonVariant.primary => FilledButton(
        onPressed: effectiveOnPressed,
        child: child,
      ),
      AscendButtonVariant.secondary => OutlinedButton(
        onPressed: effectiveOnPressed,
        child: child,
      ),
      AscendButtonVariant.ghost => TextButton(
        onPressed: effectiveOnPressed,
        child: child,
      ),
      AscendButtonVariant.destructive => FilledButton(
        onPressed: effectiveOnPressed,
        style: FilledButton.styleFrom(
          backgroundColor: context.colors.error,
          foregroundColor: context.colors.onError,
        ),
        child: child,
      ),
    };

    return Semantics(
      button: true,
      enabled: effectiveOnPressed != null,
      label: label,
      child: expanded
          ? SizedBox(width: double.infinity, child: button)
          : button,
    );
  }

  Widget _buildChild(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: variant == AscendButtonVariant.primary
              ? context.colors.onPrimary
              : context.colors.primary,
        ),
      );
    }

    if (icon == null) {
      return Text(label);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20),
        const SizedBox(width: AscendSpacing.sm),
        Text(label),
      ],
    );
  }
}
