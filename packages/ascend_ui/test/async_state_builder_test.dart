import 'dart:async';

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AscendTheme.light,
  home: Scaffold(body: child),
);

void main() {
  group('AsyncStateBuilder — los cinco estados', () {
    testWidgets('carga: muestra skeletons, no un spinner desnudo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AsyncStateBuilder<List<String>>(
            value: const AsyncValue<List<String>>.loading(),
            data: (data) => Text(data.join()),
          ),
        ),
      );

      expect(find.byType(AscendSkeletonList), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('datos: renderiza el contenido', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AsyncStateBuilder<List<String>>(
            value: const AsyncValue<List<String>>.data(<String>['misión 1']),
            data: (data) => Text(data.first),
          ),
        ),
      );

      expect(find.text('misión 1'), findsOneWidget);
    });

    testWidgets('vacío: muestra el estado vacío con su llamada a la acción', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AsyncStateBuilder<List<String>>(
            value: const AsyncValue<List<String>>.data(<String>[]),
            emptyState: const EmptyStateConfig(
              title: 'Todavía no tenés misiones',
              message: 'Creá tu primer objetivo y te armamos el plan.',
              actionLabel: 'Crear objetivo',
            ),
            data: (data) => Text('${data.length} items'),
          ),
        ),
      );

      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text('Todavía no tenés misiones'), findsOneWidget);
      expect(
        find.text('Crear objetivo'),
        findsNothing,
      ); // sin onAction no hay botón
    });

    testWidgets('error: muestra mensaje amigable y botón de reintentar', (
      tester,
    ) async {
      var retries = 0;

      await tester.pumpWidget(
        _wrap(
          AsyncStateBuilder<List<String>>(
            value: const AsyncValue<List<String>>.error(
              NetworkFailure(),
              StackTrace.empty,
            ),
            onRetry: () => retries++,
            data: (data) => Text(data.join()),
          ),
        ),
      );

      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(find.text('Sin conexión'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      expect(retries, 1);
    });

    testWidgets('offline: el banner comunica el estado sin bloquear', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: <Widget>[
              OfflineBanner(pendingCount: 2),
              Text('contenido cacheado'),
            ],
          ),
        ),
      );

      expect(find.textContaining('2 pendientes'), findsOneWidget);
      expect(find.text('contenido cacheado'), findsOneWidget);
    });
  });

  group('AsyncStateBuilder — garantías de resiliencia', () {
    // Esta es la prueba que respalda el requisito "jamás un error de Flutter":
    // aunque alguien lance una excepción cruda sin envolverla en Failure, la
    // pantalla muestra un mensaje amigable.
    testWidgets('una excepción cruda se normaliza a mensaje amigable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AsyncStateBuilder<List<String>>(
            value: AsyncValue<List<String>>.error(
              StateError('null check operator on a null value'),
              StackTrace.empty,
            ),
            data: (data) => Text(data.join()),
          ),
        ),
      );

      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(find.text('Algo salió mal'), findsOneWidget);
      // El detalle técnico NO se filtra a la pantalla.
      expect(find.textContaining('null check operator'), findsNothing);
    });

    testWidgets('no ofrece reintentar cuando reintentar no sirve', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AsyncStateBuilder<List<String>>(
            value: const AsyncValue<List<String>>.error(
              PermissionFailure(),
              StackTrace.empty,
            ),
            onRetry: () {},
            data: (data) => Text(data.join()),
          ),
        ),
      );

      expect(find.text('No tenés acceso'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('al refrescar mantiene los datos viejos en pantalla', (
      tester,
    ) async {
      // Se ejercita contra un provider real porque el estado "cargando pero con
      // valor previo" solo lo produce Riverpod al invalidar: construirlo a mano
      // usaría API interna del paquete.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      var callCount = 0;
      final provider = FutureProvider<List<String>>((ref) async {
        callCount++;
        if (callCount > 1) {
          // El segundo pedido nunca resuelve durante el test: así el estado
          // queda en "recargando" con el valor anterior todavía disponible.
          return Completer<List<String>>().future;
        }
        return <String>['dato previo'];
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(
            Consumer(
              builder: (context, ref, _) => AsyncStateBuilder<List<String>>(
                value: ref.watch(provider),
                data: (data) => Text(data.first),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('dato previo'), findsOneWidget);

      container.invalidate(provider);
      await tester.pump();

      expect(find.text('dato previo'), findsOneWidget);
      expect(find.byType(AscendSkeletonList), findsNothing);
    });
  });

  group('AscendErrorFallback', () {
    testWidgets('reemplaza la pantalla roja sin filtrar el stack en release', (
      tester,
    ) async {
      await tester.pumpWidget(
        AscendErrorFallback(
          details: FlutterErrorDetails(
            exception: StateError('boom interno'),
            library: 'test',
          ),
        ),
      );

      expect(find.text('Algo salió mal'), findsOneWidget);
      expect(find.textContaining('boom interno'), findsNothing);
    });

    testWidgets('en debug sí muestra el detalle técnico', (tester) async {
      await tester.pumpWidget(
        AscendErrorFallback(
          showDetails: true,
          details: FlutterErrorDetails(
            exception: StateError('boom interno'),
            library: 'test',
          ),
        ),
      );

      expect(find.textContaining('boom interno'), findsOneWidget);
    });
  });

  group('Componentes de Aura', () {
    testWidgets('AuraBadge usa la variante legible y expone semántica', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(const AuraBadge(amount: 25, showPlus: true)),
      );

      expect(find.text('+25'), findsOneWidget);
      expect(find.bySemanticsLabel('+25 de Aura'), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('ProgressRing recorta valores fuera de rango', (tester) async {
      await tester.pumpWidget(
        _wrap(const ProgressRing(progress: 1.8, animate: false)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('StreakFlame anuncia el riesgo en su semántica', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(const StreakFlame(days: 12, atRisk: true)));

      expect(
        find.bySemanticsLabel('Racha de 12 días en riesgo'),
        findsOneWidget,
      );

      semantics.dispose();
    });
  });

  group('AscendButton', () {
    testWidgets('bloquea la pulsación mientras carga', (tester) async {
      var taps = 0;

      await tester.pumpWidget(
        _wrap(
          AscendButton(
            label: 'Guardar',
            isLoading: true,
            onPressed: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byType(FilledButton));
      expect(taps, 0, reason: 'Un doble tap no debe duplicar la escritura.');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('dispara la acción cuando no está cargando', (tester) async {
      var taps = 0;

      await tester.pumpWidget(
        _wrap(AscendButton(label: 'Guardar', onPressed: () => taps++)),
      );

      await tester.tap(find.text('Guardar'));
      expect(taps, 1);
    });
  });
}
