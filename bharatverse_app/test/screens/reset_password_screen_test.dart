import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:bharatverse_app/screens/reset_password_screen.dart';
import 'package:bharatverse_app/state/auth_state.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class FakeUserResponse extends Fake implements UserResponse {}

void main() {
  late MockGoTrueClient client;
  late AuthState authState;

  setUpAll(() => registerFallbackValue(UserAttributes()));

  setUp(() {
    client = MockGoTrueClient();
    when(() => client.onAuthStateChange)
        .thenAnswer((_) => const Stream.empty());
    when(() => client.currentUser).thenReturn(null);
    authState = AuthState(authClient: client);
  });

  Widget wrap() => ChangeNotifierProvider.value(
        value: authState,
        child: const MaterialApp(home: ResetPasswordScreen()),
      );

  void stubUpdate(Future<UserResponse> Function() answer) =>
      when(() => client.updateUser(any())).thenAnswer((_) => answer());

  Future<void> submit(WidgetTester tester, String password, String confirm,
      {bool settle = true}) async {
    await tester.enterText(find.byKey(const Key('password-field')), password);
    await tester.enterText(find.byKey(const Key('confirm-field')), confirm);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Update Password'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('asks for the new password twice, with nowhere to go back to',
      (tester) async {
    await tester.pumpWidget(wrap());

    expect(find.text('CHOOSE A NEW PASSWORD'), findsOneWidget);
    expect(find.byKey(const Key('password-field')), findsOneWidget);
    expect(find.byKey(const Key('confirm-field')), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('rejects a password that is too short', (tester) async {
    await tester.pumpWidget(wrap());

    await submit(tester, 'abc', 'abc');

    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    verifyNever(() => client.updateUser(any()));
  });

  testWidgets('rejects two different passwords', (tester) async {
    await tester.pumpWidget(wrap());

    await submit(tester, 'new-secret', 'new-secreT');

    expect(find.text('Passwords do not match'), findsOneWidget);
    verifyNever(() => client.updateUser(any()));
  });

  testWidgets('saves the new password', (tester) async {
    stubUpdate(() async => FakeUserResponse());
    await tester.pumpWidget(wrap());

    await submit(tester, 'new-secret', 'new-secret');

    final saved = verify(() => client.updateUser(captureAny())).captured.single
        as UserAttributes;
    expect(saved.password, 'new-secret');
  });

  testWidgets("shows Supabase's message when it refuses the password",
      (tester) async {
    stubUpdate(() => Future.error(const AuthApiException(
        'New password should be different from the old password.',
        statusCode: '422')));
    await tester.pumpWidget(wrap());

    await submit(tester, 'old-secret', 'old-secret');

    expect(find.text('New password should be different from the old password.'),
        findsOneWidget);
  });

  testWidgets('says so plainly when the server cannot be reached',
      (tester) async {
    stubUpdate(() => Future.error(AuthRetryableFetchException(
        message: 'ClientException: Failed to fetch, uri=http://x/user')));
    await tester.pumpWidget(wrap());

    await submit(tester, 'new-secret', 'new-secret');

    expect(
        find.text(
            'Could not reach the server. Check your connection and try again.'),
        findsOneWidget);
    expect(find.textContaining('ClientException'), findsNothing);
  });

  testWidgets('shows a spinner and blocks a skip while saving', (tester) async {
    final answer = Completer<UserResponse>();
    stubUpdate(() => answer.future);
    var notified = 0;
    authState.addListener(() => notified++);
    await tester.pumpWidget(wrap());

    await submit(tester, 'new-secret', 'new-secret', settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(find.byType(ElevatedButton).first)
            .onPressed,
        isNull);
    await tester.tap(find.text('Skip for now'));
    await tester.pump();
    expect(notified, 0); // skipping would have ended the recovery

    answer.complete(FakeUserResponse());
    await tester.pumpAndSettle();
    expect(notified, 1); // saving ends it
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('hides the old error while trying again', (tester) async {
    var attempts = 0;
    final second = Completer<UserResponse>();
    stubUpdate(() => ++attempts == 1
        ? Future.error(const AuthException('Password is too common'))
        : second.future);
    await tester.pumpWidget(wrap());
    await submit(tester, 'password', 'password');
    expect(find.text('Password is too common'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Update Password'));
    await tester.pump();

    expect(find.text('Password is too common'), findsNothing);
  });

  testWidgets('can be skipped without saving anything', (tester) async {
    authState = AuthState(authClient: client);
    var notified = 0;
    authState.addListener(() => notified++);
    await tester.pumpWidget(wrap());

    await tester.tap(find.text('Skip for now'));
    await tester.pump();

    expect(notified, 1);
    verifyNever(() => client.updateUser(any()));
  });
}
