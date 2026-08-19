import 'dart:async';

import 'package:ascend_core/src/errors/failure.dart';
import 'package:meta/meta.dart';

/// El resultado de una operación que puede fallar.
///
/// Ascend no propaga excepciones hacia arriba: toda función de la capa de datos
/// devuelve un [Result]. La consecuencia práctica es que la UI nunca puede
/// recibir un `throw` inesperado, porque el tipo la obliga a contemplar el
/// fallo.
///
/// Al ser `sealed`, el `switch` exhaustivo lo verifica el compilador:
///
/// ```dart
/// final message = switch (result) {
///   Success(:final value) => 'Hola ${value.displayName}',
///   Failed(:final failure) => l10n.resolve(failure.messageKey),
/// };
/// ```
@immutable
sealed class Result<T> {
  /// Constructor base.
  const Result();

  /// Crea un resultado exitoso.
  const factory Result.success(T value) = Success<T>;

  /// Crea un resultado fallido.
  const factory Result.failure(Failure failure) = Failed<T>;

  /// `true` si la operación salió bien.
  bool get isSuccess => this is Success<T>;

  /// `true` si la operación falló.
  bool get isFailure => this is Failed<T>;

  /// El valor, o `null` si hubo fallo.
  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    Failed<T>() => null,
  };

  /// El fallo, o `null` si salió bien.
  Failure? get failureOrNull => switch (this) {
    Success<T>() => null,
    Failed<T>(:final failure) => failure,
  };

  /// Colapsa ambos casos en un único valor de tipo [R].
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) => switch (this) {
    Success<T>(:final value) => onSuccess(value),
    Failed<T>(:final failure) => onFailure(failure),
  };

  /// Transforma el valor si hubo éxito; propaga el fallo intacto si no.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Success<T>(:final value) => Success<R>(transform(value)),
    Failed<T>(:final failure) => Failed<R>(failure),
  };

  /// Encadena otra operación que también puede fallar.
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
    Success<T>(:final value) => transform(value),
    Failed<T>(:final failure) => Failed<R>(failure),
  };

  /// Igual que [flatMap] pero para operaciones asincrónicas.
  Future<Result<R>> flatMapAsync<R>(
    Future<Result<R>> Function(T value) transform,
  ) async => switch (this) {
    Success<T>(:final value) => await transform(value),
    Failed<T>(:final failure) => Failed<R>(failure),
  };

  /// El valor, o el que devuelva [orElse] si hubo fallo.
  T getOrElse(T Function(Failure failure) orElse) => switch (this) {
    Success<T>(:final value) => value,
    Failed<T>(:final failure) => orElse(failure),
  };

  /// Ejecuta [action] solo si hubo éxito. Devuelve `this` para encadenar.
  Result<T> onSuccess(void Function(T value) action) {
    if (this case Success<T>(:final value)) {
      action(value);
    }
    return this;
  }

  /// Ejecuta [action] solo si hubo fallo. Devuelve `this` para encadenar.
  Result<T> onFailure(void Function(Failure failure) action) {
    if (this case Failed<T>(:final failure)) {
      action(failure);
    }
    return this;
  }
}

/// Rama exitosa de un [Result].
final class Success<T> extends Result<T> {
  /// Crea una rama exitosa con su [value].
  const Success(this.value);

  /// El valor producido por la operación.
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Success<T> && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Success($value)';
}

/// Rama fallida de un [Result].
final class Failed<T> extends Result<T> {
  /// Crea una rama fallida con su [failure].
  const Failed(this.failure);

  /// El fallo que impidió completar la operación.
  final Failure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Failed<T> && other.failure == failure);

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Failed($failure)';
}

/// Azúcar sintáctico para construir resultados.
extension ResultValueX<T> on T {
  /// Envuelve este valor en un [Success].
  Result<T> get asSuccess => Success<T>(this);
}

/// Utilidades para trabajar con futuros que devuelven [Result].
extension FutureResultX<T> on Future<Result<T>> {
  /// Encadena una operación asincrónica sobre el valor exitoso.
  Future<Result<R>> flatMapAsync<R>(
    Future<Result<R>> Function(T value) transform,
  ) async => (await this).flatMapAsync(transform);

  /// Transforma el valor exitoso.
  Future<Result<R>> mapAsync<R>(R Function(T value) transform) async =>
      (await this).map(transform);
}

/// Ejecuta [action] capturando cualquier excepción y convirtiéndola con
/// [onError] en un [Failure].
///
/// Es el único lugar donde Ascend hace `try/catch` genérico: cada repositorio
/// lo usa con su propio mapeador de errores, de modo que ninguna excepción
/// escapa de la capa de datos.
Future<Result<T>> guardAsync<T>(
  Future<T> Function() action, {
  required Failure Function(Object error, StackTrace stackTrace) onError,
}) async {
  try {
    return Success<T>(await action());
  } on Object catch (error, stackTrace) {
    return Failed<T>(onError(error, stackTrace));
  }
}

/// Versión sincrónica de [guardAsync].
Result<T> guard<T>(
  T Function() action, {
  required Failure Function(Object error, StackTrace stackTrace) onError,
}) {
  try {
    return Success<T>(action());
  } on Object catch (error, stackTrace) {
    return Failed<T>(onError(error, stackTrace));
  }
}
