import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum AppTagTone { neutral, green, saffron }

/// Small rounded pill for article tags. Mirrors the design system's Tag
/// component (variant="pill" only -- variant="tab" is for category filters,
/// which don't exist yet, so it's not implemented here).
class AppTag extends StatelessWidget {
  final String text;
  final AppTagTone tone;

  const AppTag(this.text, {super.key, this.tone = AppTagTone.neutral});

  ({Color background, Color foreground}) get _colors {
    switch (tone) {
      case AppTagTone.neutral:
        return (
          background: AppColors.paper100,
          foreground: AppColors.textSecondary
        );
      case AppTagTone.green:
        return (
          background: AppColors.accentSecondaryTint,
          foreground: AppColors.green700
        );
      case AppTagTone.saffron:
        return (
          background: AppColors.accentPrimaryTint,
          foreground: AppColors.saffron600
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3, vertical: 5),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        text,
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: 12 * 0.02,
          color: colors.foreground,
        ),
      ),
    );
  }
}
