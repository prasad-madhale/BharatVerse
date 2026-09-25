import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/app_input.dart';
import '../widgets/auth_form_page.dart';

/// Asks for an email address and has Supabase send a link to it for choosing
/// a new password. It answers the same way whether or not an account exists,
/// so it cannot be used to find out who has one.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController =
      TextEditingController(text: widget.initialEmail);

  bool _isSubmitting = false;
  bool _sent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await context
          .read<AuthState>()
          .sendPasswordReset(_emailController.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = describeAuthError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (_sent) {
      return AuthFormPage(
        title: 'Check Your Email',
        formKey: _formKey,
        fields: [
          Text(
            'If an account exists for ${_emailController.text.trim()}, a link '
            'to choose a new password is on its way.',
            style: AppTypography.body.copyWith(color: colors.textBody),
          ),
        ],
        submitLabel: 'Back to Sign In',
        onSubmit: () => Navigator.of(context).pop(),
      );
    }
    return AuthFormPage(
      title: 'Reset Password',
      formKey: _formKey,
      fields: [
        Text(
          'Enter the email you signed up with and we will send you a link to '
          'choose a new password.',
          style: AppTypography.body.copyWith(color: colors.textBody),
        ),
        AppInput(
          fieldKey: const Key('email-field'),
          label: 'Email',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          placeholder: 'you@example.com',
          validator: validateEmail,
        ),
      ],
      error: _errorMessage,
      submitLabel: 'Send Reset Link',
      submitting: _isSubmitting,
      onSubmit: _submit,
    );
  }
}
