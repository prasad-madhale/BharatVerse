import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/reset_password_screen.dart';
import '../state/auth_state.dart';

const _linkParameters = {'code', 'error', 'error_code', 'error_description'};

/// True when [uri] still carries an emailed link's parameters. The SDK removes
/// them once it has signed the reader in with the link, so any left mean it
/// could not use it.
bool isUnusedAuthLink(Uri uri) {
  try {
    return uri.queryParameters.keys.any(_linkParameters.contains);
  } catch (_) {
    return false; // an address that will not parse is not a link
  }
}

/// Shows [child], the app, unless the reader has just followed a
/// password-reset link, when it shows the form for choosing a new password.
/// If the page was opened by a link that could not be used, it says so.
class RecoveryGate extends StatefulWidget {
  final Widget child;

  /// The address the page was opened with; the browser's own by default.
  final Uri? openedWith;

  const RecoveryGate({super.key, required this.child, this.openedWith});

  @override
  State<RecoveryGate> createState() => _RecoveryGateState();
}

class _RecoveryGateState extends State<RecoveryGate> {
  @override
  void initState() {
    super.initState();
    if (isUnusedAuthLink(widget.openedWith ?? Uri.base)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 10),
          content: Text('That reset link could not be used: it may have '
              'expired, been used already, or been opened on a different '
              'device. Request a new one from Sign In.'),
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovering =
        context.select<AuthState, bool>((auth) => auth.isRecovering);
    return recovering ? const ResetPasswordScreen() : widget.child;
  }
}
