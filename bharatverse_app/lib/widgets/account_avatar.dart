import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth_screen.dart';
import '../state/auth_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'settings_sheet.dart';

/// The circular account button used on Today's and Library's mastheads: the
/// signed-in user's initial, or a person icon when signed out. Tapping it
/// opens the Settings sheet when signed in, or [AuthScreen] otherwise.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final authState = context.watch<AuthState>();
    final email = authState.currentUser?.email;
    final initial =
        (email != null && email.isNotEmpty) ? email[0].toUpperCase() : null;

    return Semantics(
      button: true,
      label: authState.isAuthenticated ? 'Account settings' : 'Sign in',
      child: InkWell(
        onTap: () => authState.isAuthenticated
            ? SettingsSheet.show(context)
            : Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AuthScreen())),
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: colors.ink950, shape: BoxShape.circle),
          child: initial != null
              ? Text(initial,
                  style: AppTypography.headline
                      .copyWith(fontSize: 17, color: colors.paper0))
              : Icon(Icons.person_outline, color: colors.paper0, size: 22),
        ),
      ),
    );
  }
}
