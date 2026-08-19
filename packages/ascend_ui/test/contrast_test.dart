import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Estos tests son una barrera de accesibilidad: si alguien cambia un token de
/// color y rompe el contraste mínimo, el build falla acá y no en una auditoría
/// tres meses después.
void main() {
  group('Contraste WCAG — modo claro', () {
    test('el texto principal cumple AA sobre fondo y superficie', () {
      expect(
        AscendColors.meetsAaText(
          AscendColors.textPrimaryLight,
          AscendColors.backgroundLight,
        ),
        isTrue,
      );
      expect(
        AscendColors.meetsAaText(
          AscendColors.textPrimaryLight,
          AscendColors.surfaceLight,
        ),
        isTrue,
      );
    });

    test('el texto secundario cumple AA sobre superficie', () {
      expect(
        AscendColors.meetsAaText(
          AscendColors.textSecondaryLight,
          AscendColors.surfaceLight,
        ),
        isTrue,
      );
    });

    test('el blanco sobre el azul primario cumple AA para texto grande', () {
      // Es el par de los botones primarios, cuyo label es de 16px semibold.
      expect(
        AscendColors.meetsAaLarge(AscendColors.white, AscendColors.primary),
        isTrue,
      );
    });

    // Este test documenta la restricción que motivó el token `auraText`.
    test('el naranja Aura NO cumple AA como texto sobre blanco', () {
      expect(
        AscendColors.meetsAaText(AscendColors.aura, AscendColors.surfaceLight),
        isFalse,
        reason: 'Si esto pasa a true, revisar por qué cambió el token `aura`.',
      );
    });

    test('la variante auraText SÍ cumple AA sobre superficies claras', () {
      expect(
        AscendColors.meetsAaText(
          AscendColors.auraText,
          AscendColors.surfaceLight,
        ),
        isTrue,
      );
      expect(
        AscendColors.meetsAaText(
          AscendColors.auraText,
          AscendColors.backgroundLight,
        ),
        isTrue,
      );
    });

    test('la variante successText cumple AA sobre superficies claras', () {
      expect(
        AscendColors.meetsAaText(
          AscendColors.successText,
          AscendColors.surfaceLight,
        ),
        isTrue,
      );
    });
  });

  group('Contraste WCAG — modo oscuro', () {
    test('el texto principal cumple AA sobre fondo y superficie', () {
      expect(
        AscendColors.meetsAaText(
          AscendColors.textPrimaryDark,
          AscendColors.backgroundDark,
        ),
        isTrue,
      );
      expect(
        AscendColors.meetsAaText(
          AscendColors.textPrimaryDark,
          AscendColors.surfaceDark,
        ),
        isTrue,
      );
    });

    test('el texto secundario cumple AA sobre superficie oscura', () {
      expect(
        AscendColors.meetsAaText(
          AscendColors.textSecondaryDark,
          AscendColors.surfaceDark,
        ),
        isTrue,
      );
    });

    test('el Aura clara sí funciona como texto sobre fondo oscuro', () {
      // Por eso en modo oscuro `auraOnSurface` no necesita variante propia.
      expect(
        AscendColors.meetsAaText(
          AscendColors.auraDark,
          AscendColors.surfaceDark,
        ),
        isTrue,
      );
    });

    test('el azul y el verde claros cumplen AA sobre superficie oscura', () {
      expect(
        AscendColors.meetsAaText(
          AscendColors.primaryDark,
          AscendColors.surfaceDark,
        ),
        isTrue,
      );
      expect(
        AscendColors.meetsAaText(
          AscendColors.successDark,
          AscendColors.surfaceDark,
        ),
        isTrue,
      );
    });
  });

  group('Coherencia de la extensión de tema', () {
    test('cada modo usa una variante de Aura legible', () {
      expect(
        AscendColors.meetsAaText(
          AscendThemeExtension.light.auraOnSurface,
          AscendColors.surfaceLight,
        ),
        isTrue,
      );
      expect(
        AscendColors.meetsAaText(
          AscendThemeExtension.dark.auraOnSurface,
          AscendColors.surfaceDark,
        ),
        isTrue,
      );
    });

    test('contrastRatio es simétrico y acotado', () {
      final ratio = AscendColors.contrastRatio(
        AscendColors.white,
        AscendColors.textPrimaryLight,
      );
      final inverse = AscendColors.contrastRatio(
        AscendColors.textPrimaryLight,
        AscendColors.white,
      );

      expect(ratio, closeTo(inverse, 0.0001));
      expect(ratio, inInclusiveRange(1.0, 21.0));
    });

    test('un color contra sí mismo da 1:1', () {
      expect(
        AscendColors.contrastRatio(AscendColors.primary, AscendColors.primary),
        closeTo(1.0, 0.0001),
      );
    });
  });
}
