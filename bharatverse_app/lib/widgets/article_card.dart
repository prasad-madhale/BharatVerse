import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/article.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_badge.dart';
import 'arrow_link.dart';
import 'highlighted_text.dart';

enum ArticleCardSize { featured, compact }

/// Article card -- the core content unit. `featured` is a side-by-side
/// hero (text left, image placeholder right) with a "Today's Article"
/// badge and a "Read More" link; `compact` is a thumbnail-left list row.
/// Mirrors the design system's ArticleCard component. In the compact card,
/// [highlight] terms are set in bold saffron (search results), and the tags
/// they appear in are listed, since a search can match through a tag alone.
///
/// Shows the article's featured image when it has one; falls back to a flat parchment block
/// (not the mockup's literal diagonal-hatch texture) when it doesn't, e.g. an older article
/// from before images were sourced automatically.
class ArticleCard extends StatelessWidget {
  final Article article;
  final ArticleCardSize size;
  final VoidCallback onTap;
  final List<String> highlight;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    this.size = ArticleCardSize.compact,
    this.highlight = const [],
  });

  @override
  Widget build(BuildContext context) {
    return size == ArticleCardSize.featured
        ? _buildFeatured(context)
        : _buildCompact(context);
  }

  Widget _buildFeatured(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.ink200),
            bottom: BorderSide(color: colors.ink200),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppBadge("Today's Article"),
            const SizedBox(height: AppSpacing.space2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title.toUpperCase(),
                        style: AppTypography.display2
                            .copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.space2),
                      Text(
                        article.dateAndReadingTime,
                        style: AppTypography.caption
                            .copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.space2),
                      Text(
                        article.summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppTypography.body.copyWith(color: colors.textBody),
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      Text('Read More →', style: arrowLinkStyle(context)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.space4),
                _thumbnail(context, width: 90, height: 150),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(BuildContext context,
      {required double width, required double height}) {
    final placeholderColor = context.colors.paper200;
    final url = article.imageUrl;
    if (url == null) {
      return Container(width: width, height: height, color: placeholderColor);
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (context, url) =>
          Container(width: width, height: height, color: placeholderColor),
      errorWidget: (context, url, error) =>
          Container(width: width, height: height, color: placeholderColor),
    );
  }

  /// The article's tags that contain a search term.
  List<String> get _matchedTags => article.tags
      .where((tag) => highlight.any((term) =>
          term.isNotEmpty && tag.toLowerCase().contains(term.toLowerCase())))
      .toList();

  Widget _buildCompact(BuildContext context) {
    final colors = context.colors;
    final matchedTags = _matchedTags;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderHairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _thumbnail(context, width: 68, height: 68),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HighlightedText(
                    article.title.toUpperCase(),
                    terms: highlight,
                    maxLines: 2,
                    style: AppTypography.headline.copyWith(
                        fontSize: 16, height: 1.3, color: colors.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    article.dateAndReadingTime,
                    style: AppTypography.caption
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 3),
                  HighlightedText(
                    article.summary,
                    terms: highlight,
                    maxLines: 2,
                    style: AppTypography.caption
                        .copyWith(color: colors.textSecondary),
                  ),
                  if (matchedTags.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    HighlightedText(
                      'Tagged: ${matchedTags.join(', ')}',
                      terms: highlight,
                      maxLines: 1,
                      style: AppTypography.caption
                          .copyWith(color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
