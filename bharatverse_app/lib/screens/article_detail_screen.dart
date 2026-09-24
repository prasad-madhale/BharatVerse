import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/article.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_back_bar.dart';
import '../widgets/app_tag.dart';
import '../widgets/article_image.dart';
import '../widgets/citation_item.dart';
import '../widgets/content_column.dart';
import '../widgets/like_button.dart';
import 'auth_screen.dart';

/// Opens [article], first noting the view so it stays in the offline cache.
Future<void> openArticle(
  BuildContext context,
  ApiClient apiClient,
  Article article,
) {
  unawaited(apiClient.markViewed(article));
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: article)),
  );
}

class ArticleDetailScreen extends StatelessWidget {
  final Article article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBackBar(
        title: 'ARTICLE',
        trailing: LikeButton(
          articleId: article.id,
          onRequireAuth: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
          ),
        ),
      ),
      body: ListView(
        padding: columnPadding(
          context,
          horizontal: AppSpacing.space5,
          vertical: AppSpacing.space5,
        ),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space5,
            ),
            decoration:
                BoxDecoration(border: Border.all(color: AppColors.ink200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(article.title.toUpperCase(),
                    style: AppTypography.display1),
                const SizedBox(height: AppSpacing.space4),
                Text(
                  '${article.dateAndReadingTime} · ${article.author}',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.space5),
                if (article.images.isNotEmpty)
                  ArticleImageView(image: article.images.first)
                else
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                        width: double.infinity, color: AppColors.paper200),
                  ),
                const SizedBox(height: AppSpacing.space5),
                for (final entry in article.sections.asMap().entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space5),
                    child: _Section(
                        section: entry.value,
                        isFirst:
                            entry.value.order == article.sections.first.order),
                  ),
                  for (final image in _inlineImagesAfter(entry.key, article))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.space5),
                      child: ArticleImageView(image: image),
                    ),
                ],
                if (article.tags.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.only(top: AppSpacing.space3),
                    decoration: const BoxDecoration(
                      border: Border(
                          top: BorderSide(color: AppColors.borderHairline)),
                    ),
                    child: Wrap(
                      spacing: AppSpacing.space2,
                      runSpacing: AppSpacing.space2,
                      children: article.tags.map((t) => AppTag(t)).toList(),
                    ),
                  ),
                if (article.citations.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.space4),
                  Text('SOURCES',
                      style: AppTypography.label
                          .copyWith(color: AppColors.textSecondary)),
                  for (final citation in article.citations)
                    CitationItem(citation: citation),
                ],
              ],
            ),
          ),
        ],
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

/// One article section: uppercase serif heading + body. The first section
/// gets a drop-cap treatment on its opening letter -- a large leading
/// character, not a true CSS-style float-wrap (Flutter has no built-in
/// equivalent; see plan notes).
class _Section extends StatelessWidget {
  final ArticleSection section;
  final bool isFirst;

  const _Section({required this.section, required this.isFirst});

  @override
  Widget build(BuildContext context) {
    final bodyStyleSheet = MarkdownStyleSheet(p: AppTypography.bodyLg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.heading.toUpperCase(), style: AppTypography.headline),
        const SizedBox(height: AppSpacing.space2),
        if (isFirst && section.content.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.content.substring(0, 1),
                style: AppTypography.display1
                    .copyWith(fontSize: 40 * 1.4, height: 0.8),
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
