import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../state/like_state.dart';
import 'app_icon_button.dart';

/// Heart toggle for an article -- filled in the like accent when the signed-in
/// user has liked it. Only a signed-in user has likes, so a signed-out tap
/// calls [onRequireAuth] instead. Needs an [AuthState] and a [LikeState] above
/// it in the widget tree.
class LikeButton extends StatelessWidget {
  final String articleId;
  final VoidCallback onRequireAuth;

  const LikeButton({
    super.key,
    required this.articleId,
    required this.onRequireAuth,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final likeState = context.watch<LikeState>();
    final liked = likeState.isLiked(articleId);

    return AppIconButton(
      icon: liked ? Icons.favorite : Icons.favorite_border,
      label: liked ? 'Unlike' : 'Like',
      active: liked,
      onPressed: () => authState.isAuthenticated
          ? _toggle(context, likeState)
          : onRequireAuth(),
    );
  }

  Future<void> _toggle(BuildContext context, LikeState likeState) async {
    // Grabbed before the await: the context may be gone by the time it ends.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await likeState.toggle(articleId);
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update your like: $e')),
      );
    }
  }
}
