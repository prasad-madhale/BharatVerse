---
id: TASK-015
title: Add a like button to the article screen
depends_on: TASK-014
requires: flutter, dart
allowed: bharatverse_app/lib/widgets/like_button.dart, bharatverse_app/lib/screens/article_detail_screen.dart, bharatverse_app/lib/main.dart, bharatverse_app/test/widgets/like_button_test.dart, bharatverse_app/test/screens/article_detail_screen_test.dart, bharatverse_app/test/screens/home_screen_test.dart
verify: cd "$BV_ROOT/bharatverse_app" && flutter test --no-pub test/widgets/like_button_test.dart test/screens/article_detail_screen_test.dart test/screens/home_screen_test.dart
verify: cd "$BV_ROOT/bharatverse_app" && dart format --output=none --set-exit-if-changed .
verify: cd "$BV_ROOT/bharatverse_app" && flutter analyze --no-pub
verify: cd "$BV_ROOT/bharatverse_app" && flutter test --no-pub --coverage
verify: cd "$BV_ROOT" && ./scripts/check_lcov_coverage.sh bharatverse_app/coverage/lcov.info 85 "lib/main.dart"
commit: feat: add a like button to the article screen
---

# TASK-015: Add a like button to the article screen

## Why

This puts the like feature in front of the user. A heart button, `LikeButton`, goes in the article screen's header, in the slot
that held a spacer commented "balances the back button". It is outline when the article is not liked and filled in the
like accent when it is. A signed-out user who taps it is sent to the sign-in screen, because only a signed-in user has
likes. If the request fails, the heart rolls back and a message says so.

The button builds on `AppIconButton`, whose `active` state already uses the accent `AppColors.likeActive` is defined
as, so the widget adds no styling of its own. `main.dart` provides the `LikeState`, created after the `AuthState` it
follows.

The detail screen now needs a `LikeState` above it, so the home screen test's provider wrapper gains one. Its
navigation test pushes the detail screen and would otherwise fail.

## Conventions to match

This code follows the app's existing patterns, so copy it exactly rather than restyling it. State classes extend
`ChangeNotifier` and take their dependencies in the constructor, like `AuthState`. Services take an injectable
`http.Client` and throw `ApiException`, like `ApiClient`. Tests use `mocktail` for collaborators and `MockClient` to
assert the HTTP requests actually sent, grouped per class or method.

## Read first, and nothing else

- `bharatverse_app/lib/screens/article_detail_screen.dart`, only the imports and the header `Row`
- `bharatverse_app/lib/main.dart`
- `bharatverse_app/test/screens/home_screen_test.dart`, only the imports, the mock class, and `_wrapWithProviders`

## Steps

### Step 1. Create the button

Create `bharatverse_app/lib/widgets/like_button.dart` with exactly this content:

<!-- step: create bharatverse_app/lib/widgets/like_button.dart -->
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../state/like_state.dart';
import 'app_icon_button.dart';

/// Heart toggle for an article -- filled in the like accent when the signed-in
/// user has liked it. Only a signed-in user has likes, so a signed-out tap
/// calls [onRequireAuth] instead. Needs an [AuthState] and a [LikeState] above
/// it in the widget tree.
class LikeButton extends StatelessWidget {
  final String articleId;
  final VoidCallback onRequireAuth;

  const LikeButton({
    super.key,
    required this.articleId,
    required this.onRequireAuth,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final likeState = context.watch<LikeState>();
    final liked = likeState.isLiked(articleId);

    return AppIconButton(
      icon: liked ? Icons.favorite : Icons.favorite_border,
      label: liked ? 'Unlike' : 'Like',
      active: liked,
      onPressed: () => authState.isAuthenticated
          ? _toggle(context, likeState)
          : onRequireAuth(),
    );
  }

  Future<void> _toggle(BuildContext context, LikeState likeState) async {
    // Grabbed before the await: the context may be gone by the time it ends.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await likeState.toggle(articleId);
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update your like: $e')),
      );
    }
  }
}
```

### Step 2. Put it in the article screen's header

<!-- step: replace bharatverse_app/lib/screens/article_detail_screen.dart -->
Replace this exact text:

```dart
import '../widgets/citation_item.dart';
```

with this exact text:

```dart
import '../widgets/citation_item.dart';
import '../widgets/like_button.dart';
import 'auth_screen.dart';
```

<!-- step: replace bharatverse_app/lib/screens/article_detail_screen.dart -->
Replace this exact text:

```dart
                const SizedBox(width: 40), // balances the back button
```

with this exact text:

```dart
                LikeButton(
                  articleId: article.id,
                  onRequireAuth: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  ),
                ),
```

### Step 3. Provide `LikeState` in the app

<!-- step: replace bharatverse_app/lib/main.dart -->
Replace this exact text:

```dart
import 'services/api_client.dart';
import 'state/auth_state.dart';
```

with this exact text:

```dart
import 'services/api_client.dart';
import 'services/likes_client.dart';
import 'state/auth_state.dart';
import 'state/like_state.dart';
```

<!-- step: replace bharatverse_app/lib/main.dart -->
Replace this exact text:

```dart
    return ChangeNotifierProvider(
      create: (_) => AuthState(),
      child: MaterialApp(
```

with this exact text:

```dart
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState()),
        // LikeState follows AuthState, so it is created after it.
        ChangeNotifierProvider(
          create: (context) => LikeState(
            likesClient: LikesClient(),
            authState: context.read<AuthState>(),
          ),
        ),
      ],
      child: MaterialApp(
```

### Step 4. Give the home screen test a `LikeState`

Four edits to `bharatverse_app/test/screens/home_screen_test.dart`.

<!-- step: replace bharatverse_app/test/screens/home_screen_test.dart -->
Replace this exact text:

```dart
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
```

with this exact text:

```dart
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/services/likes_client.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/like_state.dart';
```

<!-- step: replace bharatverse_app/test/screens/home_screen_test.dart -->
Replace this exact text:

```dart
class MockGoTrueClient extends Mock implements GoTrueClient {}
```

with this exact text:

```dart
class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockLikesClient extends Mock implements LikesClient {}
```

<!-- step: replace bharatverse_app/test/screens/home_screen_test.dart -->
Replace this exact text:

```dart
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
```

with this exact text:

```dart
/// Wraps HomeScreen with a signed-out AuthState and the LikeState that
/// follows it -- HomeScreen's account icon (a Consumer widget for AuthState)
/// and the detail screen's like button both need a Provider ancestor
/// regardless of whether a given test cares about auth or likes at all.
Widget _wrapWithProviders(ApiClient apiClient) {
  final mockAuthClient = MockGoTrueClient();
  when(() => mockAuthClient.currentUser).thenReturn(null);
  when(() => mockAuthClient.onAuthStateChange)
      .thenAnswer((_) => const Stream.empty());
  final authState = AuthState(authClient: mockAuthClient);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: authState),
      ChangeNotifierProvider(
        create: (_) => LikeState(
          likesClient: MockLikesClient(),
          authState: authState,
        ),
      ),
    ],
    child: MaterialApp(home: HomeScreen(apiClient: apiClient)),
  );
}
```

### Step 5. Create the widget tests

Create `bharatverse_app/test/widgets/like_button_test.dart` with exactly this content:

<!-- step: create bharatverse_app/test/widgets/like_button_test.dart -->
```dart
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
```

Create `bharatverse_app/test/screens/article_detail_screen_test.dart` with exactly this content:

<!-- step: create bharatverse_app/test/screens/article_detail_screen_test.dart -->
```dart
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
```

## Verify

Run every `verify:` command from the front matter and make each one exit 0. CI enforces `dart format`, so if the
format check reports files, run `dart format <each file you changed>` and check again. Always pass `--no-pub` to
`flutter test` and `flutter analyze`: without it Flutter rewrites `pubspec.lock`, which you must not change. Do not
edit any file that is not listed under `allowed`.

## Definition of done

- Every step above was applied exactly as written.
- Every `verify:` command exits 0.
- Only files listed under `allowed` changed.
- You did not run git commit, checkout, reset, or push. The runner commits.

## Out of scope

Do not add a liked-articles screen, a like count, or a search screen. Do not touch
`integration_test/app_screenshot_test.dart`, which is already stale and is not run in CI. Do not change `pubspec.yaml`
or `pubspec.lock`.
