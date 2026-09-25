import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/content_column.dart';
import 'forgot_password_screen.dart';

/// Single screen toggling between sign-in and sign-up, plus Apple OAuth and
/// a guest path. Pops itself on success -- unless [onContinue] is given (the
/// first-run flow from [OnboardingScreen], which has no app screen beneath
/// it to pop back to), in which case that replaces the pop and the guest
/// "Not now" button is offered too.
class AuthScreen extends StatefulWidget {
  final bool initialSignUp;
  final VoidCallback? onContinue;

  const AuthScreen({super.key, this.initialSignUp = false, this.onContinue});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late bool _isSignUpMode = widget.initialSignUp;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _done() {
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.of(context).pop();
    }
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
      if (mounted) _done();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = describeAuthError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _continueWithApple() async {
    setState(() => _errorMessage = null);
    try {
      await context.read<AuthState>().signInWithApple();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = describeAuthError(e));
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
    final colors = context.colors;
    final title = _isSignUpMode ? 'Create your account' : 'Welcome back';
    final subtitle = _isSignUpMode
        ? 'Save stories, keep your streak, and read across devices.'
        : 'Pick up where you left off — your saved stories are waiting.';
    final cta = _isSignUpMode ? 'Create account' : 'Sign in';
    final toggleLabel = _isSignUpMode
        ? 'Already have an account? Sign in'
        : 'New here? Create an account';

    return Scaffold(
      backgroundColor: colors.surfacePage,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.chevron_left, color: colors.tint, size: 26),
                  label: Text('Back',
                      style: AppTypography.ui
                          .copyWith(fontSize: 17, color: colors.tint)),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: ContentColumn(
                  maxWidth: AppSpacing.formWidth,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: AppTypography.display1.copyWith(
                            fontSize: 34,
                            height: 1.1,
                            letterSpacing: -0.5,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: AppTypography.ui
                              .copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 14),
                        _AppleButton(onPressed: _continueWithApple),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(child: Divider(color: colors.sep)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('or use email',
                                  style: AppTypography.caption
                                      .copyWith(color: colors.textSecondary)),
                            ),
                            Expanded(child: Divider(color: colors.sep)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _AuthFieldCell(
                          emailController: _emailController,
                          passwordController: _passwordController,
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: AppSpacing.space3),
                          Text(_errorMessage!,
                              style: AppTypography.caption
                                  .copyWith(color: colors.colorError)),
                        ],
                        const SizedBox(height: AppSpacing.space4),
                        AppButton(
                          label: cta,
                          variant: AppButtonVariant.cta,
                          pill: true,
                          wide: true,
                          onPressed: _isSubmitting ? null : _submit,
                          loadingChild: _isSubmitting
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: colors.ctaFg),
                                )
                              : null,
                        ),
                        if (!_isSignUpMode) ...[
                          const SizedBox(height: AppSpacing.space1),
                          Center(
                            child: TextButton(
                              onPressed: _isSubmitting ? null : _forgotPassword,
                              child: Text('Forgot password?',
                                  style: AppTypography.ui.copyWith(
                                      fontSize: 15, color: colors.tint)),
                            ),
                          ),
                        ],
                        Center(
                          child: TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => setState(() {
                                      _isSignUpMode = !_isSignUpMode;
                                      _errorMessage = null;
                                    }),
                            child: Text(toggleLabel,
                                style: AppTypography.ui.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colors.tint)),
                          ),
                        ),
                        if (widget.onContinue != null)
                          Center(
                            child: TextButton(
                              onPressed: _isSubmitting ? null : _done,
                              child: Text('Not now — just browse',
                                  style: AppTypography.ui.copyWith(
                                      fontSize: 15,
                                      color: colors.textSecondary)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The grouped email+password cell -- one rounded card with a hairline
/// divider between the two fields, matching the mockup's `--bv-cell`
/// list-style input group (distinct from [AppInput]'s standalone,
/// labeled-field style used elsewhere).
class _AuthFieldCell extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;

  const _AuthFieldCell({
    required this.emailController,
    required this.passwordController,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.ui.copyWith(
      fontSize: 17,
      color: colors.textPrimary,
    );
    InputDecoration decoration(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: style.copyWith(color: colors.textPlaceholder),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          isDense: true,
        );

    return Container(
      decoration: BoxDecoration(
        color: colors.cell,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.sep, width: 0.5),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 50,
            child: TextFormField(
              key: const Key('email-field'),
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: style,
              decoration: decoration('Email'),
              validator: (value) => value == null || !value.contains('@')
                  ? 'Enter a valid email'
                  : null,
            ),
          ),
          Divider(height: 0.5, thickness: 0.5, color: colors.sep),
          SizedBox(
            height: 50,
            child: TextFormField(
              key: const Key('password-field'),
              controller: passwordController,
              obscureText: true,
              style: style,
              decoration: decoration('Password'),
              validator: (value) => value == null || value.length < 6
                  ? 'Password must be at least 6 characters'
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppleButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AppleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.apple, color: colors.appleFg, size: 20),
        label: Text('Continue with Apple',
            style: AppTypography.ui.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.appleFg)),
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.appleBg,
          foregroundColor: colors.appleFg,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull)),
        ),
      ),
    );
  }
}
