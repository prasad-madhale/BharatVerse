import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A `backdrop-filter: blur(...)` pill, matching the mockup's `--bv-glass`
/// floating chrome (tab bar, search button, onboarding's Skip button,
/// continue-reading bar, article back/share buttons).
class GlassSurface extends StatelessWidget {
  final double height;
  final double? width;
  final Widget child;

  const GlassSurface({
    super.key,
    required this.height,
    this.width,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: colors.glass,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            border: Border.all(color: colors.glassEdge, width: 0.5),
            boxShadow: colors.shadowFloat,
          ),
          child: child,
        ),
      ),
    );
  }
}
