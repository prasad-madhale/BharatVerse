import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/theme/app_colors.dart';
import 'package:bharatverse_app/widgets/like_button.dart';

import '../support/like_fixtures.dart';

void main() {
  late MockGoTrueClient authClient;
  late MockLikesClient likesClient;

  /// Pumps a LikeButton for article 'art_1'; [onRequireAuth] defaults to doing nothing.
  Future<void> pumpButton(
    WidgetTester tester, {
    VoidCallback? onRequireAuth,
  }) async {
    await tester.pumpWidget(
      withLikeProviders(
        authState: AuthState(authClient: authClient),
        likesClient: likesClient,
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
    authClient = stubAuthClient();
    likesClient = stubLikesClient();
  });

  group('LikeButton', () {
    testWidgets('shows an outline heart when the article is not liked',
        (tester) async {
      authClient.signInAs(testUser());

      await pumpButton(tester);

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byTooltip('Like'), findsOneWidget);
    });

    testWidgets('shows a filled heart in the like accent when liked',
        (tester) async {
      authClient.signInAs(testUser());
      when(() => likesClient.getLikedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});

      await pumpButton(tester);

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byTooltip('Unlike'), findsOneWidget);
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.color, AppColors.likeActive);
    });

    testWidgets('tapping while signed in likes the article', (tester) async {
      authClient.signInAs(testUser());
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
      authClient.signInAs(testUser());
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

  group('LikeButton failure messages', () {
    testWidgets('says plainly that the server could not be reached',
        (tester) async {
      authClient.signInAs(testUser());
      when(() => likesClient.like(
                accessToken: any(named: 'accessToken'),
                userId: any(named: 'userId'),
                articleId: any(named: 'articleId'),
              ))
          .thenThrow(ApiException(
              'Could not reach the server. Check your connection and try again.'));
      await pumpButton(tester);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(
          find.text(
              'Could not reach the server. Check your connection and try again.'),
          findsOneWidget);
    });

    testWidgets('names the status when the server refused', (tester) async {
      authClient.signInAs(testUser());
      when(() => likesClient.like(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Request failed (500)', statusCode: 500));
      await pumpButton(tester);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('Could not update your like (500). Please try again.'),
          findsOneWidget);
    });
  });

  testWidgets('animates between the outline and the filled heart',
      (tester) async {
    authClient.signInAs(testUser());
    await pumpButton(tester);

    await tester.tap(find.byType(IconButton));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget); // fading out

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });
}
