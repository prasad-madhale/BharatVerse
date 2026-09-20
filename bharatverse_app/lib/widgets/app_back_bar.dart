import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_icon_button.dart';

/// Slim top bar with a back button, for screens pushed over the home screen.
class AppBackBar extends StatelessWidget implements PreferredSizeWidget {
  const AppBackBar({super.key});

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
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppIconButton(
            icon: Icons.arrow_back,
            label: 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
