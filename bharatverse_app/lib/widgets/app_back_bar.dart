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

  /// False for a page with nothing beneath it, so there is nowhere to go back
  /// to. The bar keeps its rules.
  final bool showBack;

  const AppBackBar({
    super.key,
    this.title,
    this.trailing,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfacePage,
        border: Border(
          top: BorderSide(color: colors.ink950, width: 2),
          bottom: BorderSide(color: colors.ink200),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ContentColumn(
          child: Row(
            children: [
              if (showBack)
                AppIconButton(
                  icon: Icons.arrow_back,
                  label: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                )
              else
                const SizedBox(width: 48),
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
                          color: colors.textPrimary,
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
