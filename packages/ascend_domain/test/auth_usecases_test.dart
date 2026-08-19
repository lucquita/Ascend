import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

/// Doble de [AuthRepository] que registra qué se le pidió.
///
/// Se escribe a mano en lugar de usar un framework de mocking porque lo que hay
/// que verificar es justamente **si el repositorio llegó a llamarse**: la
/// mayoría de estos tests comprueban que una validación cortó el flujo antes de
/// tocar la red.
class _FakeAuthRepository implements AuthRepository {
  int signInCalls = 0;
  int signUpCalls = 0;
  int resetCalls = 0;
  int updatePasswordCalls = 0;
  int deleteCalls = 0;

  String? lastEmail;
  String? lastHandle;
  String? lastDisplayName;

  Result<AppUser> nextResult = Success<AppUser>(_user);

  static final AppUser _user = AppUser(
    uid: 'u1',
    email: 'ana@ascend.app',
    displayName: 'Ana',
    handle: 'ana',
    createdAt: DateTime.utc(2026),
  );

  @override
  Future<Result<AppUser>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    lastEmail = email;
    return nextResult;
  }

  @override
  Future<Result<AppUser>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String handle,
  }) async {
    signUpCalls++;
    lastEmail = email;
    lastHandle = handle;
    lastDisplayName = displayName;
    return nextResult;
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    resetCalls++;
    lastEmail = email;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    updatePasswordCalls++;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> deleteAccount({required String password}) async {
    deleteCalls++;
    return const Success<void>(null);
  }

  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.value(_user);

  @override
  AppUser? get currentUser => _user;

  @override
  Future<Result<AppUser>> reloadUser() async => nextResult;

  @override
  Future<Result<void>> refreshToken() async => const Success<void>(null);

  @override
  Future<Result<void>> sendEmailVerification() async =>
      const Success<void>(null);

  @override
  Future<Result<void>> signOut() async => const Success<void>(null);

  @override
  Future<Result<AppUser>> signInWithApple() async => nextResult;

  @override
  Future<Result<AppUser>> signInWithGoogle() async => nextResult;
}

class _FakeUserRepository implements UserRepository {
  int updateProfileCalls = 0;
  String? lastDisplayName;
  String? lastBio;
  bool handleFree = true;

  @override
  Future<Result<void>> updateProfile({
    required String uid,
    String? displayName,
    String? bio,
    String? photoUrl,
  }) async {
    updateProfileCalls++;
    lastDisplayName = displayName;
    lastBio = bio;
    return const Success<void>(null);
  }

  @override
  Future<Result<bool>> isHandleAvailable(String handle) async =>
      Success<bool>(handleFree);

  @override
  Future<Result<void>> completeOnboarding({
    required String uid,
    required List<String> interests,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> claimHandle({
    required String uid,
    required String handle,
  }) async => const Success<void>(null);

  @override
  Future<Result<AppUser>> getUser(String uid) async =>
      Success<AppUser>(_FakeAuthRepository._user);

  @override
  Future<Result<void>> updateSettings({
    required String uid,
    required UserSettings settings,
  }) async => const Success<void>(null);

  @override
  Future<Result<String>> uploadAvatar({
    required String uid,
    required String localPath,
  }) async => const Success<String>('https://cdn/avatar.jpg');

  @override
  Stream<Result<AppUser>> watchUser(String uid) =>
      Stream<Result<AppUser>>.value(
        Success<AppUser>(_FakeAuthRepository._user),
      );
}

void main() {
  group('SignInWithEmailUseCase', () {
    test(
      'normaliza el email a minúsculas antes de llamar al backend',
      () async {
        final repo = _FakeAuthRepository();
        final result = await SignInWithEmailUseCase(
          repo,
        ).call(email: '  ANA@Ascend.App ', password: 'secreto123');

        expect(result.isSuccess, isTrue);
        expect(repo.lastEmail, 'ana@ascend.app');
      },
    );

    test('con email inválido NO llega a la red', () async {
      final repo = _FakeAuthRepository();
      final result = await SignInWithEmailUseCase(
        repo,
      ).call(email: 'no-es-un-email', password: 'secreto123');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.signInCalls, 0, reason: 'validar primero ahorra una llamada');
    });

    test('acepta contraseñas que hoy no cumplirían la política', () async {
      // Quien se registró antes de endurecer la política tiene que poder
      // entrar: aplicar las reglas nuevas en el login lo dejaría afuera.
      final repo = _FakeAuthRepository();
      final result = await SignInWithEmailUseCase(
        repo,
      ).call(email: 'ana@ascend.app', password: 'abc');

      expect(result.isSuccess, isTrue);
      expect(repo.signInCalls, 1);
    });

    test('rechaza la contraseña vacía sin llamar al backend', () async {
      final repo = _FakeAuthRepository();
      final result = await SignInWithEmailUseCase(
        repo,
      ).call(email: 'ana@ascend.app', password: '');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.signInCalls, 0);
    });
  });

  group('SignUpWithEmailUseCase', () {
    Future<Result<AppUser>> signUp(
      _FakeAuthRepository repo, {
      String email = 'ana@ascend.app',
      String password = 'secreto123',
      String? confirmation,
      String displayName = 'Ana',
      String handle = 'ana',
      bool terms = true,
    }) => SignUpWithEmailUseCase(repo).call(
      email: email,
      password: password,
      passwordConfirmation: confirmation ?? password,
      displayName: displayName,
      handle: handle,
      acceptedTerms: terms,
    );

    test('registra y normaliza el handle a minúsculas', () async {
      final repo = _FakeAuthRepository();
      final result = await signUp(repo, handle: 'AnaGomez');

      expect(result.isSuccess, isTrue);
      expect(repo.lastHandle, 'anagomez');
      expect(repo.lastDisplayName, 'Ana');
    });

    test('sin aceptar los términos no crea la cuenta', () async {
      final repo = _FakeAuthRepository();
      final result = await signUp(repo, terms: false);

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(
        (result.failureOrNull! as ValidationFailure).field,
        'acceptedTerms',
      );
      expect(repo.signUpCalls, 0);
    });

    test('si las contraseñas no coinciden no crea la cuenta', () async {
      final repo = _FakeAuthRepository();
      final result = await signUp(repo, confirmation: 'otraCosa123');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.signUpCalls, 0);
    });

    test('una contraseña débil se rechaza antes de tocar la red', () async {
      final repo = _FakeAuthRepository();
      final result = await signUp(repo, password: 'todoletras');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.signUpCalls, 0);
    });

    test('un handle con caracteres inválidos se rechaza', () async {
      final repo = _FakeAuthRepository();
      final result = await signUp(repo, handle: 'ana gomez!');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.signUpCalls, 0);
    });

    test('valida el email antes que la contraseña', () async {
      // El orden importa para el mensaje que ve la persona: si los dos campos
      // están mal, se señala el primero del formulario.
      final repo = _FakeAuthRepository();
      final result = await signUp(repo, email: 'roto', password: 'x');

      final failure = result.failureOrNull! as ValidationFailure;
      expect(failure.field, 'email');
    });

    test(
      'NO consulta disponibilidad del handle: la verdad es del servidor',
      () async {
        // Entre consultar y dar de alta hay una ventana en la que otra persona
        // puede quedarse con el nombre. La transacción del servidor es la única
        // verificación que vale.
        final repo = _FakeAuthRepository();
        await signUp(repo);
        expect(repo.signUpCalls, 1);
      },
    );
  });

  group('SendPasswordResetUseCase', () {
    test('valida el formato antes de mandar', () async {
      final repo = _FakeAuthRepository();
      final result = await SendPasswordResetUseCase(repo).call('arroba-nada');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.resetCalls, 0);
    });

    test('manda el correo con el email normalizado', () async {
      final repo = _FakeAuthRepository();
      final result = await SendPasswordResetUseCase(
        repo,
      ).call('ANA@ascend.app');

      expect(result.isSuccess, isTrue);
      expect(repo.lastEmail, 'ana@ascend.app');
    });
  });

  group('ChangePasswordUseCase', () {
    test('rechaza cambiar la contraseña por la misma', () async {
      final repo = _FakeAuthRepository();
      final result = await ChangePasswordUseCase(repo).call(
        currentPassword: 'secreto123',
        newPassword: 'secreto123',
        confirmation: 'secreto123',
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.updatePasswordCalls, 0);
    });

    test('exige la contraseña actual', () async {
      final repo = _FakeAuthRepository();
      final result = await ChangePasswordUseCase(repo).call(
        currentPassword: '',
        newPassword: 'nuevaClave9',
        confirmation: 'nuevaClave9',
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.updatePasswordCalls, 0);
    });

    test('cambia la contraseña cuando todo está bien', () async {
      final repo = _FakeAuthRepository();
      final result = await ChangePasswordUseCase(repo).call(
        currentPassword: 'secreto123',
        newPassword: 'nuevaClave9',
        confirmation: 'nuevaClave9',
      );

      expect(result.isSuccess, isTrue);
      expect(repo.updatePasswordCalls, 1);
    });
  });

  group('DeleteAccountUseCase', () {
    test('sin confirmación explícita no borra nada', () async {
      final repo = _FakeAuthRepository();
      final result = await DeleteAccountUseCase(
        repo,
      ).call(password: 'secreto123', confirmed: false);

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.deleteCalls, 0);
    });

    test('sin contraseña no borra nada', () async {
      final repo = _FakeAuthRepository();
      final result = await DeleteAccountUseCase(
        repo,
      ).call(password: '', confirmed: true);

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.deleteCalls, 0);
    });

    test('borra con contraseña y confirmación', () async {
      final repo = _FakeAuthRepository();
      final result = await DeleteAccountUseCase(
        repo,
      ).call(password: 'secreto123', confirmed: true);

      expect(result.isSuccess, isTrue);
      expect(repo.deleteCalls, 1);
    });
  });

  group('UpdateProfileUseCase', () {
    test('recorta los espacios de la biografía', () async {
      final users = _FakeUserRepository();
      await UpdateProfileUseCase(
        users,
      ).call(uid: 'u1', bio: '   Corriendo mi primer 10k   ');

      expect(users.lastBio, 'Corriendo mi primer 10k');
    });

    test('rechaza una biografía demasiado larga', () async {
      final users = _FakeUserRepository();
      final result = await UpdateProfileUseCase(
        users,
      ).call(uid: 'u1', bio: 'x' * (kMaxBioLength + 1));

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(users.updateProfileCalls, 0);
    });

    test('sin cambios reales no escribe', () async {
      // Una escritura vacía igual actualizaría `updatedAt` y dispararía el
      // trigger de proyección sin motivo.
      final users = _FakeUserRepository();
      final result = await UpdateProfileUseCase(users).call(uid: 'u1');

      expect(result.isSuccess, isTrue);
      expect(users.updateProfileCalls, 0);
    });

    test('rechaza un nombre vacío', () async {
      final users = _FakeUserRepository();
      final result = await UpdateProfileUseCase(
        users,
      ).call(uid: 'u1', displayName: '   ');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(users.updateProfileCalls, 0);
    });
  });

  group('CheckHandleAvailabilityUseCase', () {
    test('valida el formato antes de consultar', () async {
      final users = _FakeUserRepository();
      final result = await CheckHandleAvailabilityUseCase(users).call('ab');

      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('informa cuando está tomado', () async {
      final users = _FakeUserRepository()..handleFree = false;
      final result = await CheckHandleAvailabilityUseCase(
        users,
      ).call('santino');

      expect(result.valueOrNull, isFalse);
    });
  });

  group('CompleteOnboardingUseCase', () {
    test('exige al menos un interés', () async {
      final users = _FakeUserRepository();
      final result = await CompleteOnboardingUseCase(
        users,
      ).call(uid: 'u1', interests: <String>[]);

      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });
}
