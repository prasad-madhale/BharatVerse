import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

enum AppBadgeTone { saffron, green, neutral }

/// Small uppercase eyebrow label -- "TODAY'S ARTICLE", "SOURCES".
/// Mirrors the design system's Badge component.
class AppBadge extends StatelessWidget {
  final String text;
  final AppBadgeTone tone;

  const AppBadge(this.text, {super.key, this.tone = AppBadgeTone.saffron});

  Color _color(BuildContext context) {
    final colors = context.colors;
    switch (tone) {
      case AppBadgeTone.saffron:
        return colors.saffron600;
      case AppBadgeTone.green:
        return colors.green600;
      case AppBadgeTone.neutral:
        return colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.label.copyWith(color: _color(context)),
    );
  }
}
