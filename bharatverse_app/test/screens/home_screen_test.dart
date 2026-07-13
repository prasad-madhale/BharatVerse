import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:bharatverse_app/screens/home_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/article_card.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

Map<String, dynamic> sampleArticleJson({
  String id = 'art_20260703_001',
  String title = 'The Mauryan Empire',
}) =>
    {
      'id': id,
      'title': title,
      'summary': 'A summary of the Mauryan Empire.',
      'content': '## Origins\n\nSome content.',
      'sections': [
        {'heading': 'Origins', 'content': 'Some content.', 'order': 1},
      ],
      'citations': [],
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'BharatVerse AI',
      'tags': ['mauryan-empire'],
      'image_url': null,
    };

/// Wraps HomeScreen with a signed-out AuthState -- HomeScreen's account icon
/// (a Consumer widget for AuthState) needs a Provider ancestor regardless of
/// whether a given test cares about auth at all.
Widget _wrapWithProviders(ApiClient apiClient) {
  final mockAuthClient = MockGoTrueClient();
  when(() => mockAuthClient.currentUser).thenReturn(null);
  when(() => mockAuthClient.onAuthStateChange)
      .thenAnswer((_) => const Stream.empty());

  return ChangeNotifierProvider(
    create: (_) => AuthState(authClient: mockAuthClient),
    child: MaterialApp(home: HomeScreen(apiClient: apiClient)),
  );
}

void main() {
  testWidgets('shows the daily article once loaded', (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode([sampleArticleJson()]), 200);
    });
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

    final mockClient = MockClient((request) async {
      final articles = List.generate(
        5,
        (i) => sampleArticleJson(id: 'art_$i', title: 'Article $i'),
      );
      return http.Response(jsonEncode(articles), 200);
    });
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
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        return http.Response('error', 500);
      }
      return http.Response(jsonEncode([sampleArticleJson()]), 200);
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
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode([sampleArticleJson()]), 200);
    });
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
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode([sampleArticleJson()]), 200);
    });
    final apiClient = ApiClient(client: mockClient);

    await tester.pumpWidget(_wrapWithProviders(apiClient));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.login), findsOneWidget);

    await tester.tap(find.byIcon(Icons.login));
    await tester.pumpAndSettle();

    expect(find.text('Sign In'), findsWidgets);
  });
}
