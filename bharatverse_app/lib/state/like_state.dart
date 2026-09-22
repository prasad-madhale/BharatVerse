import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_client.dart' show ApiException;
import '../services/likes_client.dart';
import '../services/pending_likes.dart';
import 'auth_state.dart';

/// The signed-in user's liked articles, in memory and synced through
/// [LikesClient]. Follows [AuthState]: loads on sign-in, clears on sign-out.
class LikeState extends ChangeNotifier {
  final LikesClient _likesClient;
  final AuthState _authState;
  final PendingLikes? _pendingLikes;

  final Set<String> _likedIds = {};
  final Set<String> _pending = {};
  String? _loadedForUserId;

  LikeState({
    required LikesClient likesClient,
    required AuthState authState,
    PendingLikes? pendingLikes,
  })  : _likesClient = likesClient,
        _authState = authState,
        _pendingLikes = pendingLikes {
    _authState.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  bool isLiked(String articleId) => _likedIds.contains(articleId);

  /// Flips the like at once. If the server cannot be reached at all, the change is kept and
  /// queued to send once it can be (see [_flushPending]); any other failure rolls back and
  /// rethrows. Ignored while a change to the same article is in flight; throws a [StateError]
  /// when nobody is signed in.
  Future<void> toggleLike(String articleId) async {
    final userId = _authState.currentUser?.id;
    final accessToken = _authState.authToken;
    if (userId == null || accessToken == null) {
      throw StateError('Sign in to like articles');
    }
    if (!_pending.add(articleId)) {
      return;
    }

    final wasLiked = isLiked(articleId);
    final wantLiked = !wasLiked;
    _setLiked(userId, articleId, wantLiked);
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
      await _pendingLikes?.clear(userId, articleId);
      unawaited(_flushPending(userId));
    } on ApiException catch (e) {
      final pendingLikes = _pendingLikes;
      if (e.statusCode == null &&
          pendingLikes != null &&
          _loadedForUserId == userId) {
        await pendingLikes.set(userId, articleId, wantLiked);
      } else {
        _setLiked(userId, articleId, wasLiked);
        rethrow;
      }
    } catch (_) {
      _setLiked(userId, articleId, wasLiked);
      rethrow;
    } finally {
      _pending.remove(articleId);
    }
  }

  /// Sends whatever [userId] has queued because the server could not be reached earlier. The
  /// optimistic state from when each change was made is already showing, so a retry that
  /// succeeds needs nothing more than dropping it from the queue; one the server refuses outright
  /// (called with the wrong user, say) is dropped too, since retrying it will never succeed.
  Future<void> _flushPending(String userId) async {
    final pendingLikes = _pendingLikes;
    final accessToken = _authState.authToken;
    if (pendingLikes == null || accessToken == null) {
      return;
    }
    for (final entry in pendingLikes.forUser(userId).entries) {
      final articleId = entry.key;
      if (_pending.contains(articleId)) {
        continue; // toggleLike itself owns this article right now
      }
      try {
        if (entry.value) {
          await _likesClient.like(
            accessToken: accessToken,
            userId: userId,
            articleId: articleId,
          );
        } else {
          await _likesClient.unlike(
            accessToken: accessToken,
            articleId: articleId,
          );
        }
        await pendingLikes.clear(userId, articleId);
      } on ApiException catch (e) {
        if (e.statusCode != null) {
          await pendingLikes.clear(userId, articleId);
        }
      }
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
    final accessToken = _authState.authToken;
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
      unawaited(_flushPending(userId));
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
