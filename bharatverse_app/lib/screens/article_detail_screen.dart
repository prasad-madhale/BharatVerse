import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../services/reading_history.dart';
import '../state/auth_state.dart';
import '../state/like_state.dart';
import '../state/save_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_tag.dart';
import '../widgets/article_image.dart';
import '../widgets/citation_item.dart';
import '../widgets/content_column.dart';
import '../widgets/glass_surface.dart';
import 'auth_screen.dart';

/// Opens [article], first noting the view so it stays in the offline cache
/// and in the Library screen's "Recently read".
Future<void> openArticle(
  BuildContext context,
  ApiClient apiClient,
  Article article,
) {
  unawaited(apiClient.markViewed(article));
  // Best-effort: a widget test that doesn't care about Library's "Recently
  // read" won't have registered a ReadingHistory, and missing one entry
  // there is harmless, unlike the offline cache markViewed keeps.
  try {
    unawaited(context.read<ReadingHistory>().recordOpened(article.id));
  } catch (_) {}
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: article)),
  );
}

class ArticleDetailScreen extends StatelessWidget {
  final Article article;

  const ArticleDetailScreen({super.key, required this.article});

  void _requireAuth(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: Stack(
        children: [
          ListView(
            children: [
              ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (article.images.isNotEmpty)
                      ArticleImageView(image: article.images.first)
                    else
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Container(
                            width: double.infinity, color: colors.paper100),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.space5,
                        AppSpacing.space5,
                        AppSpacing.space5,
                        AppSpacing.space6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${article.shortDate} · ${article.readingTimeMinutes} min read',
                            style: AppTypography.caption.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            article.title,
                            style: AppTypography.display1.copyWith(
                              fontSize: 31.2,
                              height: 1.15,
                              letterSpacing: -0.624,
                              color: colors.textPrimary,
                            ),
                          ),
                          if (article.era.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              article.era,
                              style: AppTypography.ui.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: colors.tint),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.space4),
                          Row(
                            children: [
                              _SaveToggle(
                                  articleId: article.id,
                                  onRequireAuth: () => _requireAuth(context)),
                              const SizedBox(width: AppSpacing.space2),
                              _LikeToggle(
                                  articleId: article.id,
                                  onRequireAuth: () => _requireAuth(context)),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                top: AppSpacing.space5,
                                bottom: AppSpacing.space3),
                            child: Container(
                              height: 0.5,
                              color: colors.sep,
                            ),
                          ),
                          for (final entry
                              in article.sections.asMap().entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppSpacing.space5),
                              child: _Section(
                                  section: entry.value,
                                  isFirst: entry.value.order ==
                                      article.sections.first.order),
                            ),
                            for (final image
                                in _inlineImagesAfter(entry.key, article))
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.space5),
                                child: ArticleImageView(image: image),
                              ),
                          ],
                          if (article.tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppSpacing.space6),
                              child: Wrap(
                                spacing: AppSpacing.space2,
                                runSpacing: AppSpacing.space2,
                                children:
                                    article.tags.map((t) => AppTag(t)).toList(),
                              ),
                            ),
                          if (article.citations.isNotEmpty) ...[
                            Text('Sources',
                                style: AppTypography.headline.copyWith(
                                    fontSize: 20.8,
                                    letterSpacing: -0.208,
                                    color: colors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(
                              'Every claim in this story traces to one of these.',
                              style: AppTypography.caption
                                  .copyWith(color: colors.textSecondary),
                            ),
                            for (final citation in article.citations)
                              CitationItem(citation: citation),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              bottom: false,
              child: GlassSurface(
                height: 44,
                width: 44,
                child: IconButton(
                  icon: Icon(Icons.chevron_left, color: colors.textPrimary),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill button matching the mockup's Save/Like pair: filled with an accent
/// once active, otherwise a neutral sunken background. Bespoke rather than
/// [SaveButton]/[LikeButton] (icon-only, used elsewhere): this pair shows a
/// label that changes with the state too.
class _SaveToggle extends StatelessWidget {
  final String articleId;
  final VoidCallback onRequireAuth;

  const _SaveToggle({required this.articleId, required this.onRequireAuth});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final authState = context.watch<AuthState>();
    final saveState = context.watch<SaveState>();
    final saved = saveState.isSaved(articleId);
    return _ActionPill(
      icon: saved ? Icons.bookmark : Icons.bookmark_border,
      label: saved ? 'Saved' : 'Save',
      background: saved ? colors.cta : colors.surfaceSunken,
      foreground: saved ? colors.ctaFg : colors.textPrimary,
      onTap: () async {
        if (!authState.isAuthenticated) {
          onRequireAuth();
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        try {
          await saveState.toggleSave(articleId);
        } on ApiException catch (e) {
          messenger.showSnackBar(SnackBar(
              content: Text(e.statusCode == null
                  ? e.message
                  : 'Could not update your save (${e.statusCode}). Please try again.')));
        }
      },
    );
  }
}

class _LikeToggle extends StatelessWidget {
  final String articleId;
  final VoidCallback onRequireAuth;

  const _LikeToggle({required this.articleId, required this.onRequireAuth});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final authState = context.watch<AuthState>();
    final likeState = context.watch<LikeState>();
    final liked = likeState.isLiked(articleId);
    return _ActionPill(
      icon: liked ? Icons.favorite : Icons.favorite_border,
      label: liked ? 'Liked' : 'Like',
      background: liked ? colors.accentPrimaryTint : colors.surfaceSunken,
      foreground: liked ? colors.tint : colors.textPrimary,
      onTap: () async {
        if (!authState.isAuthenticated) {
          onRequireAuth();
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        try {
          await likeState.toggleLike(articleId);
        } on ApiException catch (e) {
          messenger.showSnackBar(SnackBar(
              content: Text(e.statusCode == null
                  ? e.message
                  : 'Could not update your like (${e.statusCode}). Please try again.')));
        }
      },
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 7),
                Text(label,
                    style: AppTypography.ui.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: foreground)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline images (article.images, skipping the hero at index 0) that belong right after
/// [sectionIndex], spread evenly across the article's sections rather than clustering at the top.
List<ArticleImage> _inlineImagesAfter(int sectionIndex, Article article) {
  final inline = article.images.skip(1).toList();
  if (inline.isEmpty) return const [];
  final sectionCount = article.sections.length;
  return [
    for (var i = 0; i < inline.length; i++)
      if (_inlineImagePosition(i, inline.length, sectionCount) == sectionIndex)
        inline[i],
  ];
}

int _inlineImagePosition(int imageIndex, int totalImages, int sectionCount) {
  final slot = ((imageIndex + 1) * sectionCount / (totalImages + 1)).floor();
  return slot.clamp(0, sectionCount - 1);
}

/// One article section: serif heading + body. The first section gets a
/// drop-cap treatment on its opening letter -- a large leading character,
/// not a true CSS-style float-wrap (Flutter has no built-in equivalent; see
/// plan notes).
class _Section extends StatelessWidget {
  final ArticleSection section;
  final bool isFirst;

  const _Section({required this.section, required this.isFirst});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyleSheet = MarkdownStyleSheet(
      p: AppTypography.bodyLg.copyWith(color: colors.textBody),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.heading,
          style: AppTypography.headline.copyWith(
              fontSize: 20.8, letterSpacing: -0.104, color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        if (isFirst && section.content.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.content.substring(0, 1),
                style: AppTypography.display1.copyWith(
                    fontSize: 40 * 1.4, height: 0.8, color: colors.tint),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: MarkdownBody(
                  data: section.content.substring(1),
                  styleSheet: bodyStyleSheet,
                ),
              ),
            ],
          )
        else
          MarkdownBody(data: section.content, styleSheet: bodyStyleSheet),
      ],
    );
  }
}
