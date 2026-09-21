import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_back_bar.dart';
import 'app_button.dart';
import 'content_column.dart';

String? validateEmail(String? value) =>
    value == null || !value.contains('@') ? 'Enter a valid email' : null;

String? validatePassword(String? value) => value == null || value.length < 6
    ? 'Password must be at least 6 characters'
    : null;

/// Page for the sign-in and password forms: the [title], the [fields] with
/// the [error] under them, one wide submit button that shows a spinner while
/// [submitting], and any [footer] actions beneath it.
class AuthFormPage extends StatelessWidget {
  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> fields;
  final String submitLabel;
  final VoidCallback onSubmit;
  final bool submitting;
  final String? error;
  final List<Widget> footer;

  /// False when the page is the only one on screen, so there is nowhere to go back to.
  final bool showBack;

  const AuthFormPage({
    super.key,
    required this.title,
    required this.formKey,
    required this.fields,
    required this.submitLabel,
    required this.onSubmit,
    this.submitting = false,
    this.error,
    this.footer = const [],
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showBack ? const AppBackBar() : null,
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.space8),
        child: ContentColumn(
          maxWidth: AppSpacing.formWidth,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title.toUpperCase(), style: AppTypography.display2),
                const SizedBox(height: AppSpacing.space5),
                Column(
                  spacing: AppSpacing.space4,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: fields,
                ),
                const SizedBox(height: AppSpacing.space5),
                if (error != null) ...[
                  Text(error!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.colorError)),
                  const SizedBox(height: AppSpacing.space4),
                ],
                AppButton(
                  label: submitLabel,
                  wide: true,
                  onPressed: submitting ? null : onSubmit,
                  loadingChild: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.textOnAccent),
                        )
                      : null,
                ),
                if (footer.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.space2),
                  for (final action in footer) Center(child: action),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
