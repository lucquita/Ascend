import 'package:ascend_admin/features/auth/application/admin_session.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _user({
  UserRole role = UserRole.user,
  UserStatus status = UserStatus.active,
}) => AppUser(
  uid: 'u1',
  email: 'ana@ascend.app',
  displayName: 'Ana',
  handle: 'ana',
  createdAt: DateTime.utc(2026),
  role: role,
  status: status,
  emailVerified: true,
);

/// El guard del router es comodidad de navegación, no control de acceso —eso
/// son las reglas de Firestore—. Pero si se equivoca, alguien ve un panel que
/// no puede usar o queda encerrado afuera sin entender por qué.
void main() {
  group('resolveAdminSession', () {
    test('mientras se restaura la sesión, no se decide nada', () {
      // Decidir antes de tiempo hace parpadear el login en cada recarga.
      expect(
        resolveAdminSession(const AsyncLoading<AppUser?>()),
        AdminSessionState.unknown,
      );
    });

    test('sin sesión, afuera', () {
      expect(
        resolveAdminSession(const AsyncData<AppUser?>(null)),
        AdminSessionState.signedOut,
      );
    });

    test('un error leyendo la sesión deja afuera, no adentro', () {
      // Ante la duda, afuera. Es el mismo criterio que `UserRole.fromWire`.
      expect(
        resolveAdminSession(
          AsyncError<AppUser?>(StateError('token roto'), StackTrace.empty),
        ),
        AdminSessionState.signedOut,
      );
    });

    test('una cuenta común no entra al panel', () {
      expect(
        resolveAdminSession(AsyncData<AppUser?>(_user())),
        AdminSessionState.notAdmin,
      );
    });

    test('un administrador entra', () {
      expect(
        resolveAdminSession(AsyncData<AppUser?>(_user(role: UserRole.admin))),
        AdminSessionState.ready,
      );
    });

    test('un administrador suspendido NO entra', () {
      // La suspensión se evalúa antes que el rol: una cuenta de administrador
      // suspendida no puede administrar nada.
      expect(
        resolveAdminSession(
          AsyncData<AppUser?>(
            _user(role: UserRole.admin, status: UserStatus.suspended),
          ),
        ),
        AdminSessionState.suspended,
      );
    });

    test('con un valor resuelto nunca se queda en "no se sabe"', () {
      // El guard mira `isLoading && !hasValue`, no solo `isLoading`. Si mirara
      // solo lo segundo, cada refresco del token —que ocurre seguido, porque
      // el claim de rol se relee— expulsaría del panel a quien ya estaba
      // adentro.
      for (final user in <AppUser?>[
        null,
        _user(),
        _user(role: UserRole.admin),
      ]) {
        expect(
          resolveAdminSession(AsyncData<AppUser?>(user)),
          isNot(AdminSessionState.unknown),
        );
      }
    });
  });
}
