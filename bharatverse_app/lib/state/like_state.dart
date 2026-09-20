import 'package:flutter/foundation.dart';

import '../services/likes_client.dart';
import 'auth_state.dart';

/// Which articles the signed-in user has liked, kept in memory and synced to
/// Supabase through [LikesClient]. Follows [AuthState]: it loads the user's
/// likes on sign-in and forgets them on sign-out, so one user's likes never
/// show for the next.
class LikeState extends ChangeNotifier {
  final LikesClient _likesClient;
  final AuthState _authState;

  final Set<String> _likedIds = {};
  final Set<String> _pending = {};
  String? _loadedForUserId;

  LikeState({required LikesClient likesClient, required AuthState authState})
      : _likesClient = likesClient,
        _authState = authState {
    _authState.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  bool isLiked(String articleId) => _likedIds.contains(articleId);

  /// Likes the article if it is not liked, and unlikes it if it is. The change
  /// shows immediately and is rolled back if the request fails, in which case
  /// the error is rethrown. A tap on an article whose previous change is still
  /// in flight is ignored. Throws a [StateError] when nobody is signed in.
  Future<void> toggle(String articleId) async {
    final userId = _authState.currentUser?.id;
    final accessToken = _authState.accessToken;
    if (userId == null || accessToken == null) {
      throw StateError('Sign in to like articles');
    }
    if (!_pending.add(articleId)) {
      return;
    }

    final wasLiked = isLiked(articleId);
    _setLiked(userId, articleId, !wasLiked);
    try {
      if (wasLiked) {
        await _likesClient.unlike(
          accessToken: accessToken,
          articleId: articleId,
        );
      } else {
        await _likesClient.like(
          accessToken: accessToken,
          userId: userId,
          articleId: articleId,
        );
      }
    } catch (_) {
      _setLiked(userId, articleId, wasLiked);
      rethrow;
    } finally {
      _pending.remove(articleId);
    }
  }

  void _setLiked(String userId, String articleId, bool liked) {
    // The account may have changed while a request was in flight.
    if (_loadedForUserId != userId) {
      return;
    }
    if (liked) {
      _likedIds.add(articleId);
    } else {
      _likedIds.remove(articleId);
    }
    notifyListeners();
  }

  void _onAuthChanged() {
    final userId = _authState.currentUser?.id;
    // Token refreshes also notify; only a different user changes anything.
    if (userId == _loadedForUserId) {
      return;
    }
    _loadedForUserId = userId;
    _likedIds.clear();
    _pending.clear();
    notifyListeners();
    if (userId != null) {
      _load(userId);
    }
  }

  Future<void> _load(String userId) async {
    final accessToken = _authState.accessToken;
    if (accessToken == null) {
      return;
    }
    try {
      final ids = await _likesClient.getLikedArticleIds(
        accessToken: accessToken,
      );
      // Signed out, or a different account, by the time this returned.
      if (_loadedForUserId != userId) {
        return;
      }
      _likedIds.addAll(ids);
      notifyListeners();
    } catch (e) {
      // A failed load must not block reading. The likes stay empty until the
      // next sign-in.
      debugPrint('Could not load likes: $e');
    }
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthChanged);
    super.dispose();
  }
}
