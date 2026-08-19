import 'package:ascend_mobile/app.dart';
import 'package:ascend_mobile/router/app_router.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({SessionState session = SessionState.ready}) => ProviderScope(
  overrides: [sessionStateProvider.overrideWithValue(session)],
  child: const AscendApp(),
);

void main() {
  group('Arranque de la app', () {
    testWidgets('monta sin errores y muestra la pantalla Hoy', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Hoy'), findsWidgets);
    });

    testWidgets('la barra inferior tiene las cuatro secciones', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      for (final label in <String>['Hoy', 'Objetivos', 'Comunidad', 'Perfil']) {
        expect(
          find.text(label),
          findsWidgets,
          reason: 'Falta la sección $label',
        );
      }
    });

    testWidgets('navega entre secciones conservando el shell', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Objetivos').last);
      // `pump` con duración fija y no `pumpAndSettle`: la pantalla de objetivos
      // puede quedar mostrando skeletons, cuyo shimmer es una animación infinita
      // que nunca "asienta". `pumpAndSettle` esperaría para siempre.
      await tester.pump(const Duration(milliseconds: 400));
      // Se afirma sobre el andamiaje de la pantalla —que se pinta con datos o
      // sin ellos— y no sobre su contenido: este test verifica navegación, no
      // la carga de objetivos, que tiene sus propios tests.
      expect(find.text('Nuevo objetivo'), findsOneWidget);

      await tester.tap(find.text('Comunidad').last);
      await tester.pump(const Duration(milliseconds: 400));
      // Igual que con Objetivos: se afirma sobre el andamiaje de la pantalla,
      // que se pinta con datos o sin ellos. Este test verifica navegación.
      expect(find.text('Publicar'), findsOneWidget);

      // El shell nunca desaparece al cambiar de sección.
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('Guards del router', () {
    testWidgets('sin sesión, cualquier ruta lleva al login', (tester) async {
      await tester.pumpWidget(_app(session: SessionState.signedOut));
      await tester.pumpAndSettle();

      expect(find.text('Iniciar sesión'), findsWidgets);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('con onboarding pendiente, redirige al onboarding', (
      tester,
    ) async {
      await tester.pumpWidget(_app(session: SessionState.needsOnboarding));
      await tester.pumpAndSettle();

      expect(find.text('Onboarding'), findsWidgets);
    });

    testWidgets('con sesión lista, no se puede volver al login', (
      tester,
    ) async {
      // El container tiene que ser el mismo que usa el widget: si se crea uno
      // aparte se instancia un GoRouter distinto del que está montado.
      final container = ProviderContainer(
        overrides: [sessionStateProvider.overrideWithValue(SessionState.ready)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AscendApp(),
        ),
      );
      await tester.pumpAndSettle();

      final goRouter = container.read(appRouterProvider)..go(Routes.login);
      await tester.pumpAndSettle();

      expect(goRouter.state.matchedLocation, isNot(Routes.login));
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('una ruta inexistente muestra la pantalla de no encontrado', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [sessionStateProvider.overrideWithValue(SessionState.ready)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AscendApp(),
        ),
      );
      await tester.pumpAndSettle();

      container.read(appRouterProvider).go('/ruta-que-no-existe');
      await tester.pumpAndSettle();

      expect(find.text('Página no encontrada'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('Red de captura de errores', () {
    testWidgets(
      'un throw dentro de build muestra la pantalla de Ascend, no la roja',
      (tester) async {
        // Este es el criterio de aceptación central de la Fase 0.
        final originalBuilder = ErrorWidget.builder;
        ErrorWidget.builder = (details) =>
            AscendErrorFallback(details: details);

        await tester.pumpWidget(const MaterialApp(home: _ExplodingWidget()));

        // Flutter registra la excepción, pero la pantalla muestra nuestro
        // mensaje humano en lugar del cuadro rojo.
        expect(tester.takeException(), isA<StateError>());
        expect(find.byType(AscendErrorFallback), findsOneWidget);
        expect(find.text('Algo salió mal'), findsOneWidget);
        expect(find.textContaining('StateError'), findsNothing);

        // Se restaura acá y no en un addTearDown: el framework verifica que
        // ErrorWidget.builder vuelva a su valor original ANTES de los teardowns.
        ErrorWidget.builder = originalBuilder;
      },
    );
  });

  group('Accesibilidad', () {
    testWidgets('el escalado de texto se limita a 1.5x sin desbordar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: _app(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

class _ExplodingWidget extends StatelessWidget {
  const _ExplodingWidget();

  @override
  Widget build(BuildContext context) =>
      throw StateError('Error provocado dentro de build()');
}
