import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Builds the app's light and dark [ThemeData], so incidental Material
/// widgets (CircularProgressIndicator, Form validation color, default text)
/// stay visually consistent with the custom widgets in lib/widgets/ even
/// though most screens read [AppColorTokens]/[AppTypography] directly via
/// `context.colors` rather than relying on Material theming.
abstract class AppTheme {
  static ThemeData get light => _build(AppColorTokens.light, Brightness.light);
  static ThemeData get dark => _build(AppColorTokens.dark, Brightness.dark);

  static ThemeData _build(AppColorTokens colors, Brightness brightness) {
    TextStyle withColor(TextStyle style, Color color) =>
        style.copyWith(color: color);

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: colors.surfacePage,
      colorScheme: ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: colors.accentPrimary,
        primary: colors.accentPrimary,
        secondary: colors.accentSecondary,
        error: colors.colorError,
        surface: colors.surfaceCard,
      ),
      extensions: [colors],
      textTheme: TextTheme(
        displayLarge: withColor(AppTypography.display1, colors.textPrimary),
        displayMedium: withColor(AppTypography.display2, colors.textPrimary),
        headlineSmall: withColor(AppTypography.headline, colors.textPrimary),
        bodyLarge: withColor(AppTypography.bodyLg, colors.textBody),
        bodyMedium: withColor(AppTypography.body, colors.textBody),
        labelLarge: withColor(AppTypography.ui, colors.textPrimary),
        labelSmall: withColor(AppTypography.label, colors.textSecondary),
        bodySmall: withColor(AppTypography.caption, colors.textSecondary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accentPrimary,
      ),
      dividerColor: colors.ink200,
      hoverColor: colors.surfaceSunken,
      highlightColor: colors.surfaceSunken,
      splashColor: colors.accentPrimaryTint,
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.ink950,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        ),
        textStyle: withColor(AppTypography.caption, colors.textOnAccent),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space2,
          vertical: AppSpacing.space1,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink950,
        contentTextStyle: withColor(AppTypography.ui, colors.textOnAccent),
        actionTextColor: colors.saffron500,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surfacePage,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        titleTextStyle: withColor(AppTypography.headline, colors.textPrimary),
      ),
    );
  }
}
