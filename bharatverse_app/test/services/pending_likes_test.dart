import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/services/pending_likes.dart';

void main() {
  late SharedPreferences prefs;
  late PendingLikes pendingLikes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    pendingLikes = PendingLikes(prefs);
  });

  group('PendingLikes', () {
    test('has nothing queued until something is set', () {
      expect(pendingLikes.forUser('alice'), isEmpty);
    });

    test('remembers a queued like across instances', () async {
      await pendingLikes.set('alice', 'art_1', true);

      expect(PendingLikes(prefs).forUser('alice'), {'art_1': true});
    });

    test('a later set for the same article replaces the earlier one', () async {
      await pendingLikes.set('alice', 'art_1', true);
      await pendingLikes.set('alice', 'art_1', false);

      expect(pendingLikes.forUser('alice'), {'art_1': false});
    });

    test('keeps each user\'s queue separate', () async {
      await pendingLikes.set('alice', 'art_1', true);
      await pendingLikes.set('bob', 'art_1', false);

      expect(pendingLikes.forUser('alice'), {'art_1': true});
      expect(pendingLikes.forUser('bob'), {'art_1': false});
    });

    test('clear drops just the one entry', () async {
      await pendingLikes.set('alice', 'art_1', true);
      await pendingLikes.set('alice', 'art_2', false);

      await pendingLikes.clear('alice', 'art_1');

      expect(pendingLikes.forUser('alice'), {'art_2': false});
    });

    test('clear on an article that was never queued does nothing', () async {
      await pendingLikes.clear('alice', 'art_1');

      expect(pendingLikes.forUser('alice'), isEmpty);
    });

    test('an unreadable store is treated as empty', () async {
      SharedPreferences.setMockInitialValues({'pending_likes_v1': 'not json'});
      final broken = PendingLikes(await SharedPreferences.getInstance());

      expect(broken.forUser('alice'), isEmpty);
    });
  });
}
