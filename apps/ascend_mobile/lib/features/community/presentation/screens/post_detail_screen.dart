import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:ascend_mobile/features/community/application/community_controller.dart';
import 'package:ascend_mobile/features/community/presentation/widgets/post_widgets.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Una publicación concreta, en vivo.
// Sin anotación explícita: `StreamProviderFamily` no está exportado.
final postDetailProvider = StreamProvider.family<Result<Post>, String>(
  (ref, postId) => ref.watch(postRepositoryProvider).watchPost(postId),
  name: 'postDetail',
);

/// Detalle de una publicación con su hilo de comentarios.
class PostDetailScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const PostDetailScreen({required this.postId, super.key});

  /// Id de la publicación.
  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final ok = await ref
        .read(communityControllerProvider.notifier)
        .comment(postId: widget.postId, text: _comment.text);
    if (ok) {
      _comment.clear();
    }
  }

  Future<void> _report(Post post) async {
    final reason = await showModalBottomSheet<ReportReason>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(AscendSpacing.lg),
              child: Text('¿Por qué querés reportarlo?'),
            ),
            for (final reason in ReportReason.values)
              ListTile(
                title: Text(reason.label),
                onTap: () => Navigator.of(sheetContext).pop(reason),
              ),
          ],
        ),
      ),
    );

    if (reason == null || !mounted) {
      return;
    }

    final ok = await ref
        .read(communityControllerProvider.notifier)
        .report(
          targetId: post.id,
          targetOwnerId: post.authorId,
          reason: reason,
        );

    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gracias. Lo vamos a revisar.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postDetailProvider(widget.postId));
    final action = ref.watch(communityControllerProvider);
    final failure = action.error is Failure ? action.error! as Failure : null;
    final uid = ref.watch(currentUserProvider)?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Publicación')),
      body: AsyncStateBuilder<Result<Post>>(
        value: post,
        onRetry: () => ref.invalidate(postDetailProvider(widget.postId)),
        data: (Result<Post> result) => result.fold<Widget>(
          onFailure: (Failure f) => ErrorStateView(
            failure: f,
            onRetry: () => ref.invalidate(postDetailProvider(widget.postId)),
          ),
          onSuccess: (Post value) => Column(
            children: <Widget>[
              if (failure != null)
                ErrorStateView(failure: failure, compact: true),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AscendSpacing.lg),
                  children: <Widget>[
                    PostCard(
                      post: value,
                      onTap: () {},
                      onLike: (liked) => ref
                          .read(communityControllerProvider.notifier)
                          .toggleLike(postId: value.id, liked: liked),
                    ),
                    Row(
                      children: <Widget>[
                        if (uid != null && value.isAuthoredBy(uid))
                          TextButton.icon(
                            onPressed: () async {
                              final ok = await ref
                                  .read(communityControllerProvider.notifier)
                                  .deletePost(value.id);
                              if (ok && context.mounted) {
                                context.pop();
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Borrar'),
                          )
                        else
                          TextButton.icon(
                            onPressed: () => _report(value),
                            icon: const Icon(Icons.flag_outlined),
                            label: const Text('Reportar'),
                          ),
                      ],
                    ),
                    const Divider(height: AscendSpacing.xxl),
                    Text('Comentarios', style: context.texts.titleMedium),
                    const SizedBox(height: AscendSpacing.md),
                    _CommentList(postId: widget.postId, viewerId: uid),
                  ],
                ),
              ),
              _CommentComposer(
                controller: _comment,
                enabled: !action.isLoading,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentList extends ConsumerWidget {
  const _CommentList({required this.postId, required this.viewerId});

  final String postId;
  final String? viewerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(commentsProvider(postId));

    return AsyncStateBuilder<Result<List<Comment>>>(
      value: comments,
      // Skeletons en `Column`: este widget vive dentro del `ListView` del
      // detalle, y anidar un scroll vertical rompe el layout.
      loading: const Column(
        children: <Widget>[
          AscendSkeleton(height: 48),
          SizedBox(height: AscendSpacing.sm),
          AscendSkeleton(height: 48),
        ],
      ),
      isEmpty: (result) => result.valueOrNull?.isEmpty ?? false,
      emptyState: const EmptyStateConfig(
        icon: Icons.mode_comment_outlined,
        title: 'Sin comentarios',
        message: 'Sé la primera persona en decir algo.',
      ),
      data: (Result<List<Comment>> result) => result.fold<Widget>(
        onSuccess: (List<Comment> items) => Column(
          children: <Widget>[
            for (final comment in items)
              CommentTile(
                comment: comment,
                onDelete: viewerId != null && comment.isAuthoredBy(viewerId!)
                    ? () => ref
                          .read(commentRepositoryProvider)
                          .deleteComment(postId: postId, commentId: comment.id)
                    : null,
              ),
          ],
        ),
        onFailure: (Failure f) => ErrorStateView(failure: f, compact: true),
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.onSend,
    required this.enabled,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AscendSpacing.lg,
        0,
        AscendSpacing.lg,
        AscendSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: AscendTextField(
              controller: controller,
              label: 'Escribí un comentario',
              maxLength: kMaxCommentLength,
              textInputAction: TextInputAction.send,
              enabled: enabled,
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: AscendSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(top: AscendSpacing.sm),
            child: IconButton.filled(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Enviar',
            ),
          ),
        ],
      ),
    ),
  );
}
