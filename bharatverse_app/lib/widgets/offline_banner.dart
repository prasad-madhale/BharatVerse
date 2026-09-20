import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'content_column.dart';

/// A slim notice, shown while [offline] is true, that the articles on screen
/// were saved on this device.
class OfflineBanner extends StatelessWidget {
  final ValueListenable<bool> offline;

  const OfflineBanner({super.key, required this.offline});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: offline,
      builder: (context, isOffline, _) {
        if (!isOffline) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
          decoration: const BoxDecoration(
            color: AppColors.surfaceSunken,
            border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
          ),
          child: ContentColumn(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
              child: Text('OFFLINE · SHOWING SAVED ARTICLES',
                  style: AppTypography.label),
            ),
          ),
        );
      },
    );
  }
}
