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

  /// Key for the inner TextFormField specifically (not this widget) --
  /// the label is a sibling Text, not a descendant of the field, so tests
  /// can't target it by label text the way a bare TextFormField could.
  final Key? fieldKey;

  const AppInput({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.placeholder,
    this.validator,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: 6),
        TextFormField(
          key: fieldKey,
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: AppTypography.ui,
          decoration: InputDecoration(
            hintText: placeholder,
            filled: true,
            fillColor: AppColors.surfaceCard,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space3,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              borderSide: const BorderSide(color: AppColors.ink200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              borderSide: const BorderSide(color: AppColors.ink200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              borderSide: const BorderSide(color: AppColors.ink800),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              borderSide: const BorderSide(color: AppColors.colorError),
            ),
            errorStyle:
                AppTypography.caption.copyWith(color: AppColors.colorError),
          ),
        ),
      ],
    );
  }
}
