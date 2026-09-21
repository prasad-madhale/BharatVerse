import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/auth_form_page.dart';

/// Asks for a new password after the reader follows a reset link, which has
/// already signed them in. They can also skip it and carry on signed in.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    // Saving ends the recovery, which replaces this screen, so keep what is
    // needed to say so afterwards.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthState>().updatePassword(_passwordController.text);
      messenger.showSnackBar(const SnackBar(content: Text('Password updated')));
    } catch (e) {
      if (mounted) setState(() => _errorMessage = describeAuthError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormPage(
      title: 'Choose a New Password',
      formKey: _formKey,
      showBack: false,
      fields: [
        AppInput(
          fieldKey: const Key('password-field'),
          label: 'New password',
          controller: _passwordController,
          obscureText: true,
          placeholder: '••••••••',
          validator: validatePassword,
        ),
        AppInput(
          fieldKey: const Key('confirm-field'),
          label: 'Confirm password',
          controller: _confirmController,
          obscureText: true,
          placeholder: '••••••••',
          validator: (value) => value == _passwordController.text
              ? null
              : 'Passwords do not match',
        ),
      ],
      error: _errorMessage,
      submitLabel: 'Update Password',
      submitting: _isSubmitting,
      onSubmit: _submit,
      footer: [
        AppButton(
          label: 'Skip for now',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          onPressed:
              _isSubmitting ? null : context.read<AuthState>().finishRecovery,
        ),
      ],
    );
  }
}
