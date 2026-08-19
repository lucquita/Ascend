import 'package:ascend_core/src/errors/failure.dart';
import 'package:ascend_core/src/result/result.dart';

/// Validaciones compartidas entre la app móvil, el panel y los tests.
///
/// Devuelven [Result] en lugar de lanzar, para poder componerlas con el resto
/// del flujo sin `try/catch`. Las mismas reglas se replican en las reglas de
/// Firestore y en las Cloud Functions: validar solo en el cliente no es
/// validar.
abstract final class Validators {
  static final RegExp _emailRegExp = RegExp(
    r'^[\w.!#$%&’*+/=?^`{|}~-]+@[a-zA-Z0-9]'
    r'(?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  static final RegExp _handleRegExp = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Longitud mínima de contraseña aceptada.
  static const int minPasswordLength = 8;

  /// Longitud máxima del nombre visible.
  static const int maxDisplayNameLength = 40;

  /// Longitud máxima del título de un objetivo o misión.
  static const int maxTitleLength = 80;

  /// Longitud máxima del texto de una publicación.
  static const int maxPostLength = 500;

  /// Longitud máxima de un comentario.
  static const int maxCommentLength = 300;

  /// Valida un correo electrónico.
  static Result<String> email(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.email.required',
          field: 'email',
        ),
      );
    }
    if (!_emailRegExp.hasMatch(value)) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.email.invalid',
          field: 'email',
        ),
      );
    }
    return Success<String>(value.toLowerCase());
  }

  /// Valida una contraseña.
  ///
  /// Exige 8 caracteres con al menos una letra y un número. No pedimos
  /// símbolos obligatorios: encarece el registro sin mejorar la seguridad real
  /// frente a un límite de intentos, que sí tenemos.
  static Result<String> password(String? input) {
    final value = input ?? '';
    if (value.isEmpty) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.password.required',
          field: 'password',
        ),
      );
    }
    if (value.length < minPasswordLength) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.password.tooShort',
          field: 'password',
        ),
      );
    }
    final hasLetter = value.contains(RegExp('[a-zA-Z]'));
    final hasDigit = value.contains(RegExp('[0-9]'));
    if (!hasLetter || !hasDigit) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.password.tooWeak',
          field: 'password',
        ),
      );
    }
    return Success<String>(value);
  }

  /// Valida que dos contraseñas coincidan.
  static Result<String> passwordConfirmation(
    String? password,
    String? confirmation,
  ) {
    if (password != confirmation) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.password.mismatch',
          field: 'passwordConfirmation',
        ),
      );
    }
    return Success<String>(confirmation ?? '');
  }

  /// Valida un nombre de usuario público (`@handle`).
  ///
  /// Minúsculas, números y guion bajo, de 3 a 20 caracteres. Se normaliza a
  /// minúsculas para que la unicidad sea insensible a mayúsculas.
  static Result<String> handle(String? input) {
    final value = input?.trim().toLowerCase() ?? '';
    if (value.isEmpty) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.handle.required',
          field: 'handle',
        ),
      );
    }
    if (!_handleRegExp.hasMatch(value)) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.handle.invalid',
          field: 'handle',
        ),
      );
    }
    return Success<String>(value);
  }

  /// Valida el nombre visible.
  static Result<String> displayName(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.displayName.required',
          field: 'displayName',
        ),
      );
    }
    if (value.length > maxDisplayNameLength) {
      return const Failed<String>(
        ValidationFailure(
          messageKey: 'validation.displayName.tooLong',
          field: 'displayName',
        ),
      );
    }
    return Success<String>(value);
  }

  /// Valida un texto obligatorio con longitud máxima.
  static Result<String> requiredText(
    String? input, {
    required String field,
    required int maxLength,
  }) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) {
      return Failed<String>(
        ValidationFailure(
          messageKey: 'validation.$field.required',
          field: field,
        ),
      );
    }
    if (value.length > maxLength) {
      return Failed<String>(
        ValidationFailure(
          messageKey: 'validation.$field.tooLong',
          field: field,
        ),
      );
    }
    return Success<String>(value);
  }
}
