import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/theme/app_colors.dart';
import 'package:bharatverse_app/widgets/save_button.dart';

import '../support/like_fixtures.dart';

void main() {
  late MockGoTrueClient authClient;
  late MockLikesClient likesClient;
  late MockSavesClient savesClient;

  /// Pumps a SaveButton for article 'art_1'; [onRequireAuth] defaults to doing nothing.
  Future<void> pumpButton(
    WidgetTester tester, {
    VoidCallback? onRequireAuth,
  }) async {
    await tester.pumpWidget(
      withLikeProviders(
        authState: AuthState(authClient: authClient),
        likesClient: likesClient,
        savesClient: savesClient,
        child: MaterialApp(
          home: Scaffold(
            body: SaveButton(
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
    savesClient = stubSavesClient();
  });

  group('SaveButton', () {
    testWidgets('shows an outline bookmark when the article is not saved',
        (tester) async {
      authClient.signInAs(testUser());

      await pumpButton(tester);

      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsNothing);
      expect(find.byTooltip('Save'), findsOneWidget);
    });

    testWidgets('shows a filled bookmark in the accent colour when saved',
        (tester) async {
      authClient.signInAs(testUser());
      when(() => savesClient.getSavedArticleIds(accessToken: 'user-token'))
          .thenAnswer((_) async => {'art_1'});

      await pumpButton(tester);

      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byTooltip('Remove from saved'), findsOneWidget);
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.color, AppColorTokens.light.accentPrimary);
    });

    testWidgets('tapping while signed in saves the article', (tester) async {
      authClient.signInAs(testUser());
      await pumpButton(tester);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      verify(() => savesClient.save(
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
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      verifyNever(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          ));
    });

    testWidgets('shows a message and rolls back when saving fails',
        (tester) async {
      authClient.signInAs(testUser());
      when(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Request failed (500)', statusCode: 500));
      await pumpButton(tester);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not update your save'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    });
  });

  group('SaveButton failure messages', () {
    testWidgets('says plainly that the server could not be reached',
        (tester) async {
      authClient.signInAs(testUser());
      when(() => savesClient.save(
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
      when(() => savesClient.save(
            accessToken: any(named: 'accessToken'),
            userId: any(named: 'userId'),
            articleId: any(named: 'articleId'),
          )).thenThrow(ApiException('Request failed (500)', statusCode: 500));
      await pumpButton(tester);

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('Could not update your save (500). Please try again.'),
          findsOneWidget);
    });
  });

  testWidgets('animates between the outline and the filled bookmark',
      (tester) async {
    authClient.signInAs(testUser());
    await pumpButton(tester);

    await tester.tap(find.byType(IconButton));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget); // fading out

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsNothing);
  });
}
