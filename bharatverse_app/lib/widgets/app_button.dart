import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant { primary, secondary, ghost }

enum AppButtonSize { sm, md, lg }

/// Primary UI action button -- saffron-filled primary CTA, newspaper-
/// editorial style. Mirrors the design system's Button component.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool wide;
  final Widget? loadingChild;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.wide = false,
    this.loadingChild,
  });

  EdgeInsets get _padding {
    switch (size) {
      case AppButtonSize.sm:
        return const EdgeInsets.symmetric(horizontal: 14, vertical: 8);
      case AppButtonSize.md:
        return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
      case AppButtonSize.lg:
        return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;

    Color background;
    Color foreground;
    BorderSide border = BorderSide.none;

    switch (variant) {
      case AppButtonVariant.primary:
        background = disabled ? AppColors.paper200 : AppColors.accentPrimary;
        foreground =
            disabled ? AppColors.textPlaceholder : AppColors.textOnAccent;
      case AppButtonVariant.secondary:
        background = Colors.transparent;
        foreground =
            disabled ? AppColors.textPlaceholder : AppColors.textPrimary;
        border = BorderSide(
            color: disabled ? AppColors.borderHairline : AppColors.ink200);
      case AppButtonVariant.ghost:
        background = Colors.transparent;
        foreground =
            disabled ? AppColors.textPlaceholder : AppColors.accentPrimary;
    }

    final child = loadingChild ??
        Text(
          label,
          style: AppTypography.ui.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: AppTypography.ui.fontSize! * 0.02,
            color: foreground,
          ),
        );

    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        disabledBackgroundColor: background,
        foregroundColor: foreground,
        disabledForegroundColor: foreground,
        elevation: 0,
        padding: _padding,
        side: border,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
      ),
      child: child,
    );

    return wide ? SizedBox(width: double.infinity, child: button) : button;
  }
}
