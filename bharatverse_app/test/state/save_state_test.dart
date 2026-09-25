import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as gotrue
    show AuthState;

import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/services/pending_saves.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/save_state.dart';

import '../support/like_fixtures.dart';

void main() {
  late MockGoTrueClient authClient;
  late MockSavesClient savesClient;
  late StreamController<gotrue.AuthState> authEvents;
  late AuthState authState;

  /// Tells listeners the auth state changed, as Supabase would.
  Future<void> emitAuthChange(AuthChangeEvent event) async {
    authEvents.add(gotrue.AuthState(event, authClient.currentSession));
    await pumpEventQueue();
  }

  SaveState makeSaveState({PendingSaves? pendingSaves}) => SaveState(
        savesClient: savesClient,
        authState: authState,
        pendingSaves: pendingSaves,
      );

  setUp(() {
    authClient = MockGoTrueClient()..signInAs(null);
    savesClient = stubSavesClient();
    authEvents = StreamController<gotrue.AuthState>.broadcast();
    addTearDown(authEvents.close);
    when(() => authClient.onAuthStateChange)
        .thenAnswer((_) => authEvents.stream);
    authState = AuthState(authClient: authClient);
    SharedPreferences.setMockInitialValues({});
  });

  group('SaveState loading', () {
    test('nothing is saved, and nothing is fetched, when signed out', () {
      final saveState = makeSaveState();

      expect(saveState.isSaved('art_1'), isFalse);
      verifyNever(() => savesClient.getSavedArticleIds(
            accessToken: any(named: 'accessToken'),
          ));
    });

    test("loads the user's saves when already signed in", () async {
      authClient.signInAs(testUser());
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});

      final saveState = makeSaveState();
      await pumpEventQueue();

      expect(saveState.isSaved('art_1'), isTrue);
      expect(saveState.isSaved('art_2'), isFalse);
    });

    test('loads the saves when a user signs in later', () async {
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final saveState = makeSaveState();

      authClient.signInAs(testUser());
      await emitAuthChange(AuthChangeEvent.signedIn);

      expect(saveState.isSaved('art_1'), isTrue);
    });

    test('notifies listeners once the saves have loaded', () async {
      authClient.signInAs(testUser());
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final saveState = makeSaveState();
      var notified = 0;
      saveState.addListener(() => notified++);

      await pumpEventQueue();

      expect(notified, 1);
    });

    test('forgets the saves when the user signs out', () async {
      authClient.signInAs(testUser());
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final saveState = makeSaveState();
      await pumpEventQueue();

      authClient.signInAs(null);
      await emitAuthChange(AuthChangeEvent.signedOut);

      expect(saveState.isSaved('art_1'), isFalse);
    });

    test("a different account never sees the previous user's saves", () async {
      authClient.signInAs(testUser(id: 'alice'), token: 'alice-token');
      when(() => savesClient.getSavedArticleIds(accessToken: 'alice-token'))
          .thenAnswer((_) async => {'art_1'});
      final saveState = makeSaveState();
      await pumpEventQueue();

      authClient.signInAs(testUser(id: 'bob'), token: 'bob-token');
      await emitAuthChange(AuthChangeEvent.signedIn);

      expect(saveState.isSaved('art_1'), isFalse);
    });

    test("does not reload when the same user's token refreshes", () async {
      authClient.signInAs(testUser());
      makeSaveState();
      await pumpEventQueue();

      await emitAuthChange(AuthChangeEvent.tokenRefreshed);

      verify(() => savesClient.getSavedArticleIds(
            accessToken: any(named: 'accessToken'),
          )).called(1);
    });

    test('ignores a load that finishes after the user signed out', () async {
      final slowLoad = Completer<Set<String>>();
      authClient.signInAs(testUser());
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) => slowLoad.future);
      final saveState = makeSaveState();

      authClient.signInAs(null);
      await emitAuthChange(AuthChangeEvent.signedOut);
      slowLoad.complete({'art_1'});
      await pumpEventQueue();

      expect(saveState.isSaved('art_1'), isFalse);
    });

    test('a failed load leaves the saves empty and does not throw', () async {
      authClient.signInAs(testUser());
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenThrow(ApiException('Could not reach the server'));

      final saveState = makeSaveState();
      await pumpEventQueue();

      expect(saveState.isSaved('art_1'), isFalse);
    });
  });

  group('SaveState.toggleSave', () {
    test('saves an unsaved article, showing it immediately', () async {
      authClient.signInAs(testUser());
      final request = Completer<void>();
      when(() => savesClient.save(
            accessToken: 'user-token',
            userId: 'user-123',
            articleId: 'art_1',
          )).thenAnswer((_) => request.future);
      final saveState = makeSaveState();
      await pumpEventQueue();

      final toggled = saveState.toggleSave('art_1');

      expect(saveState.isSaved('art_1'), isTrue);
      request.complete();
      await toggled;
      verify(() => savesClient.save(
            accessToken: 'user-token',
            userId: 'user-123',
            articleId: 'art_1',
          )).called(1);
    });

    test('unsaves a saved article', () async {
      authClient.signInAs(testUser());
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final saveState = makeSaveState();
      await pumpEventQueue();

      await saveState.toggleSave('art_1');

      expect(saveState.isSaved('art_1'), isFalse);
      verify(() => savesClient.unsave(
            accessToken: 'user-token',
            articleId: 'art_1',
          )).called(1);
    });

    test('rolls back and rethrows when saving fails', () async {
      authClient.signInAs(testUser());
      when(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Article not found', statusCode: 404));
      final saveState = makeSaveState();
      await pumpEventQueue();

      await expectLater(
        saveState.toggleSave('art_missing'),
        throwsA(isA<ApiException>()),
      );

      expect(saveState.isSaved('art_missing'), isFalse);
    });

    test('rolls back an unsave that fails', () async {
      authClient.signInAs(testUser());
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      when(() => savesClient.unsave(
            accessToken: any(named: 'accessToken'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Request failed (500)', statusCode: 500));
      final saveState = makeSaveState();
      await pumpEventQueue();

      await expectLater(
        saveState.toggleSave('art_1'),
        throwsA(isA<ApiException>()),
      );

      expect(saveState.isSaved('art_1'), isTrue);
    });

    test('ignores a second tap while the first is still in flight', () async {
      authClient.signInAs(testUser());
      final request = Completer<void>();
      when(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenAnswer((_) => request.future);
      final saveState = makeSaveState();
      await pumpEventQueue();

      final first = saveState.toggleSave('art_1');
      final second = saveState.toggleSave('art_1');
      request.complete();
      await Future.wait([first, second]);

      expect(saveState.isSaved('art_1'), isTrue);
      verify(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).called(1);
    });

    test('notifies listeners on the optimistic change and on a rollback',
        () async {
      authClient.signInAs(testUser());
      when(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Request failed (500)', statusCode: 500));
      final saveState = makeSaveState();
      await pumpEventQueue();
      var notified = 0;
      saveState.addListener(() => notified++);

      await expectLater(
        saveState.toggleSave('art_1'),
        throwsA(isA<ApiException>()),
      );

      expect(notified, 2);
    });

    test('throws a StateError when nobody is signed in', () async {
      final saveState = makeSaveState();

      expect(() => saveState.toggleSave('art_1'), throwsStateError);
      verifyNever(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          ));
    });

    test('does not bring back an unsave after the account changed mid-request',
        () async {
      // A rollback that ignores the account change would re-add the id and leak a save.
      authClient.signInAs(testUser());
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});
      final request = Completer<void>();
      when(() => savesClient.unsave(
            accessToken: any(named: 'accessToken'),
            articleId: any(named: 'articleId'),
          )).thenAnswer((_) => request.future);
      final saveState = makeSaveState();
      await pumpEventQueue();

      final toggled = saveState.toggleSave('art_1');
      authClient.signInAs(null);
      await emitAuthChange(AuthChangeEvent.signedOut);
      request.completeError(ApiException('Request failed (500)'));
      await expectLater(toggled, throwsA(isA<ApiException>()));

      expect(saveState.isSaved('art_1'), isFalse);
    });
  });

  group('SaveState offline queueing', () {
    late PendingSaves pendingSaves;

    setUp(() async {
      pendingSaves = PendingSaves(await SharedPreferences.getInstance());
    });

    test('keeps the change and queues it when the server cannot be reached',
        () async {
      authClient.signInAs(testUser());
      when(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Could not reach the server'));
      final saveState = makeSaveState(pendingSaves: pendingSaves);
      await pumpEventQueue();

      await saveState.toggleSave('art_1');

      expect(saveState.isSaved('art_1'), isTrue);
      expect(pendingSaves.forUser('user-123'), {'art_1': true});
    });

    test(
        'still rolls back and rethrows when there is no queue to keep the change in',
        () async {
      authClient.signInAs(testUser());
      when(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Could not reach the server'));
      final saveState = makeSaveState();
      await pumpEventQueue();

      await expectLater(
        saveState.toggleSave('art_1'),
        throwsA(isA<ApiException>()),
      );

      expect(saveState.isSaved('art_1'), isFalse);
    });

    test('sends a queued save once the server can be reached again', () async {
      authClient.signInAs(testUser());
      await pendingSaves.set('user-123', 'art_1', true);

      makeSaveState(pendingSaves: pendingSaves);
      await pumpEventQueue();

      verify(() => savesClient.save(
            accessToken: 'user-token',
            userId: 'user-123',
            articleId: 'art_1',
          )).called(1);
      expect(pendingSaves.forUser('user-123'), isEmpty);
    });

    test('drops a queued change the server refuses outright', () async {
      authClient.signInAs(testUser());
      await pendingSaves.set('user-123', 'art_1', true);
      when(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Article not found', statusCode: 404));

      makeSaveState(pendingSaves: pendingSaves);
      await pumpEventQueue();

      expect(pendingSaves.forUser('user-123'), isEmpty);
    });

    test('leaves a queued change queued while the server is still unreachable',
        () async {
      authClient.signInAs(testUser());
      await pendingSaves.set('user-123', 'art_1', true);
      when(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Could not reach the server'));

      makeSaveState(pendingSaves: pendingSaves);
      await pumpEventQueue();

      expect(pendingSaves.forUser('user-123'), {'art_1': true});
    });

    test('flushes other queued articles once a toggle reaches the server',
        () async {
      authClient.signInAs(testUser());
      await pendingSaves.set('user-123', 'art_2', false);
      final saveState = makeSaveState(pendingSaves: pendingSaves);
      await pumpEventQueue();

      await saveState.toggleSave('art_1');
      await pumpEventQueue();

      verify(() => savesClient.unsave(
            accessToken: 'user-token',
            articleId: 'art_2',
          )).called(1);
      expect(pendingSaves.forUser('user-123'), isEmpty);
    });
  });

  group('SaveState.dispose', () {
    test('stops following auth changes', () async {
      final saveState = makeSaveState();
      saveState.dispose();
      authClient.signInAs(testUser());
      clearInteractions(authClient);

      await emitAuthChange(AuthChangeEvent.signedIn);

      // A SaveState still subscribed would read the current user in response.
      verifyNever(() => authClient.currentUser);
    });
  });
}
