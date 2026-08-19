import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';

/// Encabezado de una sección del panel.
class AdminSectionHeader extends StatelessWidget {
  /// Crea el encabezado.
  const AdminSectionHeader({
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    super.key,
  });

  /// Título.
  final String title;

  /// Explicación breve.
  final String? subtitle;

  /// Botones de la derecha.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AscendSpacing.lg),
    // `Wrap` y no `Row`: con el menú lateral fijo, un título largo más dos
    // botones desbordan a 1024px y Flutter pinta la franja amarilla.
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AscendSpacing.lg,
      runSpacing: AscendSpacing.md,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title, style: context.texts.headlineSmall),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: AscendSpacing.xxs),
              Text(
                subtitle!,
                style: context.texts.bodySmall?.copyWith(
                  color: context.ascend.textSecondary,
                ),
              ),
            ],
          ],
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: AscendSpacing.sm, children: actions),
      ],
    ),
  );
}

/// Tarjeta neutra del panel.
class AdminCard extends StatelessWidget {
  /// Crea la tarjeta.
  const AdminCard({required this.child, this.padding, super.key});

  /// Contenido.
  final Widget child;

  /// Relleno interno.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(AscendSpacing.lg),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AscendRadius.lg),
      border: Border.all(color: context.colors.outlineVariant),
    ),
    child: child,
  );
}

/// Etiqueta de estado con color.
class AdminBadge extends StatelessWidget {
  /// Crea la etiqueta.
  const AdminBadge({required this.label, required this.color, super.key});

  /// Texto.
  final String label;

  /// Color de acento.
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AscendSpacing.sm,
      vertical: AscendSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AscendRadius.full),
    ),
    child: Text(
      label,
      style: context.texts.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Contenedor con scroll horizontal para tablas anchas.
///
/// Sin esto, una tabla más ancha que la ventana provoca un desbordamiento de
/// layout —la franja amarilla— en vez de poder desplazarse. Pasa siempre en la
/// primera pantalla angosta que alguien abre.
///
/// Fija un **ancho exacto**, no un mínimo. Un `ConstrainedBox(minWidth:)`
/// dentro de un scroll horizontal deja `maxWidth` en infinito, y cualquier
/// `Expanded` de las filas revienta con "RenderFlex children have non-zero flex
/// but incoming width constraints are unbounded".
class AdminScrollableTable extends StatelessWidget {
  /// Crea el contenedor.
  const AdminScrollableTable({
    required this.child,
    this.minWidth = 720,
    super.key,
  });

  /// Tabla.
  final Widget child;

  /// Ancho mínimo antes de empezar a desplazarse.
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) =>
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth < minWidth
                ? minWidth
                : constraints.maxWidth,
            child: child,
          ),
        ),
  );
}

/// Pide por escrito el motivo de una acción grave.
///
/// Devuelve el texto, o `null` si se canceló.
///
/// Es un widget con estado y no un `showDialog` con un controlador suelto: un
/// `TextEditingController` creado afuera hay que destruirlo a mano, y hacerlo
/// al cerrarse el diálogo lo destruye **mientras el `TextField` sigue vivo**
/// durante la animación de salida. El síntoma es un fallo de aserción del
/// framework (`_dependents.isEmpty`) que aparece un rato después y no señala a
/// la causa. Dentro de un `State`, `dispose()` corre en el momento correcto.
Future<String?> showAdminReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) => showDialog<String>(
  context: context,
  builder: (BuildContext context) =>
      _ReasonDialog(title: title, message: message, confirmLabel: confirmLabel),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.message, style: context.texts.bodyMedium),
          const SizedBox(height: AscendSpacing.md),
          AscendTextField(
            controller: _reason,
            label: 'Motivo',
            hint: 'Acoso reiterado tras dos advertencias',
            maxLines: 3,
            minLines: 2,
            autofocus: true,
            helperText: 'Queda en el registro de auditoría.',
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: context.colors.error),
        onPressed: () => Navigator.of(context).pop(_reason.text),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
