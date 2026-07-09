import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../state/auth_state.dart';

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
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isSignUpMode ? 'Sign Up' : 'Sign In')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) => (value == null || !value.contains('@'))
                    ? 'Enter a valid email'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (value) => (value == null || value.length < 6)
                    ? 'Password must be at least 6 characters'
                    : null,
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Text(_errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 16),
              ],
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isSignUpMode ? 'Sign Up' : 'Sign In'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() {
                          _isSignUpMode = !_isSignUpMode;
                          _errorMessage = null;
                        }),
                child: Text(_isSignUpMode
                    ? 'Already have an account? Sign In'
                    : "Don't have an account? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
