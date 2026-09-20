import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:bharatverse_app/models/article.dart';
import 'package:bharatverse_app/screens/article_detail_screen.dart';
import 'package:bharatverse_app/services/likes_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/like_state.dart';
import 'package:bharatverse_app/widgets/like_button.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockLikesClient extends Mock implements LikesClient {}

const _articleId = 'art_20260703_001';

Article sampleArticle() => Article.fromJson({
      'id': _articleId,
      'title': 'The Mauryan Empire',
      'summary': 'A summary.',
      'content': '## Origins\n\nSome content.',
      'sections': [
        {'heading': 'Origins', 'content': 'Some content.', 'order': 1},
      ],
      'citations': [],
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'BharatVerse AI',
      'tags': [],
      'image_url': null,
    });

void main() {
  late MockGoTrueClient authClient;
  late MockLikesClient likesClient;

  /// Pumps the detail screen under a real AuthState and the LikeState that
  /// follows it, as main.dart provides them.
  Future<void> pumpScreen(WidgetTester tester) async {
    final authState = AuthState(authClient: authClient);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: authState),
          ChangeNotifierProvider(
            create: (_) =>
                LikeState(likesClient: likesClient, authState: authState),
          ),
        ],
        child: MaterialApp(
          home: ArticleDetailScreen(article: sampleArticle()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    authClient = MockGoTrueClient();
    likesClient = MockLikesClient();
    when(() => authClient.currentUser).thenReturn(null);
    when(() => authClient.currentSession).thenReturn(null);
    when(() => authClient.onAuthStateChange)
        .thenAnswer((_) => const Stream.empty());
    when(() => likesClient.getLikedArticleIds(
          accessToken: any(named: 'accessToken'),
        )).thenAnswer((_) async => <String>{});
    when(() => likesClient.like(
          accessToken: any(named: 'accessToken'),
          userId: any(named: 'userId'),
          articleId: any(named: 'articleId'),
        )).thenAnswer((_) async {});
  });

  group('ArticleDetailScreen', () {
    testWidgets('shows the article with a like button in the header',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('ORIGINS'), findsOneWidget);
      expect(find.byType(LikeButton), findsOneWidget);
    });

    testWidgets('a signed-out tap on the heart opens the sign-in screen',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsWidgets);
    });

    testWidgets('liking sends this article\'s id', (tester) async {
      final user = User(
        id: 'user-123',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-07-08T00:00:00Z',
      );
      when(() => authClient.currentUser).thenReturn(user);
      when(() => authClient.currentSession).thenReturn(
        Session(accessToken: 'user-token', tokenType: 'bearer', user: user),
      );
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      verify(() => likesClient.like(
            accessToken: 'user-token',
            userId: 'user-123',
            articleId: _articleId,
          )).called(1);
    });
  });
}
