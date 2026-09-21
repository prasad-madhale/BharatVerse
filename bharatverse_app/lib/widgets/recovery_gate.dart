import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/reset_password_screen.dart';
import '../state/auth_state.dart';

/// Shows [child], the app, unless the reader has just followed a
/// password-reset link, when it shows the form for choosing a new password.
class RecoveryGate extends StatelessWidget {
  final Widget child;

  const RecoveryGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final recovering =
        context.select<AuthState, bool>((auth) => auth.isRecovering);
    return recovering ? const ResetPasswordScreen() : child;
  }
}
