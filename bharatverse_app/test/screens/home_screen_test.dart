import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:bharatverse_app/screens/home_screen.dart';
import 'package:bharatverse_app/screens/search_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/article_card.dart';
import '../support/like_fixtures.dart' show MockLikesClient, withLikeProviders;
import '../support/article_fixtures.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

/// Wraps HomeScreen with a signed-out AuthState and LikeState: the account icon
/// and the detail screen's like button need them whether or not a test cares.
Widget _wrapWithProviders(ApiClient apiClient) {
  final mockAuthClient = MockGoTrueClient();
  when(() => mockAuthClient.currentUser).thenReturn(null);
  when(() => mockAuthClient.onAuthStateChange)
      .thenAnswer((_) => const Stream.empty());

  return withLikeProviders(
    authState: AuthState(authClient: mockAuthClient),
    likesClient: MockLikesClient(),
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

    expect(find.text('Sign In'), findsWidgets);
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
}
