import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/features/community/application/community_controller.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Misiones completadas que todavía se pueden publicar.
///
/// Se ofrecen como origen del post para que publicar un logro sea elegir de una
/// lista y no escribir a mano: la premisa del producto es que el feed muestre
/// logros reales, y la interfaz tiene que hacer que ese sea el camino fácil.
final FutureProvider<List<Mission>> publishableMissionsProvider =
    FutureProvider<List<Mission>>((ref) async {
      final uid = ref.watch(currentUserProvider)?.uid;
      if (uid == null) {
        return const <Mission>[];
      }
      final result = await ref
          .read(missionRepositoryProvider)
          .getHistory(uid: uid);
      return result.fold(
        onSuccess: (page) => page.items,
        onFailure: (_) => const <Mission>[],
      );
    }, name: 'publishableMissions');

/// Alta de una publicación.
class CreatePostScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final TextEditingController _text = TextEditingController();
  Mission? _selected;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    FocusScope.of(context).unfocus();
    final controller = ref.read(communityControllerProvider.notifier);

    final id = _selected == null
        ? await controller.publishReflection(_text.text)
        : await controller.publishMission(
            mission: _selected!,
            text: _text.text,
          );

    if (id != null && mounted) {
      // Se recarga el feed para que la publicación aparezca al volver: el feed
      // es paginado, no un stream, así que no se entera solo.
      ref.invalidate(feedProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityControllerProvider);
    final isSaving = state.isLoading;
    final failure = state.error is Failure ? state.error! as Failure : null;
    final missions = ref.watch(publishableMissionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Publicar')),
      body: ListView(
        padding: const EdgeInsets.all(AscendSpacing.lg),
        children: <Widget>[
          if (failure != null) ...<Widget>[
            ErrorStateView(failure: failure, compact: true),
            const SizedBox(height: AscendSpacing.lg),
          ],
          Text('¿Qué querés compartir?', style: context.texts.labelLarge),
          const SizedBox(height: AscendSpacing.sm),
          missions.when(
            loading: () => const AscendSkeleton(height: 40),
            error: (_, _) => const SizedBox.shrink(),
            data: (items) => Wrap(
              spacing: AscendSpacing.sm,
              runSpacing: AscendSpacing.sm,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Una reflexión'),
                  selected: _selected == null,
                  onSelected: isSaving
                      ? null
                      : (_) => setState(() => _selected = null),
                ),
                for (final mission in items)
                  ChoiceChip(
                    label: Text(mission.title, overflow: TextOverflow.ellipsis),
                    selected: _selected?.id == mission.id,
                    onSelected: isSaving
                        ? null
                        : (_) => setState(() => _selected = mission),
                  ),
              ],
            ),
          ),
          if (missions.value?.isEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: AscendSpacing.sm),
              child: Text(
                'Todavía no completaste ninguna misión, así que por ahora solo '
                'podés publicar una reflexión.',
                style: context.texts.bodySmall?.copyWith(
                  color: context.ascend.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: AscendSpacing.xl),
          AscendTextField(
            controller: _text,
            label: _selected == null ? 'Tu reflexión' : 'Contá cómo fue',
            hint: _selected == null
                ? 'Hoy me costó, pero seguí'
                : 'Opcional: el logro ya habla por sí solo',
            maxLength: kMaxPostLength,
            maxLines: 6,
            minLines: 3,
            textInputAction: TextInputAction.newline,
            enabled: !isSaving,
            onChanged: (_) =>
                ref.read(communityControllerProvider.notifier).clearError(),
          ),
          const SizedBox(height: AscendSpacing.xl),
          AscendButton(
            label: 'Publicar',
            isLoading: isSaving,
            onPressed: isSaving ? null : _publish,
          ),
        ],
      ),
    );
  }
}
