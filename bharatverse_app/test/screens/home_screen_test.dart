import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:bharatverse_app/screens/archive_screen.dart';
import 'package:bharatverse_app/screens/home_screen.dart';
import 'package:bharatverse_app/screens/liked_articles_screen.dart';
import 'package:bharatverse_app/screens/search_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/article_card.dart';
import '../support/like_fixtures.dart'
    show MockLikesClient, MockSavesClient, testUser, withLikeProviders;
import '../support/article_fixtures.dart';
import '../support/layout_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bharatverse_app/services/article_cache.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

/// Wraps HomeScreen with a signed-out AuthState and LikeState: the account icon
/// and the detail screen's like button need them whether or not a test cares.
Widget _wrapWithProviders(ApiClient apiClient, {bool signedIn = false}) {
  final mockAuthClient = MockGoTrueClient();
  when(() => mockAuthClient.currentUser)
      .thenReturn(signedIn ? testUser() : null);
  when(() => mockAuthClient.onAuthStateChange)
      .thenAnswer((_) => const Stream.empty());

  return withLikeProviders(
    authState: AuthState(authClient: mockAuthClient),
    likesClient: MockLikesClient(),
    savesClient: MockSavesClient(),
    child: MaterialApp(home: HomeScreen(apiClient: apiClient)),
  );
}

void main() {
  testWidgets('shows the daily article once loaded', (tester) async {
    final mockClient = articlesMockClient(() => [sampleArticleRow()]);
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(_wrapWithProviders(apiClient));

    // Loading state first.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('THE MAURYAN EMPIRE'), findsOneWidget);
    expect(find.text('A summary of the Mauryan Empire.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows up to 5 articles with the label only on the first',
      (tester) async {
    // Tall enough that ListView.builder lays out all 5 cards without needing
    // to scroll -- it only builds what's within the viewport.
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final mockClient = articlesMockClient(() => List.generate(
          5,
          (i) => sampleArticleRow(id: 'art_$i', title: 'Article $i'),
        ));
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      expect(find.text('ARTICLE $i'), findsOneWidget);
    }
    expect(find.byType(ArticleCard), findsNWidgets(5));
    expect(find.text('TODAY\'S ARTICLE'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no articles',
      (tester) async {
    final mockClient = MockClient((request) async => http.Response('[]', 200));
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    expect(find.text('NO ARTICLES YET'), findsOneWidget);
    expect(find.text('Check back soon!'), findsOneWidget);
    expect(find.byType(ArticleCard), findsNothing);
  });

  testWidgets('shows an error state with retry when the request fails',
      (tester) async {
    var restCallCount = 0;
    final mockClient = MockClient((request) async {
      if (request.url.path.contains('/storage/')) {
        return http.Response(jsonEncode(sampleArticleContent()), 200);
      }
      restCallCount++;
      if (restCallCount == 1) {
        return http.Response('error', 500);
      }
      return http.Response(jsonEncode([sampleArticleRow()]), 200);
    });
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('THE MAURYAN EMPIRE'), findsOneWidget);
  });

  testWidgets('navigates to article detail on tap', (tester) async {
    final mockClient = articlesMockClient(() => [sampleArticleRow()]);
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ArticleCard));
    await tester.pumpAndSettle();

    // Detail screen renders the (uppercased) section heading.
    expect(find.text('ORIGINS'), findsOneWidget);
  });

  testWidgets(
      'shows a sign-in icon when logged out and opens AuthScreen on tap',
      (tester) async {
    final mockClient = articlesMockClient(() => [sampleArticleRow()]);
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.login), findsOneWidget);

    await tester.tap(find.byIcon(Icons.login));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('the search icon opens the search screen', (tester) async {
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));
    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
  });

  group('the liked-articles icon', () {
    late ApiClient apiClient;

    setUp(() {
      apiClient =
          ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));
    });

    testWidgets('is only there while signed in', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(apiClient));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Liked articles'), findsNothing);

      await tester.pumpWidget(_wrapWithProviders(apiClient, signedIn: true));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Liked articles'), findsOneWidget);
    });

    testWidgets('opens the liked articles', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(apiClient, signedIn: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Liked articles'));
      await tester.pumpAndSettle();

      expect(find.byType(LikedArticlesScreen), findsOneWidget);
    });
  });

  testWidgets('hides an unexpected error behind a generic message',
      (tester) async {
    final apiClient = ApiClient(
        client: MockClient((_) async => http.Response('not json', 200)));
    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    expect(
        find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
  });

  testWidgets('keeps its cards in a readable column on a wide screen',
      (tester) async {
    useWideScreen(tester);
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));
    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ArticleCard)).width, 720 - 2 * 16);
  });

  testWidgets('keeps the header icons in the reading column on a wide screen',
      (tester) async {
    useWideScreen(tester);
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));
    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    // The column is 720 wide, centered in 1600, with 4px and 12px row padding.
    expect(tester.getTopLeft(find.byTooltip('Search')).dx, closeTo(444, 12));
    expect(tester.getTopRight(find.byTooltip('Sign in')).dx, closeTo(1148, 12));
  });

  testWidgets('shows a plain message, not the raw error, when loading fails',
      (tester) async {
    final apiClient = ApiClient(
      client: MockClient((_) async =>
          throw http.ClientException('Failed to fetch, uri=http://internal')),
    );
    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    expect(find.text('COULD NOT LOAD ARTICLES'), findsOneWidget);
    expect(
        find.text(
            'Could not reach the server. Check your connection and try again.'),
        findsOneWidget);
    expect(find.textContaining('uri='), findsNothing);
  });

  group('the archive link', () {
    Future<void> pumpHome(WidgetTester tester, int articles) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final apiClient = ApiClient(
        client: articlesMockClient(() => List.generate(articles,
            (i) => sampleArticleRow(id: 'art_$i', title: 'Article $i'))),
      );
      await tester.pumpWidget(_wrapWithProviders(apiClient));
      await tester.pumpAndSettle();
    }

    testWidgets('follows a full page of recent articles and opens the archive',
        (tester) async {
      await pumpHome(tester, 5);

      await tester.tap(find.text('Browse the archive →'));
      await tester.pumpAndSettle();

      expect(find.byType(ArchiveScreen), findsOneWidget);
    });

    testWidgets('is left out when there is nothing older to browse',
        (tester) async {
      await pumpHome(tester, 3);

      expect(find.text('Browse the archive →'), findsNothing);
    });
  });

  group('offline', () {
    late SharedPreferences prefs;
    late ArticleCache cache;
    late bool online;

    ApiClient client() => ApiClient(
          cache: cache,
          client: MockClient((request) async {
            if (!online) {
              throw http.ClientException('Failed to fetch');
            }
            if (request.url.path.contains('/storage/')) {
              return http.Response(jsonEncode(sampleArticleContent()), 200);
            }
            return http.Response(
                jsonEncode([sampleArticleRow(id: 'live', title: 'Live news')]),
                200);
          }),
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      cache = ArticleCache(prefs);
      await cache.cacheArticle(sampleArticle(id: 'kept', title: 'Kept copy'));
      online = false;
    });

    testWidgets('shows the saved articles with a notice', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(client()));
      await tester.pumpAndSettle();

      expect(find.text('KEPT COPY'), findsOneWidget);
      expect(find.text('OFFLINE · SHOWING SAVED ARTICLES'), findsOneWidget);
    });

    testWidgets('goes back to live articles when a refresh succeeds',
        (tester) async {
      await tester.pumpWidget(_wrapWithProviders(client()));
      await tester.pumpAndSettle();
      online = true;

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(find.text('LIVE NEWS'), findsOneWidget);
      expect(find.text('OFFLINE · SHOWING SAVED ARTICLES'), findsNothing);
    });
  });
}
