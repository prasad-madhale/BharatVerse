import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Underlined serif style for links that end in an arrow, like "Read More →".
TextStyle get arrowLinkStyle => AppTypography.ui.copyWith(
      fontFamily: AppTypography.headline.fontFamily,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      color: AppColors.textPrimary,
    );

/// A text link such as "Browse the archive →".
class ArrowLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const ArrowLink({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
        child: Text('$label →', style: arrowLinkStyle),
      ),
    );
  }
}
