import 'package:ascend_ui/src/theme/ascend_theme.dart';
import 'package:ascend_ui/src/tokens/ascend_tokens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Bloque gris con efecto shimmer que ocupa el lugar del contenido real.
///
/// Ascend no usa spinners a pantalla completa. Un skeleton con la forma del
/// contenido que viene hace que la espera se perciba más corta y evita el salto
/// de layout cuando llegan los datos.
class AscendSkeleton extends StatelessWidget {
  /// Crea un bloque de carga con dimensiones explícitas.
  const AscendSkeleton({
    this.width,
    this.height = 16,
    this.borderRadius = AscendRadius.sm,
    super.key,
  });

  /// Skeleton con forma de línea de texto.
  const AscendSkeleton.text({double width = double.infinity, Key? key})
    : this(width: width, height: 14, key: key);

  /// Skeleton circular, para avatares.
  const AscendSkeleton.circle({double size = 40, Key? key})
    : this(
        width: size,
        height: size,
        borderRadius: AscendRadius.full,
        key: key,
      );

  /// Ancho del bloque. `null` ocupa todo el disponible.
  final double? width;

  /// Alto del bloque.
  final double height;

  /// Radio de las esquinas.
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final ascend = context.ascend;
    return Shimmer.fromColors(
      baseColor: ascend.skeletonBase,
      highlightColor: ascend.skeletonHighlight,
      period: AscendDurations.shimmer,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: ascend.skeletonBase,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Lista de skeletons con la forma de una tarjeta de Ascend.
class AscendSkeletonList extends StatelessWidget {
  /// Crea una lista de placeholders.
  const AscendSkeletonList({
    this.itemCount = 5,
    this.hasLeading = true,
    super.key,
  });

  /// Cuántos placeholders mostrar.
  final int itemCount;

  /// Si cada fila lleva un círculo a la izquierda (avatar o icono).
  final bool hasLeading;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: AscendSpacing.screen,
    physics: const NeverScrollableScrollPhysics(),
    // `shrinkWrap` porque esta lista **nunca** scrollea —ya lo dice el
    // `physics`— y aparece con frecuencia dentro de otro scrollable: sin él,
    // Flutter lanza "Vertical viewport was given unbounded height" y la
    // pantalla de carga revienta. Con un `itemCount` de placeholders el costo
    // de construir todos los hijos de una es irrelevante.
    shrinkWrap: true,
    itemCount: itemCount,
    separatorBuilder: (_, _) => const SizedBox(height: AscendSpacing.md),
    itemBuilder: (_, _) => Container(
      padding: AscendSpacing.card,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AscendRadius.cardRadius,
        border: Border.all(color: context.colors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (hasLeading) ...<Widget>[
            const AscendSkeleton.circle(),
            const SizedBox(width: AscendSpacing.lg),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AscendSkeleton.text(width: 160),
                SizedBox(height: AscendSpacing.sm),
                AscendSkeleton.text(),
                SizedBox(height: AscendSpacing.xs),
                AscendSkeleton.text(width: 220),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
