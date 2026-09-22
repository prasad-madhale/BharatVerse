import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/services/article_cache.dart';

import '../support/article_fixtures.dart';

void main() {
  late SharedPreferences prefs;
  late DateTime clock;

  ArticleCache cacheOf({int capacity = 50}) =>
      ArticleCache(prefs, capacity: capacity, now: () => clock);
  void tick() => clock = clock.add(const Duration(minutes: 1));
  Future<List<String>> savedIds(ArticleCache cache) async =>
      [for (final a in await cache.getCachedArticles()) a.id]..sort();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    clock = DateTime(2026, 9, 20, 9);
  });

  group('ArticleCache', () {
    test('keeps an article with all its content intact', () async {
      final cache = cacheOf();
      final article = sampleArticle();

      await cache.cacheArticle(article);

      final saved = await cache.getCachedArticle(article.id);
      expect(saved!.toJson(), article.toJson());
      expect(saved.sections.single.heading, 'Origins');
    });

    test('has nothing until something is cached', () async {
      final cache = cacheOf();

      expect(await cache.getCachedArticle('art_x'), isNull);
      expect(await cache.getCachedArticles(), isEmpty);
    });

    test('lists what it holds newest publication first', () async {
      final cache = cacheOf();
      await cache.cacheArticles([
        sampleArticle(id: 'a', date: '2026-07-01'),
        sampleArticle(id: 'b', date: '2026-07-03'),
        sampleArticle(id: 'c', date: '2026-07-02'),
      ]);

      final ids = [for (final a in await cache.getCachedArticles()) a.id];

      expect(ids, ['b', 'c', 'a']);
    });

    test('replaces an older copy with the latest one', () async {
      final cache = cacheOf();
      await cache.cacheArticle(sampleArticle(id: 'a', title: 'Old title'));

      await cache.cacheArticle(sampleArticle(id: 'a', title: 'New title'));

      final all = await cache.getCachedArticles();
      expect(all.map((a) => a.title), ['New title']);
    });

    test('survives a restart: a new cache over the same store sees it',
        () async {
      await cacheOf().cacheArticle(sampleArticle(id: 'a'));

      expect(await savedIds(cacheOf()), ['a']);
    });

    test('drops the article viewed longest ago when it is full', () async {
      final cache = cacheOf(capacity: 3);
      for (final id in ['a', 'b', 'c', 'd']) {
        await cache.cacheArticle(sampleArticle(id: id));
        tick();
      }

      expect(await savedIds(cache), ['b', 'c', 'd']);
    });

    test('viewing an article again saves it from eviction', () async {
      final cache = cacheOf(capacity: 3);
      for (final id in ['a', 'b', 'c']) {
        await cache.cacheArticle(sampleArticle(id: id));
        tick();
      }
      await cache.cacheArticle(sampleArticle(id: 'a')); // viewed again
      tick();

      await cache.cacheArticle(sampleArticle(id: 'd'));

      expect(await savedIds(cache), ['a', 'c', 'd']);
    });

    test('among articles cached together, the older publication goes first',
        () async {
      final cache = cacheOf(capacity: 3);

      await cache.cacheArticles([
        for (var day = 1; day <= 5; day++)
          sampleArticle(id: 'day$day', date: '2026-07-0$day'),
      ]);

      expect(await savedIds(cache), ['day3', 'day4', 'day5']);
    });

    test('holds at least a week of daily articles by default', () async {
      final cache =
          ArticleCache(prefs); // the default capacity, not the helper's

      await cache.cacheArticles([
        for (var day = 1; day <= 10; day++)
          sampleArticle(
              id: 'day$day', date: '2026-07-${day.toString().padLeft(2, '0')}'),
      ]);

      expect(cache.capacity, greaterThanOrEqualTo(7));
      expect((await cache.getCachedArticles()).length, 10);
    });

    test('treats unreadable stored data as empty, and recovers', () async {
      await prefs.setString('article_cache_v1', 'not json');
      final cache = cacheOf();
      expect(await cache.getCachedArticles(), isEmpty);

      await cache.cacheArticle(sampleArticle(id: 'a'));

      expect(await savedIds(cache), ['a']);
    });

    test('skips an entry that no longer parses', () async {
      final cache = cacheOf();
      await cache.cacheArticle(sampleArticle(id: 'a'));
      final stored = jsonDecode(prefs.getString('article_cache_v1')!) as Map;
      stored['bad'] = {
        'viewedAt': 1,
        'article': {'id': 'bad'}
      };
      await prefs.setString('article_cache_v1', jsonEncode(stored));

      expect(await savedIds(cache), ['a']);
      expect(await cache.getCachedArticle('bad'), isNull);
    });
  });

  test('matches a plain model of the eviction rule under random use', () async {
    final random = Random(7);
    for (var run = 0; run < 80; run++) {
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      final capacity = 1 + random.nextInt(6);
      var clock = DateTime(2026, 9, 20);
      final cache = ArticleCache(store, capacity: capacity, now: () => clock);
      final model = <String, List<Object>>{}; // id -> [viewedAt, date]

      for (var step = 0; step < 40; step++) {
        if (random.nextBool()) {
          clock = clock.add(const Duration(minutes: 1));
        }
        final batch = [
          for (var i = 0; i < 1 + random.nextInt(3); i++)
            sampleArticle(
              id: 'a${random.nextInt(10)}',
              date: '2026-07-0${1 + random.nextInt(9)}',
            ),
        ];

        await cache.cacheArticles(batch);

        for (final article in batch) {
          model[article.id] = [
            clock.millisecondsSinceEpoch,
            article.toJson()['publication_date'] as String,
          ];
        }
        while (model.length > capacity) {
          // Drop the entry viewed longest ago; among equals the older
          // publication, then the smaller id.
          final victim = model.entries.reduce((a, b) {
            final byView = (a.value[0] as int).compareTo(b.value[0] as int);
            if (byView != 0) return byView < 0 ? a : b;
            final byDate =
                (a.value[1] as String).compareTo(b.value[1] as String);
            if (byDate != 0) return byDate < 0 ? a : b;
            return a.key.compareTo(b.key) < 0 ? a : b;
          });
          model.remove(victim.key);
        }

        final saved = await savedIds(cache);
        expect(saved, model.keys.toList()..sort(),
            reason: 'run $run step $step');
        expect(saved.length, lessThanOrEqualTo(capacity));
      }
    }
  });
}
