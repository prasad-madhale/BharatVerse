import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/services/pending_saves.dart';

void main() {
  late SharedPreferences prefs;
  late PendingSaves pendingSaves;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    pendingSaves = PendingSaves(prefs);
  });

  group('PendingSaves', () {
    test('has nothing queued until something is set', () {
      expect(pendingSaves.forUser('alice'), isEmpty);
    });

    test('remembers a queued save across instances', () async {
      await pendingSaves.set('alice', 'art_1', true);

      expect(PendingSaves(prefs).forUser('alice'), {'art_1': true});
    });

    test('a later set for the same article replaces the earlier one', () async {
      await pendingSaves.set('alice', 'art_1', true);
      await pendingSaves.set('alice', 'art_1', false);

      expect(pendingSaves.forUser('alice'), {'art_1': false});
    });

    test('keeps each user\'s queue separate', () async {
      await pendingSaves.set('alice', 'art_1', true);
      await pendingSaves.set('bob', 'art_1', false);

      expect(pendingSaves.forUser('alice'), {'art_1': true});
      expect(pendingSaves.forUser('bob'), {'art_1': false});
    });

    test('clear drops just the one entry', () async {
      await pendingSaves.set('alice', 'art_1', true);
      await pendingSaves.set('alice', 'art_2', false);

      await pendingSaves.clear('alice', 'art_1');

      expect(pendingSaves.forUser('alice'), {'art_2': false});
    });

    test('clear on an article that was never queued does nothing', () async {
      await pendingSaves.clear('alice', 'art_1');

      expect(pendingSaves.forUser('alice'), isEmpty);
    });

    test('an unreadable store is treated as empty', () async {
      SharedPreferences.setMockInitialValues({'pending_saves_v1': 'not json'});
      final broken = PendingSaves(await SharedPreferences.getInstance());

      expect(broken.forUser('alice'), isEmpty);
    });
  });
}
