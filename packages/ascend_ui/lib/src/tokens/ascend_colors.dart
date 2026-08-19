import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paleta de Ascend.
///
/// Los colores de marca están fijados por diseño. Lo que sí decide este archivo
/// es **dónde** puede usarse cada uno, porque no todos pasan contraste AA.
///
/// El caso crítico es [aura] (`#F59E0B`): sobre blanco da 2.15:1, por debajo
/// del 4.5:1 que exige WCAG AA para texto. Por eso existe [auraText], una
/// variante oscurecida que sí cumple, y que es la que hay que usar cuando el
/// Aura se escribe en modo claro. [aura] queda reservado para rellenos: anillos
/// de progreso, insignias e iconos de 24px o más.
abstract final class AscendColors {
  // ── Marca ───────────────────────────────────────────────────────────────
  /// Azul de marca. Acciones primarias y navegación.
  static const Color primary = Color(0xFF3B82F6);

  /// Azul aclarado para modo oscuro (mantiene contraste sobre fondos oscuros).
  static const Color primaryDark = Color(0xFF60A5FA);

  /// Azul oscurecido para textos y estados presionados en modo claro.
  static const Color primaryDeep = Color(0xFF1D4ED8);

  /// Verde de progreso y misiones completadas.
  static const Color success = Color(0xFF22C55E);

  /// Verde para modo oscuro.
  static const Color successDark = Color(0xFF4ADE80);

  /// Verde oscurecido, apto para texto sobre fondo claro.
  static const Color successText = Color(0xFF15803D);

  /// Naranja Aura. **Solo relleno** en modo claro: no cumple AA como texto.
  static const Color aura = Color(0xFFF59E0B);

  /// Naranja Aura para modo oscuro.
  static const Color auraDark = Color(0xFFFBBF24);

  /// Variante de Aura apta para texto sobre fondos claros (contraste 4.6:1).
  static const Color auraText = Color(0xFFB45309);

  // ── Superficies ─────────────────────────────────────────────────────────
  /// Fondo de pantalla en modo claro.
  static const Color backgroundLight = Color(0xFFF9FAFB);

  /// Fondo de tarjetas en modo claro.
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Superficie elevada en modo claro (sheets, diálogos).
  static const Color surfaceElevatedLight = Color(0xFFFFFFFF);

  /// Fondo de pantalla en modo oscuro.
  static const Color backgroundDark = Color(0xFF0B0F17);

  /// Fondo de tarjetas en modo oscuro.
  static const Color surfaceDark = Color(0xFF111827);

  /// Superficie elevada en modo oscuro.
  static const Color surfaceElevatedDark = Color(0xFF1A2231);

  // ── Texto ───────────────────────────────────────────────────────────────
  /// Gris oscuro de marca. Texto principal en modo claro.
  static const Color textPrimaryLight = Color(0xFF1F2937);

  /// Texto secundario en modo claro.
  static const Color textSecondaryLight = Color(0xFF6B7280);

  /// Texto deshabilitado en modo claro.
  static const Color textDisabledLight = Color(0xFF9CA3AF);

  /// Texto principal en modo oscuro.
  static const Color textPrimaryDark = Color(0xFFF3F4F6);

  /// Texto secundario en modo oscuro.
  static const Color textSecondaryDark = Color(0xFF9CA3AF);

  /// Texto deshabilitado en modo oscuro.
  static const Color textDisabledDark = Color(0xFF6B7280);

  // ── Bordes ──────────────────────────────────────────────────────────────
  /// Borde y separador en modo claro.
  static const Color outlineLight = Color(0xFFE5E7EB);

  /// Borde y separador en modo oscuro.
  static const Color outlineDark = Color(0xFF1F2937);

  // ── Semánticos ──────────────────────────────────────────────────────────
  /// Error / acción destructiva (modo claro).
  static const Color error = Color(0xFFEF4444);

  /// Error en modo oscuro.
  static const Color errorDark = Color(0xFFF87171);

  /// Advertencia.
  static const Color warning = Color(0xFFF97316);

  /// Información.
  static const Color info = Color(0xFF0EA5E9);

  /// Blanco puro.
  static const Color white = Color(0xFFFFFFFF);

  // ── Utilidades de accesibilidad ─────────────────────────────────────────

  /// Luminancia relativa según WCAG 2.1.
  static double relativeLuminance(Color color) {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// Ratio de contraste entre dos colores (de 1:1 a 21:1).
  ///
  /// Se usa en los tests del design system: si alguien cambia un token y rompe
  /// el contraste, el build falla antes de llegar a producción.
  static double contrastRatio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// `true` si el par cumple WCAG AA para texto normal (4.5:1).
  static bool meetsAaText(Color foreground, Color background) =>
      contrastRatio(foreground, background) >= 4.5;

  /// `true` si el par cumple WCAG AA para texto grande o iconos (3:1).
  static bool meetsAaLarge(Color foreground, Color background) =>
      contrastRatio(foreground, background) >= 3.0;
}
