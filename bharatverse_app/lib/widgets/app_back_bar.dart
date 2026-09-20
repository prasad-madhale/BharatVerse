import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'app_icon_button.dart';
import 'content_column.dart';

/// Slim top bar for screens pushed over the home screen: a back button, and
/// optionally a centered [title] and a [trailing] action. Its rules span the
/// screen while the content stays in the reading column.
class AppBackBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? trailing;

  const AppBackBar({super.key, this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfacePage,
        border: Border(
          top: BorderSide(color: AppColors.ink950, width: 2),
          bottom: BorderSide(color: AppColors.ink200),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ContentColumn(
          child: Row(
            children: [
              AppIconButton(
                icon: Icons.arrow_back,
                label: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: title == null
                    ? const SizedBox.shrink()
                    : Text(
                        title!,
                        textAlign: TextAlign.center,
                        style: AppTypography.ui.copyWith(
                          fontFamily: AppTypography.headline.fontFamily,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 15 * 0.08,
                        ),
                      ),
              ),
              trailing ?? const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
