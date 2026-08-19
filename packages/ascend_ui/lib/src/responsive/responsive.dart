import 'package:ascend_ui/src/tokens/ascend_tokens.dart';
import 'package:flutter/widgets.dart';

/// Tamaño de pantalla según los breakpoints de Ascend.
enum ScreenSize {
  /// Teléfono.
  mobile,

  /// Tablet o ventana angosta.
  tablet,

  /// Escritorio.
  desktop;

  /// `true` si no es un teléfono.
  bool get isWide => this != ScreenSize.mobile;
}

/// Construye distinto según el ancho disponible.
///
/// Se apoya en el ancho del **contenedor**, no en el de la pantalla: dentro de
/// un panel lateral el contenido debe comportarse como móvil aunque la ventana
/// sea de escritorio.
class ResponsiveBuilder extends StatelessWidget {
  /// Crea un constructor responsive.
  const ResponsiveBuilder({required this.builder, super.key});

  /// Constructor que recibe el tamaño resuelto y las restricciones.
  final Widget Function(
    BuildContext context,
    ScreenSize size,
    BoxConstraints constraints,
  )
  builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        builder(context, sizeOf(constraints.maxWidth), constraints),
  );

  /// Resuelve el [ScreenSize] correspondiente a un ancho.
  static ScreenSize sizeOf(double width) {
    if (AscendBreakpoints.isMobile(width)) {
      return ScreenSize.mobile;
    }
    if (AscendBreakpoints.isTablet(width)) {
      return ScreenSize.tablet;
    }
    return ScreenSize.desktop;
  }
}

/// Elige un valor distinto por tamaño de pantalla.
class ResponsiveValue<T> {
  /// Crea el selector de valores responsive.
  const ResponsiveValue({required this.mobile, this.tablet, this.desktop});

  /// Valor en teléfono (obligatorio: diseñamos mobile-first).
  final T mobile;

  /// Valor en tablet. Si es `null` hereda el de teléfono.
  final T? tablet;

  /// Valor en escritorio. Si es `null` hereda el de tablet.
  final T? desktop;

  /// Resuelve el valor para el ancho dado.
  T resolve(double width) => switch (ResponsiveBuilder.sizeOf(width)) {
    ScreenSize.mobile => mobile,
    ScreenSize.tablet => tablet ?? mobile,
    ScreenSize.desktop => desktop ?? tablet ?? mobile,
  };

  /// Resuelve el valor usando el ancho de la ventana.
  T of(BuildContext context) => resolve(MediaQuery.sizeOf(context).width);
}

/// Limita el ancho del contenido y lo centra.
///
/// En una tablet o en la web, una columna de texto de 1200px es ilegible. Este
/// widget mantiene el contenido dentro de un ancho cómodo sin que cada pantalla
/// tenga que acordarse.
class ContentContainer extends StatelessWidget {
  /// Crea un contenedor de contenido con ancho máximo.
  const ContentContainer({
    required this.child,
    this.maxWidth = AscendBreakpoints.maxContentWidth,
    this.padding = AscendSpacing.screenHorizontal,
    super.key,
  });

  /// Contenido.
  final Widget child;

  /// Ancho máximo.
  final double maxWidth;

  /// Relleno horizontal.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}
