import 'dart:io';

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/remote/firestore_user_datasource.dart';
import 'package:ascend_data/src/dtos/user_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Implementación de [UserRepository] sobre Firestore y Storage.
class UserRepositoryImpl implements UserRepository {
  /// Crea el repositorio.
  const UserRepositoryImpl({
    required FirestoreUserDataSource userDataSource,
    required FirebaseStorage storage,
  }) : _users = userDataSource,
       _storage = storage;

  final FirestoreUserDataSource _users;
  final FirebaseStorage _storage;

  @override
  Stream<Result<AppUser>> watchUser(String uid) {
    // `guardStream` emite el fallo sin cerrar la suscripción: si se corta la
    // red, la pantalla muestra el aviso y se recupera sola al volver, en vez de
    // quedarse congelada para siempre.
    return guardStream(_users.watchUser(uid)).map(
      (result) => result.flatMap((snapshot) {
        if (!snapshot.exists) {
          return const Failed<AppUser>(
            NotFoundFailure(code: 'profile-missing'),
          );
        }
        return Success<AppUser>(UserDto.fromFirestore(snapshot));
      }),
    );
  }

  @override
  Future<Result<AppUser>> getUser(String uid) => runGuarded(() async {
    final snapshot = await _users.getUser(uid);
    if (!snapshot.exists) {
      throw const NotFoundFailure(code: 'profile-missing');
    }
    return UserDto.fromFirestore(snapshot);
  });

  @override
  Future<Result<void>> updateProfile({
    required String uid,
    String? displayName,
    String? bio,
    String? photoUrl,
  }) => runGuarded(
    () => _users.update(
      uid,
      UserDto.profileUpdate(
        displayName: displayName,
        bio: bio,
        photoUrl: photoUrl,
      ),
    ),
  );

  @override
  Future<Result<void>> updateSettings({
    required String uid,
    required UserSettings settings,
  }) => runGuarded(() => _users.update(uid, UserDto.settingsUpdate(settings)));

  @override
  Future<Result<bool>> isHandleAvailable(String handle) =>
      runGuarded(() => _users.isHandleAvailable(handle));

  @override
  Future<Result<void>> claimHandle({
    required String uid,
    required String handle,
  }) async =>
      // La reserva es una transacción del servidor (`registerProfile`). Que el
      // cliente no pueda hacerla es el punto: `handles` es `write: if false`.
      const Failed<void>(
        PermissionFailure(code: 'handle-claim-is-server-side'),
      );

  @override
  Future<Result<void>> completeOnboarding({
    required String uid,
    required List<String> interests,
  }) =>
      runGuarded(() => _users.update(uid, UserDto.onboardingUpdate(interests)));

  @override
  Future<Result<String>> uploadAvatar({
    required String uid,
    required String localPath,
  }) => runGuarded(() async {
    // Ruta fija por usuario: las reglas de Storage autorizan `avatars/{uid}/`
    // y un nombre estable evita acumular avatares viejos en cada cambio.
    final ref = _storage.ref('avatars/$uid/avatar.jpg');
    await ref.putFile(
      _fileAt(localPath),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  });

  /// Aísla la creación del `File` para que el resto sea testeable sin disco.
  static File _fileAt(String path) => File(path);
}
