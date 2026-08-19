import 'dart:math' as math;

import 'package:ascend_ui/src/theme/ascend_theme.dart';
import 'package:ascend_ui/src/tokens/ascend_tokens.dart';
import 'package:flutter/material.dart';

/// Anillo de progreso circular animado.
///
/// Es el elemento visual central de los objetivos: comunica avance de un
/// vistazo, sin números.
class ProgressRing extends StatelessWidget {
  /// Crea un anillo de progreso.
  const ProgressRing({
    required this.progress,
    this.size = 64,
    this.strokeWidth = 6,
    this.color,
    this.child,
    this.animate = true,
    super.key,
  });

  /// Avance entre 0.0 y 1.0. Se recorta si viene fuera de rango.
  final double progress;

  /// Diámetro del anillo.
  final double size;

  /// Grosor del trazo.
  final double strokeWidth;

  /// Color del progreso. Por defecto, el verde de éxito.
  final Color? color;

  /// Contenido central (porcentaje, icono).
  final Widget? child;

  /// Si anima al cambiar el valor.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final effectiveColor = color ?? context.ascend.success;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (animate)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: clamped),
              duration: AscendDurations.celebration,
              curve: AscendCurves.standard,
              builder: (_, value, _) => _Ring(
                progress: value,
                strokeWidth: strokeWidth,
                color: effectiveColor,
                trackColor: context.colors.surfaceContainerHighest,
              ),
            )
          else
            _Ring(
              progress: clamped,
              strokeWidth: strokeWidth,
              color: effectiveColor,
              trackColor: context.colors.surfaceContainerHighest,
            ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _RingPainter(
      progress: progress,
      strokeWidth: strokeWidth,
      color: color,
      trackColor: trackColor,
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

/// Insignia que muestra una cantidad de Aura.
///
/// El naranja se usa como **relleno** del contenedor y el número va en un color
/// que sí cumple contraste. Es la aplicación práctica de la restricción de
/// accesibilidad del token `aura`.
class AuraBadge extends StatelessWidget {
  /// Crea una insignia de Aura.
  const AuraBadge({
    required this.amount,
    this.showPlus = false,
    this.compact = false,
    super.key,
  });

  /// Cantidad de Aura a mostrar.
  final int amount;

  /// Si antepone un `+` (para recompensas recién ganadas).
  final bool showPlus;

  /// Versión reducida, para listas densas.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ascend = context.ascend;
    final label = '${showPlus ? '+' : ''}$amount';

    return Semantics(
      label: '$label de Aura',
      // Nodo semántico propio: si no, el lector de pantalla anuncia "25" suelto
      // en vez de "25 de Aura".
      container: true,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AscendSpacing.sm : AscendSpacing.md,
          vertical: compact ? AscendSpacing.xxs : AscendSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: ascend.aura.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AscendRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_awesome_rounded,
              size: compact ? 12 : 16,
              color: ascend.auraOnSurface,
            ),
            const SizedBox(width: AscendSpacing.xs),
            Text(
              label,
              style:
                  (compact
                          ? context.texts.labelSmall
                          : context.texts.labelMedium)
                      ?.copyWith(
                        color: ascend.auraOnSurface,
                        fontWeight: FontWeight.w600,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicador de racha en días.
class StreakFlame extends StatelessWidget {
  /// Crea el indicador de racha.
  const StreakFlame({required this.days, this.atRisk = false, super.key});

  /// Días consecutivos de actividad.
  final int days;

  /// Si la racha está por perderse hoy (cambia el color a advertencia).
  final bool atRisk;

  @override
  Widget build(BuildContext context) {
    final ascend = context.ascend;
    final color = atRisk ? ascend.warning : ascend.auraOnSurface;

    return Semantics(
      label: atRisk ? 'Racha de $days días en riesgo' : 'Racha de $days días',
      container: true,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.local_fire_department_rounded, size: 18, color: color),
          const SizedBox(width: AscendSpacing.xs),
          Text(
            '$days',
            style: context.texts.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
