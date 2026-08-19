import 'package:ascend_ui/src/theme/ascend_typography.dart';
import 'package:ascend_ui/src/tokens/ascend_colors.dart';
import 'package:ascend_ui/src/tokens/ascend_tokens.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colores propios de Ascend que Material 3 no contempla.
///
/// El Aura y la racha no encajan en ningún slot del [ColorScheme], así que
/// viajan como extensión del tema. De esa forma se acceden con
/// `Theme.of(context).extension<AscendThemeExtension>()` y cambian solos entre
/// claro y oscuro, sin que ningún widget tenga que preguntar por el brillo.
@immutable
class AscendThemeExtension extends ThemeExtension<AscendThemeExtension> {
  /// Crea la extensión con todos sus colores.
  const AscendThemeExtension({
    required this.aura,
    required this.auraOnSurface,
    required this.success,
    required this.successOnSurface,
    required this.warning,
    required this.info,
    required this.textSecondary,
    required this.textDisabled,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  /// Naranja Aura para rellenos (insignias, anillos, iconos grandes).
  final Color aura;

  /// Variante de Aura legible como texto sobre la superficie actual.
  final Color auraOnSurface;

  /// Verde de progreso para rellenos.
  final Color success;

  /// Verde legible como texto sobre la superficie actual.
  final Color successOnSurface;

  /// Naranja de advertencia.
  final Color warning;

  /// Azul de información.
  final Color info;

  /// Texto secundario.
  final Color textSecondary;

  /// Texto deshabilitado.
  final Color textDisabled;

  /// Color base del efecto shimmer.
  final Color skeletonBase;

  /// Color del brillo del efecto shimmer.
  final Color skeletonHighlight;

  /// Extensión del modo claro.
  static const AscendThemeExtension light = AscendThemeExtension(
    aura: AscendColors.aura,
    // Sobre fondo claro, el naranja de marca no llega a 4.5:1 como texto.
    auraOnSurface: AscendColors.auraText,
    success: AscendColors.success,
    successOnSurface: AscendColors.successText,
    warning: AscendColors.warning,
    info: AscendColors.info,
    textSecondary: AscendColors.textSecondaryLight,
    textDisabled: AscendColors.textDisabledLight,
    skeletonBase: Color(0xFFE5E7EB),
    skeletonHighlight: Color(0xFFF3F4F6),
  );

  /// Extensión del modo oscuro.
  static const AscendThemeExtension dark = AscendThemeExtension(
    aura: AscendColors.auraDark,
    // Sobre fondo oscuro el naranja claro sí contrasta: no hace falta variante.
    auraOnSurface: AscendColors.auraDark,
    success: AscendColors.successDark,
    successOnSurface: AscendColors.successDark,
    warning: AscendColors.warning,
    info: AscendColors.info,
    textSecondary: AscendColors.textSecondaryDark,
    textDisabled: AscendColors.textDisabledDark,
    skeletonBase: Color(0xFF1F2937),
    skeletonHighlight: Color(0xFF374151),
  );

  @override
  AscendThemeExtension copyWith({
    Color? aura,
    Color? auraOnSurface,
    Color? success,
    Color? successOnSurface,
    Color? warning,
    Color? info,
    Color? textSecondary,
    Color? textDisabled,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) => AscendThemeExtension(
    aura: aura ?? this.aura,
    auraOnSurface: auraOnSurface ?? this.auraOnSurface,
    success: success ?? this.success,
    successOnSurface: successOnSurface ?? this.successOnSurface,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    textSecondary: textSecondary ?? this.textSecondary,
    textDisabled: textDisabled ?? this.textDisabled,
    skeletonBase: skeletonBase ?? this.skeletonBase,
    skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
  );

  @override
  AscendThemeExtension lerp(
    covariant ThemeExtension<AscendThemeExtension>? other,
    double t,
  ) {
    if (other is! AscendThemeExtension) {
      return this;
    }
    return AscendThemeExtension(
      aura: Color.lerp(aura, other.aura, t) ?? aura,
      auraOnSurface:
          Color.lerp(auraOnSurface, other.auraOnSurface, t) ?? auraOnSurface,
      success: Color.lerp(success, other.success, t) ?? success,
      successOnSurface:
          Color.lerp(successOnSurface, other.successOnSurface, t) ??
          successOnSurface,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      info: Color.lerp(info, other.info, t) ?? info,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textDisabled:
          Color.lerp(textDisabled, other.textDisabled, t) ?? textDisabled,
      skeletonBase:
          Color.lerp(skeletonBase, other.skeletonBase, t) ?? skeletonBase,
      skeletonHighlight:
          Color.lerp(skeletonHighlight, other.skeletonHighlight, t) ??
          skeletonHighlight,
    );
  }
}

/// Acceso corto a la extensión de tema desde cualquier widget.
extension AscendThemeContextX on BuildContext {
  /// Colores propios de Ascend para el modo actual.
  AscendThemeExtension get ascend =>
      Theme.of(this).extension<AscendThemeExtension>() ??
      AscendThemeExtension.light;

  /// Atajo al [TextTheme] actual.
  TextTheme get texts => Theme.of(this).textTheme;

  /// Atajo al [ColorScheme] actual.
  ColorScheme get colors => Theme.of(this).colorScheme;

  /// `true` si la app está en modo oscuro.
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Temas claro y oscuro de Ascend.
abstract final class AscendTheme {
  /// Tema claro.
  static ThemeData get light => _build(Brightness.light);

  /// Tema oscuro.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AscendColors.primaryDark : AscendColors.primary,
      onPrimary: isDark ? const Color(0xFF0B1220) : AscendColors.white,
      primaryContainer: isDark
          ? const Color(0xFF1E3A8A)
          : const Color(0xFFDBEAFE),
      onPrimaryContainer: isDark
          ? const Color(0xFFDBEAFE)
          : AscendColors.primaryDeep,
      secondary: isDark ? AscendColors.successDark : AscendColors.success,
      onSecondary: isDark ? const Color(0xFF052E16) : AscendColors.white,
      secondaryContainer: isDark
          ? const Color(0xFF14532D)
          : const Color(0xFFDCFCE7),
      onSecondaryContainer: isDark
          ? const Color(0xFFDCFCE7)
          : AscendColors.successText,
      tertiary: isDark ? AscendColors.auraDark : AscendColors.aura,
      onTertiary: isDark ? const Color(0xFF231400) : AscendColors.white,
      error: isDark ? AscendColors.errorDark : AscendColors.error,
      onError: AscendColors.white,
      surface: isDark ? AscendColors.surfaceDark : AscendColors.surfaceLight,
      onSurface: isDark
          ? AscendColors.textPrimaryDark
          : AscendColors.textPrimaryLight,
      onSurfaceVariant: isDark
          ? AscendColors.textSecondaryDark
          : AscendColors.textSecondaryLight,
      surfaceContainerLowest: isDark
          ? AscendColors.backgroundDark
          : AscendColors.white,
      surfaceContainer: isDark
          ? AscendColors.surfaceElevatedDark
          : AscendColors.backgroundLight,
      surfaceContainerHighest: isDark
          ? AscendColors.surfaceElevatedDark
          : const Color(0xFFF3F4F6),
      outline: isDark ? AscendColors.outlineDark : AscendColors.outlineLight,
      outlineVariant: isDark
          ? const Color(0xFF374151)
          : const Color(0xFFF3F4F6),
    );

    final textTheme = AscendTypography.textTheme(
      primary: colorScheme.onSurface,
      secondary: colorScheme.onSurfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? AscendColors.backgroundDark
          : AscendColors.backgroundLight,
      textTheme: textTheme,
      fontFamily: AscendTypography.fontFamily,
      extensions: <ThemeExtension<dynamic>>[
        isDark ? AscendThemeExtension.dark : AscendThemeExtension.light,
      ],

      // Sin ondas de tinta gigantes: la respuesta táctil es sutil.
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? AscendColors.backgroundDark
            : AscendColors.backgroundLight,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AscendRadius.cardRadius,
          side: BorderSide(color: colorScheme.outline),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Alto mínimo sí, ancho mínimo NO. `Size.fromHeight` equivale a
          // `Size(double.infinity, 52)`: forzaba a **todos** los botones a
          // ocupar el ancho disponible, con lo que `AscendButton(expanded:
          // false)` no servía de nada y poner un botón dentro de un `Row`
          // rompía el layout con "BoxConstraints forces an infinite width".
          // El ancho completo lo decide `expanded`, que es donde corresponde.
          minimumSize: const Size(0, 52),
          shape: const RoundedRectangleBorder(
            borderRadius: AscendRadius.buttonRadius,
          ),
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: AscendSpacing.xl),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          side: BorderSide(color: colorScheme.outline),
          shape: const RoundedRectangleBorder(
            borderRadius: AscendRadius.buttonRadius,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // 48dp de alto mínimo: objetivo táctil accesible.
          minimumSize: const Size(48, 48),
          textStyle: textTheme.labelMedium,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AscendColors.surfaceElevatedDark
            : AscendColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AscendSpacing.lg,
          vertical: AscendSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: AscendRadius.buttonRadius,
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AscendRadius.buttonRadius,
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AscendRadius.buttonRadius,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AscendRadius.buttonRadius,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AscendRadius.buttonRadius,
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        side: BorderSide(color: colorScheme.outline),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AscendRadius.sm)),
        ),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: AscendSpacing.md),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AscendRadius.sheetRadius,
        ),
        showDragHandle: true,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AscendRadius.xl)),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
          textTheme.labelSmall,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outline,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? AscendColors.surfaceElevatedDark
            : AscendColors.textPrimaryLight,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AscendColors.white,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: AscendRadius.buttonRadius,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
