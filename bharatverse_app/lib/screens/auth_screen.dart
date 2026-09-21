import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/auth_form_page.dart';
import 'forgot_password_screen.dart';

/// Single screen toggling between sign-in and sign-up, email/password only
/// (OAuth is a fast-follow -- see roadmap.md Phase 1). Pops itself on
/// success; the caller (HomeScreen's account icon) is responsible for
/// pushing this screen.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUpMode = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final authState = context.read<AuthState>();
    try {
      if (_isSignUpMode) {
        await authState.register(
            _emailController.text, _passwordController.text);
      } else {
        await authState.login(_emailController.text, _passwordController.text);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = describeAuthError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _forgotPassword() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mode = _isSignUpMode ? 'Sign Up' : 'Sign In';
    return AuthFormPage(
      title: mode,
      formKey: _formKey,
      fields: [
        AppInput(
          fieldKey: const Key('email-field'),
          label: 'Email',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          placeholder: 'you@example.com',
          validator: validateEmail,
        ),
        AppInput(
          fieldKey: const Key('password-field'),
          label: 'Password',
          controller: _passwordController,
          obscureText: true,
          placeholder: '••••••••',
          validator: validatePassword,
        ),
      ],
      error: _errorMessage,
      submitLabel: mode,
      submitting: _isSubmitting,
      onSubmit: _submit,
      footer: [
        if (!_isSignUpMode)
          AppButton(
            label: 'Forgot password?',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: _isSubmitting ? null : _forgotPassword,
          ),
        AppButton(
          label: _isSignUpMode
              ? 'Already have an account? Sign In'
              : "Don't have an account? Sign Up",
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          onPressed: _isSubmitting
              ? null
              : () => setState(() {
                    _isSignUpMode = !_isSignUpMode;
                    _errorMessage = null;
                  }),
        ),
      ],
    );
  }
}
