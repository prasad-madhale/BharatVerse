import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/screens/app_shell.dart';
import 'package:bharatverse_app/screens/search_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';

import '../support/article_fixtures.dart';
import '../support/like_fixtures.dart'
    show stubAuthClient, stubLikesClient, stubSavesClient, withLikeProviders;

Widget _wrap(ApiClient apiClient) => withLikeProviders(
      authState: AuthState(authClient: stubAuthClient()),
      likesClient: stubLikesClient(),
      savesClient: stubSavesClient(),
      child: MaterialApp(home: AppShell(apiClient: apiClient)),
    );

void main() {
  testWidgets('starts on the Today tab, showing the daily article',
      (tester) async {
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

    await tester.pumpWidget(_wrap(apiClient));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('switching to the Library tab shows LikedArticlesScreen',
      (tester) async {
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

    await tester.pumpWidget(_wrap(apiClient));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    // ScreenHeading renders its text uppercased.
    expect(find.text('LIKED ARTICLES'), findsOneWidget);
  });

  testWidgets('the search button opens SearchScreen', (tester) async {
    final apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));

    await tester.pumpWidget(_wrap(apiClient));
    await tester.pumpAndSettle();

    // HomeScreen's own header (replaced in Phase 3) also has a "Search"
    // tooltip -- AppShell's floating button is the last one in the tree.
    await tester.tap(find.byTooltip('Search').last);
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
  });
}
