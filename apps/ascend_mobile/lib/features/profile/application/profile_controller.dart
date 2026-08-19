import 'package:ascend_data/ascend_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Orquesta la edición del perfil.
class ProfileController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Guarda nombre y biografía.
  ///
  /// Devuelve `true` si se guardó, para que la pantalla decida si cerrarse.
  Future<bool> save({
    required String uid,
    required String displayName,
    required String bio,
  }) async {
    state = const AsyncLoading<void>();

    final result = await guardResult(
      () => ref
          .read(updateProfileUseCaseProvider)
          .call(uid: uid, displayName: displayName, bio: bio),
    );

    return result.fold(
      onSuccess: (_) {
        state = const AsyncData<void>(null);
        return true;
      },
      onFailure: (failure) {
        state = AsyncError<void>(
          failure,
          failure.stackTrace ?? StackTrace.empty,
        );
        return false;
      },
    );
  }

  /// Descarta el error mostrado.
  void clearError() {
    if (state.hasError) {
      state = const AsyncData<void>(null);
    }
  }
}

/// Controlador de la edición de perfil.
final NotifierProvider<ProfileController, AsyncValue<void>>
profileControllerProvider =
    NotifierProvider<ProfileController, AsyncValue<void>>(
      ProfileController.new,
      name: 'profileController',
    );
