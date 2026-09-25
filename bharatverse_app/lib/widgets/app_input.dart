import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Labeled text field -- auth forms. Mirrors the design system's Input
/// component (uppercase label, hairline border, focus ring).
class AppInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? placeholder;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;

  /// Key for the inner TextFormField specifically (not this widget) --
  /// the label is a sibling Text, not a descendant of the field, so tests
  /// can't target it by label text the way a bare TextFormField could.
  final Key? fieldKey;

  /// Full-stadium corners, for the reimagine's rounded fields (onboarding,
  /// auth) instead of the broadsheet's crisp [AppSpacing.radiusXs].
  final bool pill;

  const AppInput({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.placeholder,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
    this.fieldKey,
    this.pill = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(
        pill ? AppSpacing.radiusFull : AppSpacing.radiusXs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: fieldKey,
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          textInputAction: textInputAction,
          autofocus: autofocus,
          style: AppTypography.ui.copyWith(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: placeholder,
            filled: true,
            fillColor: colors.surfaceCard,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space3,
            ),
            border: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: colors.ink200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: colors.ink200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: colors.ink800),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: colors.colorError),
            ),
            errorStyle:
                AppTypography.caption.copyWith(color: colors.colorError),
          ),
        ),
      ],
    );
  }
}
