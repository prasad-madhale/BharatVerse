import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/article.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'highlighted_text.dart';
import 'save_button.dart';

enum ArticleCardSize { featured, compact }

/// Article card -- the core content unit. `featured` is a rounded hero image
/// over era/title/summary with a "Read · Nmin" pill and a bookmark button;
/// `compact` is a rounded-thumbnail-left list row with the same pill and
/// bookmark. Mirrors the design system's ArticleCard component. In the
/// compact card, when [highlight] terms are given (search results), the
/// matched terms are set in bold saffron in an additional summary/tags
/// block beneath the header, since a search can match through a tag or the
/// body alone and the reader should see why a result matched.
///
/// Shows the article's featured image when it has one; falls back to a flat parchment block
/// when it doesn't, e.g. an older article from before images were sourced automatically.
class ArticleCard extends StatelessWidget {
  final Article article;
  final ArticleCardSize size;
  final VoidCallback onTap;
  final VoidCallback onRequireAuth;
  final List<String> highlight;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    required this.onRequireAuth,
    this.size = ArticleCardSize.compact,
    this.highlight = const [],
  });

  @override
  Widget build(BuildContext context) {
    return size == ArticleCardSize.featured
        ? _buildFeatured(context)
        : _buildCompact(context);
  }

  /// "Today's story · Gupta Empire", or without the era when the article
  /// predates that field.
  String _eraLine(String prefix) =>
      article.era.isEmpty ? prefix : '$prefix · ${article.era}';

  Widget _buildFeatured(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                decoration: BoxDecoration(boxShadow: colors.shadowArt),
                child: _thumbnail(context),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            _eraLine("Today's story"),
            style: AppTypography.ui.copyWith(
                fontSize: 13, fontWeight: FontWeight.w600, color: colors.tint),
          ),
          const SizedBox(height: 4),
          Text(
            article.title,
            style: AppTypography.display2.copyWith(
              fontSize: 25.6,
              height: 1.18,
              letterSpacing: -0.38,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            article.summary,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.ui.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space3),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                height: 36,
                decoration: BoxDecoration(
                  color: colors.cta,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 16, color: colors.ctaFg),
                    const SizedBox(width: 7),
                    Text('Read · ${article.readingTimeMinutes} min',
                        style: AppTypography.ui.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.ctaFg)),
                  ],
                ),
              ),
              const Spacer(),
              SaveButton(
                articleId: article.id,
                onRequireAuth: onRequireAuth,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(BuildContext context, {double? width, double? height}) {
    final placeholderColor = context.colors.paper100;
    final url = article.imageUrl;
    final colorFilter = context.colors.imageFilter;
    if (url == null) {
      return Container(width: width, height: height, color: placeholderColor);
    }
    return ColorFiltered(
      colorFilter: colorFilter,
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (context, url) =>
            Container(width: width, height: height, color: placeholderColor),
        errorWidget: (context, url, error) =>
            Container(width: width, height: height, color: placeholderColor),
      ),
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
          border: Border(bottom: BorderSide(color: colors.sep)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Container(
                decoration: BoxDecoration(boxShadow: colors.shadowArt),
                child: _thumbnail(context, width: 84, height: 84),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${article.shortDate}${article.era.isEmpty ? '' : ' · ${article.era}'}',
                    style: AppTypography.caption.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary),
                  ),
                  const SizedBox(height: 3),
                  HighlightedText(
                    article.title,
                    terms: highlight,
                    maxLines: 2,
                    style: AppTypography.headline.copyWith(
                      fontSize: 16.8,
                      height: 1.28,
                      letterSpacing: -0.08,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        height: 28,
                        decoration: BoxDecoration(
                          color: colors.accentPrimaryTint,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_outlined,
                                size: 13, color: colors.tint),
                            const SizedBox(width: 5),
                            Text('${article.readingTimeMinutes} min',
                                style: AppTypography.caption.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: colors.tint)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      SaveButton(
                        articleId: article.id,
                        onRequireAuth: onRequireAuth,
                      ),
                    ],
                  ),
                  if (highlight.isNotEmpty) ...[
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
