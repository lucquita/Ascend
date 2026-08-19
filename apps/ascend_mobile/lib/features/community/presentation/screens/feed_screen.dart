import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_mobile/features/community/application/community_controller.dart';
import 'package:ascend_mobile/features/community/presentation/widgets/post_widgets.dart';
import 'package:ascend_mobile/router/routes.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Feed de la comunidad.
///
/// Paginado con cursores e infinite scroll (ADR-006). El autor viene
/// desnormalizado dentro de cada post, así que una página de 20 cuesta **20
/// lecturas, no 40**: sin eso, cada publicación exigiría leer también su perfil.
class FeedScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    // Se pide la página siguiente antes de tocar el fondo para que la lista no
    // se corte visiblemente. El controlador ignora las llamadas repetidas.
    final threshold = _scroll.position.maxScrollExtent - 400;
    if (_scroll.position.pixels >= threshold) {
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final action = ref.watch(communityControllerProvider);
    final failure = action.error is Failure ? action.error! as Failure : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Comunidad')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.createPost),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Publicar'),
      ),
      body: Column(
        children: <Widget>[
          if (failure != null) ErrorStateView(failure: failure, compact: true),
          Expanded(
            child: AsyncStateBuilder<Result<FeedState>>(
              value: feed,
              onRetry: () => ref.invalidate(feedProvider),
              isEmpty: (result) => result.valueOrNull?.posts.isEmpty ?? false,
              emptyState: EmptyStateConfig(
                icon: Icons.public_outlined,
                title: 'El feed está tranquilo',
                message:
                    'Acá solo aparecen logros reales. Completá una misión y '
                    'sé el primero en publicar.',
                actionLabel: 'Escribir algo',
                onAction: () => context.push(Routes.createPost),
              ),
              data: (Result<FeedState> result) => result.fold<Widget>(
                onFailure: (Failure f) => ErrorStateView(
                  failure: f,
                  onRetry: () => ref.invalidate(feedProvider),
                ),
                onSuccess: (FeedState state) => RefreshIndicator(
                  onRefresh: () => ref.read(feedProvider.notifier).refresh(),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      AscendSpacing.lg,
                      AscendSpacing.md,
                      AscendSpacing.lg,
                      AscendSpacing.huge,
                    ),
                    // Una fila extra al final para el indicador de carga.
                    itemCount: state.posts.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= state.posts.length) {
                        return const Padding(
                          padding: EdgeInsets.all(AscendSpacing.lg),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }

                      final post = state.posts[index];
                      return PostCard(
                        post: post,
                        onTap: () => context.push(Routes.postDetail(post.id)),
                        onLike: (liked) => ref
                            .read(communityControllerProvider.notifier)
                            .toggleLike(postId: post.id, liked: liked),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
