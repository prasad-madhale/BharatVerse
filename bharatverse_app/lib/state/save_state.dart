import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_client.dart' show ApiException;
import '../services/pending_saves.dart';
import '../services/saves_client.dart';
import 'auth_state.dart';

/// The signed-in user's saved (bookmarked) articles, in memory and synced
/// through [SavesClient]. Follows [AuthState]: loads on sign-in, clears on
/// sign-out.
class SaveState extends ChangeNotifier {
  final SavesClient _savesClient;
  final AuthState _authState;
  final PendingSaves? _pendingSaves;

  final Set<String> _savedIds = {};
  final Set<String> _pending = {};
  String? _loadedForUserId;

  SaveState({
    required SavesClient savesClient,
    required AuthState authState,
    PendingSaves? pendingSaves,
  })  : _savesClient = savesClient,
        _authState = authState,
        _pendingSaves = pendingSaves {
    _authState.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  bool isSaved(String articleId) => _savedIds.contains(articleId);

  /// Flips the save at once. If the server cannot be reached at all, the change is kept and
  /// queued to send once it can be (see [_flushPending]); any other failure rolls back and
  /// rethrows. Ignored while a change to the same article is in flight; throws a [StateError]
  /// when nobody is signed in.
  Future<void> toggleSave(String articleId) async {
    final userId = _authState.currentUser?.id;
    final accessToken = _authState.authToken;
    if (userId == null || accessToken == null) {
      throw StateError('Sign in to save articles');
    }
    if (!_pending.add(articleId)) {
      return;
    }

    final wasSaved = isSaved(articleId);
    final wantSaved = !wasSaved;
    _setSaved(userId, articleId, wantSaved);
    try {
      if (wasSaved) {
        await _savesClient.unsave(
          accessToken: accessToken,
          articleId: articleId,
        );
      } else {
        await _savesClient.save(
          accessToken: accessToken,
          userId: userId,
          articleId: articleId,
        );
      }
      await _pendingSaves?.clear(userId, articleId);
      unawaited(_flushPending(userId));
    } on ApiException catch (e) {
      final pendingSaves = _pendingSaves;
      if (e.statusCode == null &&
          pendingSaves != null &&
          _loadedForUserId == userId) {
        await pendingSaves.set(userId, articleId, wantSaved);
      } else {
        _setSaved(userId, articleId, wasSaved);
        rethrow;
      }
    } catch (_) {
      _setSaved(userId, articleId, wasSaved);
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
    final pendingSaves = _pendingSaves;
    final accessToken = _authState.authToken;
    if (pendingSaves == null || accessToken == null) {
      return;
    }
    for (final entry in pendingSaves.forUser(userId).entries) {
      final articleId = entry.key;
      if (_pending.contains(articleId)) {
        continue; // toggleSave itself owns this article right now
      }
      try {
        if (entry.value) {
          await _savesClient.save(
            accessToken: accessToken,
            userId: userId,
            articleId: articleId,
          );
        } else {
          await _savesClient.unsave(
            accessToken: accessToken,
            articleId: articleId,
          );
        }
        await pendingSaves.clear(userId, articleId);
      } on ApiException catch (e) {
        if (e.statusCode != null) {
          await pendingSaves.clear(userId, articleId);
        }
      }
    }
  }

  void _setSaved(String userId, String articleId, bool saved) {
    // The account may have changed while a request was in flight.
    if (_loadedForUserId != userId) {
      return;
    }
    if (saved) {
      _savedIds.add(articleId);
    } else {
      _savedIds.remove(articleId);
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
    _savedIds.clear();
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
      final ids = await _savesClient.getSavedArticleIds(
        accessToken: accessToken,
      );
      // The account changed while this was loading.
      if (_loadedForUserId != userId) {
        return;
      }
      _savedIds.addAll(ids);
      notifyListeners();
      unawaited(_flushPending(userId));
    } catch (e) {
      // A failed load must not block reading.
      debugPrint('Could not load saves: $e');
    }
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthChanged);
    super.dispose();
  }
}
