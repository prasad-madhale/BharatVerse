import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

/// Centered empty/error state -- "no articles yet", load failures. Mirrors
/// the design system's EmptyState component.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    this.icon = Icons.menu_book_outlined,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space6, vertical: AppSpacing.space12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: AppColors.ink300),
          const SizedBox(height: AppSpacing.space2),
          Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppTypography.headline,
          ),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: AppTypography.body,
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.space2),
            AppButton(
              label: actionLabel!,
              variant: AppButtonVariant.secondary,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
