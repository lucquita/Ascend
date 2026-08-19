import 'package:ascend_core/ascend_core.dart';
import 'package:test/test.dart';

void main() {
  group('Validators.email', () {
    test('acepta direcciones válidas y las normaliza a minúsculas', () {
      expect(
        Validators.email('Santino@Example.COM').valueOrNull,
        'santino@example.com',
      );
      expect(Validators.email('  a.b+tag@sub.dominio.ar ').isSuccess, isTrue);
    });

    test('rechaza vacío y formatos inválidos', () {
      expect(Validators.email(null).isFailure, isTrue);
      expect(Validators.email('   ').isFailure, isTrue);
      expect(Validators.email('sin-arroba.com').isFailure, isTrue);
      expect(Validators.email('a@b').isFailure, isTrue);
    });

    test('el fallo identifica el campo del formulario', () {
      final failure = Validators.email('mal').failureOrNull;
      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).field, 'email');
    });
  });

  group('Validators.password', () {
    test('acepta 8+ caracteres con letra y número', () {
      expect(Validators.password('ascend2026').isSuccess, isTrue);
    });

    test('rechaza cortas, sin número o sin letra', () {
      expect(Validators.password('abc12').isFailure, isTrue);
      expect(Validators.password('solamenteletras').isFailure, isTrue);
      expect(Validators.password('12345678').isFailure, isTrue);
    });

    test('detecta contraseñas que no coinciden', () {
      expect(
        Validators.passwordConfirmation('abc12345', 'abc12345').isSuccess,
        isTrue,
      );
      expect(
        Validators.passwordConfirmation('abc12345', 'otra1234').isFailure,
        isTrue,
      );
    });
  });

  group('Validators.handle', () {
    test('normaliza a minúsculas', () {
      expect(Validators.handle('  SanTino_01 ').valueOrNull, 'santino_01');
    });

    test('rechaza longitudes y caracteres inválidos', () {
      expect(Validators.handle('ab').isFailure, isTrue);
      expect(Validators.handle('a' * 21).isFailure, isTrue);
      expect(Validators.handle('con espacio').isFailure, isTrue);
      expect(Validators.handle('con-guion').isFailure, isTrue);
      expect(Validators.handle('acento_ñ').isFailure, isTrue);
    });
  });

  group('Validators.requiredText', () {
    test('respeta el máximo indicado', () {
      final ok = Validators.requiredText('hola', field: 'title', maxLength: 10);
      final tooLong = Validators.requiredText(
        'a' * 11,
        field: 'title',
        maxLength: 10,
      );

      expect(ok.isSuccess, isTrue);
      expect(tooLong.isFailure, isTrue);
      expect(tooLong.failureOrNull?.messageKey, 'validation.title.tooLong');
    });
  });
}
