import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/screens/library_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/services/reading_history.dart';
import 'package:bharatverse_app/state/auth_state.dart';

import '../support/article_fixtures.dart';
import '../support/like_fixtures.dart';

Future<Widget> _wrap(
  ApiClient apiClient, {
  bool signedIn = false,
  MockSavesClient? savesClient,
}) async =>
    Provider<ReadingHistory>.value(
      value: ReadingHistory(await SharedPreferences.getInstance()),
      child: withLikeProviders(
        authState: AuthState(
            authClient: stubAuthClient()
              ..signInAs(signedIn ? testUser() : null)),
        likesClient: stubLikesClient(),
        savesClient: savesClient ?? stubSavesClient(),
        child: MaterialApp(home: LibraryScreen(apiClient: apiClient)),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows nothing saved and no recently read while signed out',
      (tester) async {
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

    await tester.pumpWidget(await _wrap(apiClient));
    await tester.pumpAndSettle();

    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.text('Recently read'), findsNothing);
  });

  testWidgets('lists the saved articles when signed in', (tester) async {
    final client = MockSavesClient();
    when(() =>
            client.getSavedArticleIds(accessToken: any(named: 'accessToken')))
        .thenAnswer((_) async => <String>{});
    when(() =>
            client.getSavedArticleRows(accessToken: any(named: 'accessToken')))
        .thenAnswer((_) async => [
              sampleArticleRow(id: 'a1', title: 'Saved One'),
              sampleArticleRow(id: 'a2', title: 'Saved Two'),
            ]);
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

    await tester.pumpWidget(
        await _wrap(apiClient, signedIn: true, savesClient: client));
    await tester.pumpAndSettle();

    expect(find.text('Saved · 2'), findsOneWidget);
    expect(find.text('Saved One'), findsOneWidget);
    expect(find.text('Saved Two'), findsOneWidget);
    expect(find.text('Nothing saved yet'), findsNothing);
  });

  testWidgets('shows a retry when loading saved articles fails',
      (tester) async {
    final client = MockSavesClient();
    when(() =>
            client.getSavedArticleIds(accessToken: any(named: 'accessToken')))
        .thenAnswer((_) async => <String>{});
    when(() =>
            client.getSavedArticleRows(accessToken: any(named: 'accessToken')))
        .thenThrow(ApiException('Could not reach the server'));
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

    await tester.pumpWidget(
        await _wrap(apiClient, signedIn: true, savesClient: client));
    await tester.pumpAndSettle();

    expect(find.text('COULD NOT LOAD YOUR SAVED ARTICLES'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('lists recently read articles from ReadingHistory',
      (tester) async {
    final history = ReadingHistory(await SharedPreferences.getInstance());
    await history.recordOpened('art_20260703_001');
    final apiClient = ApiClient(
        client:
            articlesMockClient(() => [sampleArticleRow(title: 'Read Before')]));

    await tester.pumpWidget(Provider<ReadingHistory>.value(
      value: history,
      child: withLikeProviders(
        authState: AuthState(authClient: stubAuthClient()),
        likesClient: stubLikesClient(),
        savesClient: stubSavesClient(),
        child: MaterialApp(home: LibraryScreen(apiClient: apiClient)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Recently read'), findsOneWidget);
    expect(find.text('Read Before'), findsOneWidget);
  });

  testWidgets('opening a saved article navigates to it', (tester) async {
    final client = MockSavesClient();
    when(() =>
            client.getSavedArticleIds(accessToken: any(named: 'accessToken')))
        .thenAnswer((_) async => <String>{});
    when(() =>
            client.getSavedArticleRows(accessToken: any(named: 'accessToken')))
        .thenAnswer((_) async => [sampleArticleRow()]);
    final apiClient = ApiClient(client: articlesMockClient(() => []));

    await tester.pumpWidget(
        await _wrap(apiClient, signedIn: true, savesClient: client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The Mauryan Empire'));
    await tester.pumpAndSettle();

    expect(find.byType(ArticleDetailScreen), findsOneWidget);
  });
}
