import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'content_column.dart';

/// Big serif heading at the top of a pushed screen, aligned with the list
/// beneath it.
class ScreenHeading extends StatelessWidget {
  final String text;

  const ScreenHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return ContentColumn(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text.toUpperCase(),
            style: AppTypography.display2
                .copyWith(color: context.colors.textPrimary),
          ),
        ),
      ),
    );
  }
}
