import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The article ids a reader has opened, most recently opened first, for the
/// Library screen's "Recently read" section and AppShell's continue-reading
/// bar. Device-local and not scoped to a signed-in user, like [ArticleCache]:
/// it is reading history, not an account record. A [ChangeNotifier] (unlike
/// most of this app's local services) so the continue-reading bar updates as
/// soon as a new article is opened, without AppShell needing its own signal
/// for every screen that can open one.
class ReadingHistory extends ChangeNotifier {
  static const _key = 'reading_history_v1';
  static const _maxEntries = 20;

  final SharedPreferences _prefs;

  ReadingHistory(this._prefs);

  static Future<ReadingHistory> open() async =>
      ReadingHistory(await SharedPreferences.getInstance());

  /// Article ids, most recently opened first.
  List<String> get articleIds => _prefs.getStringList(_key) ?? [];

  /// Moves [articleId] to the front, adding it if new, and drops the oldest
  /// entries past [_maxEntries].
  Future<void> recordOpened(String articleId) async {
    final ids = articleIds;
    ids.remove(articleId);
    ids.insert(0, articleId);
    await _prefs.setStringList(
      _key,
      ids.length > _maxEntries ? ids.sublist(0, _maxEntries) : ids,
    );
    notifyListeners();
  }
}
