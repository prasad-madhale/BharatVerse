import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'app_icon_button.dart';
import 'content_column.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _formatLongDate(DateTime date) {
  final weekday = _weekdayNames[date.weekday - 1];
  final month = _monthNames[date.month - 1];
  return '$weekday, $month ${date.day}, ${date.year}';
}

/// Newspaper-masthead app header -- centered "BHARATVERSE" wordmark with
/// date, an account/sign-in icon, heavy/medium rules, and a tricolor accent
/// stripe. Mirrors the design system's AppHeader component. The search icon
/// shows when [onSearchClick] is given, and the liked-articles icon when
/// [onLikedClick] is given and the user is signed in.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool authenticated;
  final VoidCallback onAuthClick;
  final VoidCallback? onSearchClick;
  final VoidCallback? onLikedClick;
  final DateTime? date;

  const AppHeader(
      {super.key,
      required this.authenticated,
      required this.onAuthClick,
      this.onSearchClick,
      this.onLikedClick,
      this.date});

  @override
  Widget build(BuildContext context) {
    // Both sides are as wide as the left icons (48px tap targets), so the
    // wordmark stays centered.
    final showLiked = authenticated && onLikedClick != null;
    final sideWidth = showLiked ? 96.0 : 48.0;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContentColumn(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 12, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: sideWidth,
                    child: Row(
                      children: [
                        if (onSearchClick != null)
                          AppIconButton(
                            icon: Icons.search,
                            label: 'Search',
                            onPressed: onSearchClick,
                          ),
                        if (showLiked)
                          AppIconButton(
                            icon: Icons.favorite_border,
                            label: 'Liked articles',
                            onPressed: onLikedClick,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'BHARATVERSE',
                          style: AppTypography.headline
                              .copyWith(fontSize: 20, letterSpacing: 20 * 0.1),
                        ),
                        const SizedBox(height: 2),
                        Text(_formatLongDate(date ?? DateTime.now()),
                            style: AppTypography.caption),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: sideWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AppIconButton(
                        icon:
                            authenticated ? Icons.account_circle : Icons.login,
                        label: authenticated ? 'Sign out' : 'Sign in',
                        onPressed: onAuthClick,
                      ),
                    ),
                  ),
                ],
              ),
            )),
            // Indian tricolor accent stripe.
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: 32,
                height: 4,
                child: Column(
                  children: const [
                    Expanded(child: ColoredBox(color: Color(0xFFFF9933))),
                    Expanded(child: ColoredBox(color: Colors.white)),
                    Expanded(child: ColoredBox(color: Color(0xFF138808))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(88);
}
