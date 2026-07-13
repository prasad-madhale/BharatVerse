import 'package:flutter/material.dart';

import '../models/article.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// One row in the "Sources" list at the bottom of an article. Mirrors the
/// design system's CitationItem component.
class CitationItem extends StatelessWidget {
  final ArticleCitation citation;

  const CitationItem({super.key, required this.citation});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderHairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            citation.sourceName.toUpperCase(),
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 12 * 0.02,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            citation.text,
            style: AppTypography.caption.copyWith(color: AppColors.textLink),
          ),
        ],
      ),
    );
  }
}
