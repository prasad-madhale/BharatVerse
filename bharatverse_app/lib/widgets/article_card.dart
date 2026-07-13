import 'package:flutter/material.dart';

import '../models/article.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_badge.dart';

enum ArticleCardSize { featured, compact }

/// Article card -- the core content unit. `featured` is a side-by-side
/// hero (text left, image placeholder right) with a "Today's Article"
/// badge and a "Read More" link; `compact` is a thumbnail-left list row.
/// Mirrors the design system's ArticleCard component.
///
/// Image placeholders are a flat parchment block, not the mockup's literal
/// diagonal-hatch texture -- see roadmap/plan notes on why that texture
/// wasn't worth building given no real photography exists yet.
class ArticleCard extends StatelessWidget {
  final Article article;
  final ArticleCardSize size;
  final VoidCallback onTap;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    this.size = ArticleCardSize.compact,
  });

  @override
  Widget build(BuildContext context) {
    return size == ArticleCardSize.featured
        ? _buildFeatured()
        : _buildCompact();
  }

  Widget _buildFeatured() {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.ink200),
            bottom: BorderSide(color: AppColors.ink200),
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
                        style: AppTypography.display2,
                      ),
                      const SizedBox(height: AppSpacing.space2),
                      Text(
                        article.summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body,
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      Text(
                        'Read More →',
                        style: AppTypography.ui.copyWith(
                          fontFamily: AppTypography.headline.fontFamily,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.space4),
                Container(
                  width: 90,
                  height: 150,
                  color: AppColors.paper200,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact() {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderHairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 68, height: 68, color: AppColors.paper200),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.headline
                        .copyWith(fontSize: 16, height: 1.3),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    article.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
