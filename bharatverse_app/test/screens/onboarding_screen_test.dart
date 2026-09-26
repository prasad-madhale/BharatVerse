import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/screens/app_shell.dart';
import 'package:bharatverse_app/screens/auth_screen.dart';
import 'package:bharatverse_app/screens/onboarding_screen.dart';
import 'package:bharatverse_app/services/api_client.dart';
import 'package:bharatverse_app/services/reading_history.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/onboarding_state.dart';

import '../support/article_fixtures.dart';
import '../support/like_fixtures.dart'
    show stubAuthClient, stubLikesClient, stubSavesClient, withLikeProviders;

Future<OnboardingState> _openOnboardingState() async {
  SharedPreferences.setMockInitialValues({});
  return OnboardingState.open();
}

// Onboarding can finish onto AppShell (see below), which needs a
// ReadingHistory for its continue-reading bar.
Future<Widget> _wrap(
        ApiClient apiClient, OnboardingState onboardingState) async =>
    ChangeNotifierProvider<ReadingHistory>.value(
      value: ReadingHistory(await SharedPreferences.getInstance()),
      child: withLikeProviders(
        authState: AuthState(authClient: stubAuthClient()),
        likesClient: stubLikesClient(),
        savesClient: stubSavesClient(),
        child: MaterialApp(
          home: OnboardingScreen(
            apiClient: apiClient,
            onboardingState: onboardingState,
          ),
        ),
      ),
    );

void main() {
  late ApiClient apiClient;

  setUp(() {
    apiClient =
        ApiClient(client: articlesMockClient(() => [sampleArticleRow()]));
  });

  testWidgets('starts on the splash, with no Skip button', (tester) async {
    await tester
        .pumpWidget(await _wrap(apiClient, await _openOnboardingState()));
    await tester.pump();

    expect(find.text('BharatVerse'), findsOneWidget);
    expect(find.text('Indian history, one story a day.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('Get started advances through the feature slides',
      (tester) async {
    await tester
        .pumpWidget(await _wrap(apiClient, await _openOnboardingState()));
    await tester.pump();

    await tester.tap(find.text('Get started'));
    await tester.pump();

    expect(find.text('Get smarter, one story at a time'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text("The India you didn't learn in school"), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('History, made a habit'), findsOneWidget);
    // The last slide's button finishes onboarding instead of continuing.
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets(
      'finishing the last slide opens AuthScreen in sign-up mode and marks '
      'onboarding seen', (tester) async {
    final onboardingState = await _openOnboardingState();
    await tester.pumpWidget(await _wrap(apiClient, onboardingState));
    await tester.pump();

    await tester.tap(find.text('Get started')); // splash -> slide 1
    await tester.pump();
    await tester.tap(find.text('Continue')); // slide 1 -> slide 2
    await tester.pump();
    await tester.tap(find.text('Continue')); // slide 2 -> slide 3
    await tester.pump();
    await tester.tap(find.text('Get started')); // slide 3 -> auth
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
    expect(onboardingState.seen, isTrue);
  });

  testWidgets('Skip on a feature slide jumps straight to sign-up',
      (tester) async {
    await tester
        .pumpWidget(await _wrap(apiClient, await _openOnboardingState()));
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
  });

  testWidgets('"I already have an account" on the splash opens sign-in',
      (tester) async {
    await tester
        .pumpWidget(await _wrap(apiClient, await _openOnboardingState()));
    await tester.pump();

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets(
      'continuing from the resulting AuthScreen replaces the stack with '
      'AppShell', (tester) async {
    await tester
        .pumpWidget(await _wrap(apiClient, await _openOnboardingState()));
    await tester.pump();
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now — just browse'));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(AuthScreen), findsNothing);
  });
}
