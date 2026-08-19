import 'package:ascend_core/ascend_core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('Success expone el valor y no el fallo', () {
      const result = Result<int>.success(42);

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.failureOrNull, isNull);
    });

    test('Failed expone el fallo y no el valor', () {
      const failure = NetworkFailure();
      const result = Result<int>.failure(failure);

      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, same(failure));
    });

    test('fold colapsa ambas ramas', () {
      const ok = Result<int>.success(2);
      const err = Result<int>.failure(ServerFailure());

      String describe(Result<int> r) => r.fold(
        onSuccess: (v) => 'ok:$v',
        onFailure: (f) => 'err:${f.messageKey}',
      );

      expect(describe(ok), 'ok:2');
      expect(describe(err), 'err:failure.server');
    });

    test('map transforma el éxito y deja pasar el fallo intacto', () {
      const failure = TimeoutFailure();

      expect(const Result<int>.success(3).map((v) => v * 2).valueOrNull, 6);
      expect(
        const Result<int>.failure(failure).map((v) => v * 2).failureOrNull,
        same(failure),
      );
    });

    test('flatMap encadena operaciones que también pueden fallar', () {
      Result<int> half(int v) => v.isEven
          ? Result<int>.success(v ~/ 2)
          : const Result<int>.failure(
              ValidationFailure(messageKey: 'validation.odd'),
            );

      expect(const Result<int>.success(8).flatMap(half).valueOrNull, 4);
      expect(const Result<int>.success(7).flatMap(half).isFailure, isTrue);
    });

    test('getOrElse devuelve el sustituto solo cuando hay fallo', () {
      expect(const Result<int>.success(5).getOrElse((_) => 0), 5);
      expect(
        const Result<int>.failure(UnknownFailure()).getOrElse((_) => 0),
        0,
      );
    });

    test('onSuccess y onFailure ejecutan solo la rama correspondiente', () {
      var successCalls = 0;
      var failureCalls = 0;

      const Result<int>.success(
        1,
      ).onSuccess((_) => successCalls++).onFailure((_) => failureCalls++);
      const Result<int>.failure(
        NetworkFailure(),
      ).onSuccess((_) => successCalls++).onFailure((_) => failureCalls++);

      expect(successCalls, 1);
      expect(failureCalls, 1);
    });

    test('la igualdad se basa en el contenido', () {
      expect(const Result<int>.success(1), const Result<int>.success(1));
      expect(const Result<int>.success(1), isNot(const Result<int>.success(2)));
    });
  });

  group('guardAsync', () {
    test('devuelve Success cuando la acción no lanza', () async {
      final result = await guardAsync<int>(
        () async => 7,
        onError: (_, _) => const UnknownFailure(),
      );

      expect(result.valueOrNull, 7);
    });

    test('convierte cualquier excepción en Failure sin propagarla', () async {
      final result = await guardAsync<int>(
        () async => throw const FormatException('boom'),
        onError: (error, stackTrace) =>
            ServerFailure(cause: error, stackTrace: stackTrace),
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ServerFailure>());
      expect(result.failureOrNull?.cause, isA<FormatException>());
    });
  });

  group('guard (sincrónico)', () {
    test('captura excepciones sincrónicas', () {
      final result = guard<int>(
        () => throw StateError('nope'),
        onError: (error, _) => UnknownFailure(cause: error),
      );

      expect(result.isFailure, isTrue);
    });
  });
}
