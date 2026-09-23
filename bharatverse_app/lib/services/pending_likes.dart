import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Like and unlike requests that could not reach the server, kept until [LikeState] can retry
/// them, per signed-in user so a different account on the same device never sees or resends
/// someone else's.
class PendingLikes {
  static const _key = 'pending_likes_v1';

  final SharedPreferences _prefs;

  PendingLikes(this._prefs);

  static Future<PendingLikes> open() async =>
      PendingLikes(await SharedPreferences.getInstance());

  /// The articleId -> wanted-liked-state queue for [userId].
  Map<String, bool> forUser(String userId) =>
      Map.of(_read()[userId] ?? const {});

  Future<void> set(String userId, String articleId, bool liked) async {
    final all = _read();
    all.putIfAbsent(userId, () => {})[articleId] = liked;
    await _write(all);
  }

  Future<void> clear(String userId, String articleId) async {
    final all = _read();
    final forUser = all[userId];
    if (forUser == null || forUser.remove(articleId) == null) {
      return;
    }
    if (forUser.isEmpty) {
      all.remove(userId);
    }
    await _write(all);
  }

  Future<void> _write(Map<String, Map<String, bool>> all) =>
      _prefs.setString(_key, jsonEncode(all));

  /// An unreadable store is an empty one.
  Map<String, Map<String, bool>> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null) {
      return {};
    }
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (userId, byArticle) => MapEntry(
          userId,
          (byArticle as Map<String, dynamic>)
              .map((articleId, liked) => MapEntry(articleId, liked as bool)),
        ),
      );
    } catch (_) {
      return {};
    }
  }
}
