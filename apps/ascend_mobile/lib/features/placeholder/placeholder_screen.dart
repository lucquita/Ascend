import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Pantalla provisional para las rutas que todavía no tienen implementación.
///
/// Existe para que la Fase 0 sea verificable de punta a punta: se puede navegar
/// por toda la app, comprobar los temas claro y oscuro y validar el árbol de
/// rutas antes de escribir una sola pantalla real. Cada una declara en qué fase
/// se completa, así el estado del proyecto se ve desde el emulador.
class PlaceholderScreen extends StatelessWidget {
  /// Crea una pantalla provisional.
  const PlaceholderScreen({
    required this.title,
    this.subtitle,
    this.phase,
    this.icon = Icons.construction_rounded,
    super.key,
  });

  /// Título de la pantalla definitiva.
  final String title;

  /// Descripción de qué hará.
  final String? subtitle;

  /// Fase del roadmap en la que se implementa.
  final String? phase;

  /// Icono ilustrativo.
  final IconData icon;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: ContentContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: context.colors.primary),
            ),
            const SizedBox(height: AscendSpacing.xl),
            Text(
              title,
              style: context.texts.headlineSmall,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: AscendSpacing.sm),
              Text(
                subtitle!,
                style: context.texts.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
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
    ),
  );
}

/// Pantalla de diagnóstico de la Fase 0.
///
/// Permite comprobar en el dispositivo que la red de captura de errores hace lo
/// que promete: los botones lanzan excepciones a propósito y en ningún caso
/// debe aparecer la pantalla roja de Flutter.
class DevToolsScreen extends StatefulWidget {
  /// Crea la pantalla de diagnóstico.
  const DevToolsScreen({super.key});

  @override
  State<DevToolsScreen> createState() => _DevToolsScreenState();
}

class _DevToolsScreenState extends State<DevToolsScreen> {
  bool _explodeOnBuild = false;

  @override
  Widget build(BuildContext context) {
    if (_explodeOnBuild) {
      // A propósito: verifica que ErrorWidget.builder atrapa un fallo dentro
      // del build y muestra la pantalla de Ascend en vez de la roja.
      throw StateError('Error provocado dentro de build()');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico')),
      body: ListView(
        padding: AscendSpacing.screen,
        children: <Widget>[
          Text(
            'Verificación de la red de errores',
            style: context.texts.titleMedium,
          ),
          const SizedBox(height: AscendSpacing.sm),
          Text(
            'Ninguna de estas acciones debe mostrar la pantalla roja de Flutter.',
            style: context.texts.bodyMedium,
          ),
          const SizedBox(height: AscendSpacing.xl),

          AscendButton(
            label: 'Lanzar error dentro de build()',
            icon: Icons.bug_report_rounded,
            onPressed: () => setState(() => _explodeOnBuild = true),
          ),
          const SizedBox(height: AscendSpacing.md),
          AscendButton.secondary(
            label: 'Lanzar excepción asincrónica',
            icon: Icons.cloud_off_rounded,
            onPressed: () =>
                Future<void>.error(StateError('Error asincrónico provocado')),
          ),
          const SizedBox(height: AscendSpacing.xxl),

          Text('Estados de la interfaz', style: context.texts.titleMedium),
          const SizedBox(height: AscendSpacing.lg),
          const SizedBox(height: 220, child: AscendSkeletonList(itemCount: 2)),
          const SizedBox(height: AscendSpacing.lg),
          SizedBox(
            height: 280,
            child: ErrorStateView(
              failure: const NetworkFailure(),
              onRetry: () {},
            ),
          ),
          const SizedBox(height: AscendSpacing.lg),
          const SizedBox(
            height: 280,
            child: EmptyStateView(
              title: 'Todavía no tenés objetivos',
              message: 'Creá el primero y te armamos el plan.',
              icon: Icons.flag_rounded,
            ),
          ),
          const SizedBox(height: AscendSpacing.lg),
          const OfflineBanner(pendingCount: 3),
          const SizedBox(height: AscendSpacing.xl),

          const Row(
            children: <Widget>[
              AuraBadge(amount: 1840),
              SizedBox(width: AscendSpacing.md),
              AuraBadge(amount: 25, showPlus: true),
              SizedBox(width: AscendSpacing.md),
              StreakFlame(days: 12),
              SizedBox(width: AscendSpacing.md),
              StreakFlame(days: 3, atRisk: true),
              Spacer(),
              ProgressRing(progress: 0.375, size: 48),
            ],
          ),
          const SizedBox(height: AscendSpacing.xxl),

          AscendButton.ghost(label: 'Volver', onPressed: () => context.pop()),
        ],
      ),
    );
  }
}
