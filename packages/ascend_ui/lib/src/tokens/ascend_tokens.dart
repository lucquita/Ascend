import 'package:flutter/widgets.dart';

/// Escala de espaciado de 4pt.
///
/// Todo margen y padding de Ascend sale de acá. Prohibido escribir números
/// sueltos en los widgets: es lo que hace que una app se vea desprolija cuando
/// la tocan tres personas distintas.
abstract final class AscendSpacing {
  /// 2px — separaciones ópticas mínimas.
  static const double xxs = 2;

  /// 4px.
  static const double xs = 4;

  /// 8px.
  static const double sm = 8;

  /// 12px.
  static const double md = 12;

  /// 16px — el espaciado por defecto de la app.
  static const double lg = 16;

  /// 24px — separación entre bloques.
  static const double xl = 24;

  /// 32px.
  static const double xxl = 32;

  /// 48px — respiros grandes (estados vacíos, onboarding).
  static const double xxxl = 48;

  /// 64px.
  static const double huge = 64;

  /// Padding horizontal estándar de las pantallas.
  static const EdgeInsets screenHorizontal = EdgeInsets.symmetric(
    horizontal: lg,
  );

  /// Padding completo estándar de las pantallas.
  static const EdgeInsets screen = EdgeInsets.all(lg);

  /// Padding interno de una tarjeta.
  static const EdgeInsets card = EdgeInsets.all(lg);
}

/// Radios de esquina.
abstract final class AscendRadius {
  /// 8px — chips y elementos pequeños.
  static const double sm = 8;

  /// 12px — campos de texto y botones.
  static const double md = 12;

  /// 16px — tarjetas.
  static const double lg = 16;

  /// 24px — hojas modales.
  static const double xl = 24;

  /// Píldora / círculo.
  static const double full = 999;

  /// Radio de tarjeta ya construido.
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));

  /// Radio de botón ya construido.
  static const BorderRadius buttonRadius = BorderRadius.all(
    Radius.circular(md),
  );

  /// Radio de hoja modal (solo esquinas superiores).
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

/// Duraciones de animación.
///
/// Tres escalones y nada más. Una app se siente coherente cuando todo se mueve
/// al mismo ritmo.
abstract final class AscendDurations {
  /// 150ms — microinteracciones (presionar, marcar, cambiar de estado).
  static const Duration micro = Duration(milliseconds: 150);

  /// 250ms — transiciones entre pantallas y aparición de contenido.
  static const Duration transition = Duration(milliseconds: 250);

  /// 400ms — celebraciones: Aura ganada, subida de nivel.
  static const Duration celebration = Duration(milliseconds: 400);

  /// 1200ms — ciclo del efecto shimmer de los skeletons.
  static const Duration shimmer = Duration(milliseconds: 1200);
}

/// Curvas de animación.
abstract final class AscendCurves {
  /// Curva por defecto: entra rápido, frena suave.
  static const Curve standard = Curves.easeOutCubic;

  /// Para elementos que entran en pantalla.
  static const Curve enter = Curves.easeOutBack;

  /// Para elementos que salen.
  static const Curve exit = Curves.easeInCubic;
}

/// Puntos de quiebre responsive.
///
/// Los mismos valores rigen la app móvil y el panel web, por eso viven en el
/// design system y no en cada app.
abstract final class AscendBreakpoints {
  /// Por debajo de 600px: teléfono.
  static const double mobile = 600;

  /// Entre 600 y 1024px: tablet o ventana angosta.
  static const double tablet = 1024;

  /// Por encima de 1024px: escritorio (el admin muestra sidebar fija).
  static const double desktop = 1440;

  /// Ancho máximo del contenido legible: más allá, el texto cansa la vista.
  static const double maxContentWidth = 720;

  /// `true` si el ancho corresponde a un teléfono.
  static bool isMobile(double width) => width < mobile;

  /// `true` si el ancho corresponde a una tablet.
  static bool isTablet(double width) => width >= mobile && width < tablet;

  /// `true` si el ancho corresponde a escritorio.
  static bool isDesktop(double width) => width >= tablet;
}

/// Sombras.
///
/// Deliberadamente más suaves que las de Material por defecto: la estética que
/// buscamos (Linear, Notion) usa borde de 1px más una sombra apenas perceptible.
abstract final class AscendShadows {
  /// Sombra de tarjeta en reposo.
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Sombra de elemento elevado (menús, tarjetas activas).
  static const List<BoxShadow> elevated = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),
  ];

  /// Sombra de hoja modal.
  static const List<BoxShadow> sheet = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), blurRadius: 32, offset: Offset(0, -4)),
  ];
}
