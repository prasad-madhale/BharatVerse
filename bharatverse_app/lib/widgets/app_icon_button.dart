import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Circular icon-only button -- header actions, back navigation. Mirrors
/// the design system's IconButton component.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 20,
      tooltip: label,
      onPressed: onPressed,
      color: active ? AppColors.accentPrimary : AppColors.textPrimary,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      splashRadius: size / 2,
    );
  }
}
