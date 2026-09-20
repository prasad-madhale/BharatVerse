import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/article.dart';

/// Articles saved on the device so they can be read offline. It keeps the
/// [capacity] most recently viewed ones; when it is full, the one viewed
/// longest ago goes first, so a week of daily articles always fits.
class ArticleCache {
  static const _key = 'article_cache_v1';

  final SharedPreferences _prefs;
  final int capacity;
  final DateTime Function() _now;

  ArticleCache(this._prefs, {this.capacity = 50, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static Future<ArticleCache> open() async =>
      ArticleCache(await SharedPreferences.getInstance());

  Future<void> cacheArticle(Article article) => cacheArticles([article]);

  /// Saves [articles] as just viewed, replacing any older copy, then drops the
  /// least recently viewed beyond [capacity].
  Future<void> cacheArticles(Iterable<Article> articles) async {
    final entries = _read();
    final viewedAt = _now().millisecondsSinceEpoch;
    for (final article in articles) {
      entries[article.id] = {'viewedAt': viewedAt, 'article': article.toJson()};
    }
    if (entries.length > capacity) {
      // Articles cached together share a time, so the older publication goes
      // first among them.
      final oldestFirst = entries.entries.toList()
        ..sort((a, b) {
          final byView = (a.value['viewedAt'] as int)
              .compareTo(b.value['viewedAt'] as int);
          if (byView != 0) {
            return byView;
          }
          final byDate = _date(a.value).compareTo(_date(b.value));
          return byDate != 0 ? byDate : a.key.compareTo(b.key);
        });
      for (final entry in oldestFirst.take(entries.length - capacity)) {
        entries.remove(entry.key);
      }
    }
    await _prefs.setString(_key, jsonEncode(entries));
  }

  Future<Article?> getCachedArticle(String id) async {
    final entry = _read()[id];
    return entry == null ? null : _article(entry);
  }

  /// Every saved article, newest first.
  Future<List<Article>> getCachedArticles() async {
    final articles = _read().values.map(_article).whereType<Article>().toList()
      ..sort((a, b) {
        final byDate = b.publicationDate.compareTo(a.publicationDate);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
    return articles;
  }

  String _date(Map<String, dynamic> entry) =>
      (entry['article'] as Map<String, dynamic>)['publication_date'] as String;

  /// An entry that no longer parses is treated as missing.
  Article? _article(Map<String, dynamic> entry) {
    try {
      return Article.fromJson(entry['article'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// An unreadable store is an empty one.
  Map<String, Map<String, dynamic>> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null) {
      return {};
    }
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (id, entry) => MapEntry(id, entry as Map<String, dynamic>),
      );
    } catch (_) {
      return {};
    }
  }
}
