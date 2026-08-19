import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';

/// Contenido provisional de una sección del panel.
///
/// Igual que en la app móvil, existe para que la Fase 0 sea verificable: se
/// recorre todo el panel, se comprueba el comportamiento responsive y el tema
/// oscuro antes de escribir la primera tabla real.
class AdminPlaceholder extends StatelessWidget {
  /// Crea el contenido provisional.
  const AdminPlaceholder({
    required this.title,
    required this.description,
    this.phase,
    this.icon = Icons.construction_rounded,
    this.standalone = false,
    super.key,
  });

  /// Nombre de la sección.
  final String title;

  /// Qué hará cuando esté implementada.
  final String description;

  /// Fase del roadmap en la que se completa.
  final String? phase;

  /// Icono de la sección.
  final IconData icon;

  /// Si se muestra fuera del shell (login, acceso denegado).
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ContentContainer(
        maxWidth: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: context.colors.primary),
            ),
            const SizedBox(height: AscendSpacing.xl),
            Text(
              title,
              style: context.texts.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AscendSpacing.sm),
            Text(
              description,
              style: context.texts.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (phase != null) ...<Widget>[
              const SizedBox(height: AscendSpacing.xl),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AscendSpacing.md,
                  vertical: AscendSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: context.ascend.aura.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AscendRadius.full),
                ),
                child: Text(
                  'Se implementa en la $phase',
                  style: context.texts.labelSmall?.copyWith(
                    color: context.ascend.auraOnSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return standalone ? Scaffold(body: content) : content;
  }
}
