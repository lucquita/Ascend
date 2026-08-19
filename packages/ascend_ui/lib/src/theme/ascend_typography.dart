import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tipografía de Ascend: Poppins en seis roles.
///
/// Hoy la fuente se resuelve con `google_fonts`, que la descarga la primera
/// vez. Está registrado como deuda técnica de Fase 9 empaquetar los `.ttf`
/// como assets: depender de la red en el arranque en frío es inaceptable en
/// una app que tiene que funcionar offline.
abstract final class AscendTypography {
  /// Familia tipográfica de la marca.
  static const String fontFamily = 'Poppins';

  /// Construye el [TextTheme] completo para un color de texto dado.
  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
  }) {
    TextStyle style(
      double size,
      FontWeight weight, {
      Color? color,
      double? height,
    }) => GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color ?? primary,
      height: height,
    );

    return TextTheme(
      // Display — números grandes de Aura, celebraciones.
      displayLarge: style(40, FontWeight.w600, height: 1.15),
      displayMedium: style(32, FontWeight.w600, height: 1.2),
      displaySmall: style(28, FontWeight.w600, height: 1.2),
      // Headline — títulos de pantalla.
      headlineLarge: style(28, FontWeight.w600, height: 1.25),
      headlineMedium: style(24, FontWeight.w600, height: 1.3),
      headlineSmall: style(20, FontWeight.w600, height: 1.3),
      // Title — títulos de tarjeta y sección.
      titleLarge: style(20, FontWeight.w500, height: 1.35),
      titleMedium: style(16, FontWeight.w500, height: 1.4),
      titleSmall: style(14, FontWeight.w500, height: 1.4),
      // Body — texto corrido.
      bodyLarge: style(16, FontWeight.w400, height: 1.5),
      bodyMedium: style(14, FontWeight.w400, height: 1.5, color: secondary),
      bodySmall: style(12, FontWeight.w400, height: 1.45, color: secondary),
      // Label — botones y etiquetas.
      labelLarge: style(16, FontWeight.w500, height: 1.2),
      labelMedium: style(14, FontWeight.w500, height: 1.2),
      labelSmall: style(12, FontWeight.w500, height: 1.2, color: secondary),
    );
  }
}
