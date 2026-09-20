import 'package:flutter/foundation.dart';

import '../services/likes_client.dart';
import 'auth_state.dart';

/// The signed-in user's liked articles, in memory and synced through
/// [LikesClient]. Follows [AuthState]: loads on sign-in, clears on sign-out.
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

  /// Flips the like at once and rolls back, rethrowing, if the request fails.
  /// Ignored while a change to the same article is in flight; throws a
  /// [StateError] when nobody is signed in.
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
      // The account changed while this was loading.
      if (_loadedForUserId != userId) {
        return;
      }
      _likedIds.addAll(ids);
      notifyListeners();
    } catch (e) {
      // A failed load must not block reading.
      debugPrint('Could not load likes: $e');
    }
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthChanged);
    super.dispose();
  }
}
