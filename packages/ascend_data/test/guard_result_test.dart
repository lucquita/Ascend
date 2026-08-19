import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// `guardResult` cierra la grieta entre el controlador y el repositorio.
///
/// Los repositorios nunca lanzan —lo garantiza `runGuarded`—, pero
/// **construirlos** sí puede: un `ref.read` levanta la cadena entera de
/// dependencias, y si en el fondo hay un `FirebaseAuth.instance` sin Firebase
/// inicializado, eso explota antes de que exista un `runGuarded` que lo atrape.
///
/// El síntoma de esa grieta era el peor posible: el controlador ya se había
/// puesto en `AsyncLoading`, la excepción escapaba del `await` y el estado
/// nunca salía de cargando. El botón giraba para siempre.
void main() {
  group('guardResult', () {
    test('deja pasar un Success intacto', () async {
      final result = await guardResult(() async => const Success<int>(42));

      expect(result.valueOrNull, 42);
    });

    test('deja pasar un Failed intacto, sin reenvolverlo', () async {
      final result = await guardResult(
        () async => const Failed<int>(NotFoundFailure(code: 'x')),
      );

      expect(result.failureOrNull, isA<NotFoundFailure>());
      expect(result.failureOrNull?.code, 'x');
    });

    test('convierte en Failure una excepción al CONSTRUIR la acción', () async {
      // Es el caso real: `ref.read(algoProvider)` lanza porque Firebase no
      // está inicializado, antes siquiera de llamar al repositorio.
      final result = await guardResult<int>(
        () => throw StateError('No Firebase App [DEFAULT] has been created'),
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isNotNull);
    });

    test('convierte en Failure una excepción asincrónica', () async {
      final result = await guardResult<int>(() async {
        await Future<void>.delayed(Duration.zero);
        throw StateError('se cayó a mitad de camino');
      });

      expect(result.isFailure, isTrue);
    });

    test('NUNCA deja el futuro colgado: siempre completa', () async {
      // Es la propiedad que importa. Si esto fallara, la pantalla se quedaría
      // en `AsyncLoading` para siempre, que es justamente el modo de fallo que
      // no puede existir en Ascend.
      for (final action in <Future<Result<int>> Function()>[
        () async => const Success<int>(1),
        () async => const Failed<int>(NetworkFailure()),
        () => throw Exception('crudo'),
        () async => throw const FormatException('malformado'),
      ]) {
        await expectLater(guardResult(action), completes);
      }
    });
  });
}
