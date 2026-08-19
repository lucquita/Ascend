/// Casos de uso del perfil.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/app_user.dart';
import 'package:ascend_domain/src/repositories/repositories.dart';

/// Longitud máxima de la biografía. Coincide con la validación del servidor.
const int kMaxBioLength = 160;

/// Observa el perfil propio en tiempo real.
class WatchProfileUseCase {
  /// Crea el caso de uso.
  const WatchProfileUseCase(this._users);

  final UserRepository _users;

  /// Emite el perfil cada vez que cambia.
  Stream<Result<AppUser>> call(String uid) => _users.watchUser(uid);
}

/// Actualiza los campos editables del perfil.
class UpdateProfileUseCase {
  /// Crea el caso de uso.
  const UpdateProfileUseCase(this._users);

  final UserRepository _users;

  /// Guarda nombre, biografía y avatar.
  ///
  /// El handle **no** se toca acá. Cambiarlo implica liberar el anterior y
  /// reclamar el nuevo en una transacción del servidor, y además rompe los
  /// enlaces `@handle` que otras personas ya compartieron. Es una operación
  /// distinta, no un campo más de este formulario.
  Future<Result<void>> call({
    required String uid,
    String? displayName,
    String? bio,
    String? photoUrl,
  }) async {
    String? cleanName;
    if (displayName != null) {
      final validName = Validators.displayName(displayName);
      if (validName case Failed<String>(:final failure)) {
        return Failed<void>(failure);
      }
      cleanName = validName.valueOrNull;
    }

    String? cleanBio;
    if (bio != null) {
      final trimmed = bio.trim();
      if (trimmed.length > kMaxBioLength) {
        return const Failed<void>(
          ValidationFailure(messageKey: 'validation.bio.tooLong', field: 'bio'),
        );
      }
      cleanBio = trimmed;
    }

    // Nada que guardar: se evita una escritura y un `updatedAt` inútil que
    // dispararía el trigger de proyección sin motivo.
    if (cleanName == null && cleanBio == null && photoUrl == null) {
      return const Success<void>(null);
    }

    return _users.updateProfile(
      uid: uid,
      displayName: cleanName,
      bio: cleanBio,
      photoUrl: photoUrl,
    );
  }
}

/// Comprueba si un handle está disponible.
class CheckHandleAvailabilityUseCase {
  /// Crea el caso de uso.
  const CheckHandleAvailabilityUseCase(this._users);

  final UserRepository _users;

  /// Devuelve `true` si el handle está libre.
  ///
  /// El resultado es orientativo: entre esta consulta y el alta, otra persona
  /// puede quedarse con el nombre. La única fuente de verdad es la transacción
  /// del servidor. Sirve para avisar mientras se escribe, no para autorizar.
  Future<Result<bool>> call(String handle) async {
    final validHandle = Validators.handle(handle);
    if (validHandle case Failed<String>(:final failure)) {
      return Failed<bool>(failure);
    }
    return _users.isHandleAvailable(validHandle.valueOrNull!);
  }
}

/// Sube el avatar y devuelve su URL.
class UploadAvatarUseCase {
  /// Crea el caso de uso.
  const UploadAvatarUseCase(this._users);

  final UserRepository _users;

  /// Sube la imagen y actualiza el perfil con la URL resultante.
  ///
  /// Las dos operaciones van juntas porque una foto subida que no quedó
  /// asociada al perfil es un archivo huérfano que nadie va a limpiar.
  Future<Result<String>> call({
    required String uid,
    required String localPath,
  }) async {
    final uploaded = await _users.uploadAvatar(uid: uid, localPath: localPath);
    if (uploaded case Failed<String>(:final failure)) {
      return Failed<String>(failure);
    }

    final url = uploaded.valueOrNull!;
    final saved = await _users.updateProfile(uid: uid, photoUrl: url);
    return saved.map((_) => url);
  }
}

/// Marca el onboarding como terminado.
class CompleteOnboardingUseCase {
  /// Crea el caso de uso.
  const CompleteOnboardingUseCase(this._users);

  final UserRepository _users;

  /// Guarda los intereses y cierra el onboarding.
  Future<Result<void>> call({
    required String uid,
    required List<String> interests,
  }) async {
    if (interests.isEmpty) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.interests.required',
          field: 'interests',
        ),
      );
    }
    return _users.completeOnboarding(uid: uid, interests: interests);
  }
}

/// Actualiza los ajustes de la persona.
class UpdateSettingsUseCase {
  /// Crea el caso de uso.
  const UpdateSettingsUseCase(this._users);

  final UserRepository _users;

  /// Guarda los ajustes completos.
  Future<Result<void>> call({
    required String uid,
    required UserSettings settings,
  }) => _users.updateSettings(uid: uid, settings: settings);
}
