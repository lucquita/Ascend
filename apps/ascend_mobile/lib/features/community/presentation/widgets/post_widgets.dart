import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';

/// Textos de presentación de [PostType].
extension PostTypePresentation on PostType {
  /// Etiqueta que encabeza la publicación.
  String get label => switch (this) {
    PostType.missionCompleted => 'completó una misión',
    PostType.goalCompleted => 'completó un objetivo',
    PostType.milestone => 'alcanzó un hito',
    PostType.reflection => 'compartió una reflexión',
  };

  /// Icono asociado.
  IconData get icon => switch (this) {
    PostType.missionCompleted => Icons.task_alt_rounded,
    PostType.goalCompleted => Icons.flag_rounded,
    PostType.milestone => Icons.emoji_events_outlined,
    PostType.reflection => Icons.chat_bubble_outline_rounded,
  };
}

/// Textos de presentación de [ReportReason].
extension ReportReasonPresentation on ReportReason {
  /// Etiqueta legible.
  String get label => switch (this) {
    ReportReason.spam => 'Spam o repetido',
    ReportReason.harassment => 'Acoso o agresión',
    ReportReason.nsfw => 'Contenido sexual o violento',
    ReportReason.fakeAchievement => 'Logro falso',
    ReportReason.violence => 'Violencia',
    ReportReason.other => 'Otro motivo',
  };
}

/// Avatar circular con iniciales de reserva.
class AuthorAvatar extends StatelessWidget {
  /// Crea el avatar.
  const AuthorAvatar({required this.author, this.radius = 20, super.key});

  /// Autor a mostrar.
  final PostAuthor? author;

  /// Radio del círculo.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final name = author?.displayName ?? '';
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.colors.primaryContainer,
      foregroundImage: author?.photoUrl == null
          ? null
          : NetworkImage(author!.photoUrl!),
      child: Text(
        _initials(name),
        style: context.texts.labelMedium?.copyWith(
          color: context.colors.onPrimaryContainer,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// Tarjeta de una publicación en el feed.
class PostCard extends StatefulWidget {
  /// Crea la tarjeta.
  const PostCard({
    required this.post,
    required this.onTap,
    required this.onLike,
    this.initiallyLiked = false,
    super.key,
  });

  /// Publicación.
  final Post post;

  /// Al tocar la tarjeta.
  final VoidCallback onTap;

  /// Al tocar el corazón. Recibe el estado deseado.
  final ValueChanged<bool> onLike;

  /// Si la persona ya había dado "me gusta".
  final bool initiallyLiked;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _liked = widget.initiallyLiked;
  late int _likes = widget.post.counters.likes;

  /// Aplica el like de forma optimista.
  ///
  /// El contador real lo mantiene un trigger y puede tardar un instante en
  /// llegar. Sin este ajuste local, tocar el corazón no haría nada visible
  /// durante ese lapso y la gente lo tocaría dos veces.
  void _toggle() {
    final next = !_liked;
    setState(() {
      _liked = next;
      _likes = (_likes + (next ? 1 : -1)).clamp(0, 1 << 30);
    });
    widget.onLike(next);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final author = post.author;

    return Padding(
      padding: const EdgeInsets.only(bottom: AscendSpacing.md),
      child: Material(
        color: context.colors.surface,
        borderRadius: AscendRadius.cardRadius,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: AscendRadius.cardRadius,
          child: Container(
            padding: AscendSpacing.card,
            decoration: BoxDecoration(
              borderRadius: AscendRadius.cardRadius,
              border: Border.all(color: context.colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AuthorAvatar(author: author),
                    const SizedBox(width: AscendSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            author?.displayName ?? 'Alguien',
                            style: context.texts.titleSmall,
                          ),
                          Text(
                            post.type.label,
                            style: context.texts.labelSmall?.copyWith(
                              color: context.ascend.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (author != null)
                      Text(
                        'Nv. ${author.level}',
                        style: context.texts.labelSmall?.copyWith(
                          color: context.ascend.auraOnSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (post.text.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AscendSpacing.md),
                  Text(post.text, style: context.texts.bodyMedium),
                ],
                if (post.source != null && !post.source!.isEmpty) ...<Widget>[
                  const SizedBox(height: AscendSpacing.md),
                  _SourceChip(source: post.source!, type: post.type),
                ],
                const SizedBox(height: AscendSpacing.md),
                Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: _toggle,
                      icon: Icon(
                        _liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _liked ? context.colors.error : null,
                      ),
                      tooltip: _liked ? 'Quitar me gusta' : 'Me gusta',
                    ),
                    Text('$_likes', style: context.texts.labelMedium),
                    const SizedBox(width: AscendSpacing.lg),
                    const Icon(Icons.mode_comment_outlined, size: 20),
                    const SizedBox(width: AscendSpacing.sm),
                    Text(
                      '${post.counters.comments}',
                      style: context.texts.labelMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Referencia al logro, con el Aura que otorgó.
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source, required this.type});

  final PostSource source;
  final PostType type;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AscendSpacing.md),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AscendRadius.md),
    ),
    child: Row(
      children: <Widget>[
        Icon(type.icon, size: 18, color: context.ascend.success),
        const SizedBox(width: AscendSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                source.missionTitle ?? source.goalTitle ?? 'Un logro',
                style: context.texts.labelLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (source.missionTitle != null && source.goalTitle != null)
                Text(
                  source.goalTitle!,
                  style: context.texts.labelSmall?.copyWith(
                    color: context.ascend.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        if (source.auraEarned > 0) AuraBadge(amount: source.auraEarned),
      ],
    ),
  );
}

/// Fila de un comentario.
class CommentTile extends StatelessWidget {
  /// Crea la fila.
  const CommentTile({required this.comment, this.onDelete, super.key});

  /// Comentario.
  final Comment comment;

  /// Acción de borrado, solo para el autor.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AscendSpacing.lg),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AuthorAvatar(author: comment.author, radius: 16),
        const SizedBox(width: AscendSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                comment.author?.displayName ?? 'Alguien',
                style: context.texts.labelLarge,
              ),
              const SizedBox(height: AscendSpacing.xxs),
              Text(comment.text, style: context.texts.bodyMedium),
            ],
          ),
        ),
        if (onDelete != null)
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Borrar comentario',
          ),
      ],
    ),
  );
}
