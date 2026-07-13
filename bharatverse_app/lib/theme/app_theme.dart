import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the app's ThemeData from the design system tokens, so incidental
/// Material widgets (CircularProgressIndicator, Form validation color,
/// default text) stay visually consistent with the custom widgets in
/// lib/widgets/ even though most screens don't rely on Material theming
/// directly.
abstract class AppTheme {
  static ThemeData get theme {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.surfacePage,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accentPrimary,
        primary: AppColors.accentPrimary,
        secondary: AppColors.accentSecondary,
        error: AppColors.colorError,
        surface: AppColors.surfaceCard,
      ),
      textTheme: TextTheme(
        displayLarge: AppTypography.display1,
        displayMedium: AppTypography.display2,
        headlineSmall: AppTypography.headline,
        bodyLarge: AppTypography.bodyLg,
        bodyMedium: AppTypography.body,
        labelLarge: AppTypography.ui,
        labelSmall: AppTypography.label,
        bodySmall: AppTypography.caption,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentPrimary,
      ),
      dividerColor: AppColors.ink200,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfacePage,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        titleTextStyle: AppTypography.headline,
      ),
    );
  }
}
