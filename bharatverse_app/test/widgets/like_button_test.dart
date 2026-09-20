import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/services/likes_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/like_state.dart';
import 'package:bharatverse_app/theme/app_colors.dart';
import 'package:bharatverse_app/widgets/like_button.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockLikesClient extends Mock implements LikesClient {}

void main() {
  late MockGoTrueClient authClient;
  late MockLikesClient likesClient;

  /// Makes the mocked auth client report a signed-in user.
  void signIn() {
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
  }

  /// Pumps a LikeButton for article 'art_1' under a real AuthState and the
  /// LikeState that follows it. [onRequireAuth] defaults to doing nothing.
  Future<void> pumpButton(
    WidgetTester tester, {
    VoidCallback? onRequireAuth,
  }) async {
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
          home: Scaffold(
            body: LikeButton(
              articleId: 'art_1',
              onRequireAuth: onRequireAuth ?? () {},
            ),
          ),
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

  group('LikeButton', () {
    testWidgets('shows an outline heart when the article is not liked',
        (tester) async {
      signIn();

      await pumpButton(tester);

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byTooltip('Like'), findsOneWidget);
    });

    testWidgets('shows a filled heart in the like accent when liked',
        (tester) async {
      signIn();
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});

      await pumpButton(tester);

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byTooltip('Unlike'), findsOneWidget);
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.color, AppColors.likeActive);
    });

    testWidgets('tapping while signed in likes the article', (tester) async {
      signIn();
      await pumpButton(tester);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      verify(() => likesClient.like(
            accessToken: 'user-token',
            userId: 'user-123',
            articleId: 'art_1',
          )).called(1);
    });

    testWidgets('tapping while signed out asks the user to sign in instead',
        (tester) async {
      var signInRequests = 0;
      await pumpButton(tester, onRequireAuth: () => signInRequests++);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(signInRequests, 1);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      verifyNever(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          ));
    });

    testWidgets('shows a message and rolls back when liking fails',
        (tester) async {
      signIn();
      when(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Request failed (500)', statusCode: 500));
      await pumpButton(tester);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not update your like'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });
  });
}
