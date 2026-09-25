import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../state/save_state.dart';
import 'app_icon_button.dart';

/// Bookmark toggle for an article. A signed-out tap calls [onRequireAuth].
/// Needs an [AuthState] and a [SaveState] above it in the widget tree.
class SaveButton extends StatelessWidget {
  final String articleId;
  final VoidCallback onRequireAuth;

  const SaveButton({
    super.key,
    required this.articleId,
    required this.onRequireAuth,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final saveState = context.watch<SaveState>();
    final saved = saveState.isSaved(articleId);

    return AppIconButton(
      icon: saved ? Icons.bookmark : Icons.bookmark_border,
      label: saved ? 'Remove from saved' : 'Save',
      active: saved,
      onPressed: () => authState.isAuthenticated
          ? _toggle(context, saveState)
          : onRequireAuth(),
    );
  }

  Future<void> _toggle(BuildContext context, SaveState saveState) async {
    // Read before the await; the context may be gone after it.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await saveState.toggleSave(articleId);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_failureMessage(e))));
    }
  }

  String _failureMessage(ApiException e) => e.statusCode == null
      ? e.message
      : 'Could not update your save (${e.statusCode}). Please try again.';
}
