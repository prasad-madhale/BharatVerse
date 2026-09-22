import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Centers [child] in a readable column no wider than [maxWidth], so text keeps
/// a comfortable line length on desktop and tablet. Narrower screens are
/// unaffected.
class ContentColumn extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentColumn({
    super.key,
    required this.child,
    this.maxWidth = AppSpacing.contentWidth,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Horizontal padding that keeps a full-width scrolling list's content in the
/// column. The list itself still spans the screen, so the mouse wheel scrolls
/// anywhere on the page.
EdgeInsets columnPadding(
  BuildContext context, {
  double horizontal = AppSpacing.space4,
  double vertical = 0,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final gutter = math.max(0.0, (width - AppSpacing.contentWidth) / 2);
  return EdgeInsets.symmetric(
    horizontal: gutter + horizontal,
    vertical: vertical,
  );
}
