import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:bharatverse_app/screens/forgot_password_screen.dart';
import 'package:bharatverse_app/state/auth_state.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

Widget _wrap(MockGoTrueClient client, {String initialEmail = ''}) =>
    ChangeNotifierProvider(
      create: (_) => AuthState(authClient: client),
      child: MaterialApp(
        home: ForgotPasswordScreen(initialEmail: initialEmail),
      ),
    );

void main() {
  late MockGoTrueClient client;

  setUp(() {
    client = MockGoTrueClient();
    when(() => client.onAuthStateChange)
        .thenAnswer((_) => const Stream.empty());
    when(() => client.currentUser).thenReturn(null);
  });

  void stubReset(Future<void> Function() answer) =>
      when(() => client.resetPasswordForEmail(any(),
          redirectTo: any(named: 'redirectTo'))).thenAnswer((_) => answer());

  Future<void> send(WidgetTester tester, String email) async {
    await tester.enterText(find.byKey(const Key('email-field')), email);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Reset Link'));
    await tester.pumpAndSettle();
  }

  Future<void> openFromAnotherPage(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AuthState(authClient: client),
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ForgotPasswordScreen())),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> closeBeforeAnswer(
    WidgetTester tester,
    void Function(Completer<void> answer) finish,
  ) async {
    final answer = Completer<void>();
    stubReset(() => answer.future);
    await openFromAnotherPage(tester);
    await tester.enterText(
        find.byKey(const Key('email-field')), 'me@example.com');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Reset Link'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    finish(answer);
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(tester.takeException(), isNull);
  }

  testWidgets('says what will happen and asks for the email', (tester) async {
    await tester.pumpWidget(_wrap(client));

    expect(find.text('RESET PASSWORD'), findsOneWidget);
    expect(find.textContaining('send you a link'), findsOneWidget);
    expect(find.byKey(const Key('email-field')), findsOneWidget);
  });

  testWidgets('starts with the email already typed on the sign-in screen',
      (tester) async {
    await tester.pumpWidget(_wrap(client, initialEmail: 'me@example.com'));

    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller?.text, 'me@example.com');
  });

  testWidgets('does not ask Supabase to email an invalid address',
      (tester) async {
    await tester.pumpWidget(_wrap(client));

    await send(tester, 'not-an-email');

    expect(find.text('Enter a valid email'), findsOneWidget);
    verifyNever(() => client.resetPasswordForEmail(any(),
        redirectTo: any(named: 'redirectTo')));
  });

  testWidgets('sends the link, then says one is on its way', (tester) async {
    stubReset(() async {});
    await tester.pumpWidget(_wrap(client));

    await send(tester, '  me@example.com ');

    verify(() => client.resetPasswordForEmail('me@example.com',
        redirectTo: any(named: 'redirectTo'))).called(1);
    expect(find.text('CHECK YOUR EMAIL'), findsOneWidget);
    expect(
        find.text('If an account exists for me@example.com, a link to '
            'choose a new password is on its way.'),
        findsOneWidget);
    expect(find.byKey(const Key('email-field')), findsNothing);
  });

  testWidgets('goes back to sign-in from the confirmation', (tester) async {
    stubReset(() async {});
    await openFromAnotherPage(tester);
    await send(tester, 'me@example.com');

    await tester.tap(find.text('Back to Sign In'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsNothing);
  });

  testWidgets("shows Supabase's message when it refuses the request",
      (tester) async {
    stubReset(() => Future.error(const AuthApiException(
        'For security purposes, you can only request this after 45 seconds.',
        statusCode: '429')));
    await tester.pumpWidget(_wrap(client));

    await send(tester, 'me@example.com');

    expect(
        find.text('For security purposes, you can only request this after 45 '
            'seconds.'),
        findsOneWidget);
    expect(find.text('RESET PASSWORD'), findsOneWidget);
    expect(find.text('CHECK YOUR EMAIL'), findsNothing);
  });

  testWidgets('says so plainly when the server cannot be reached',
      (tester) async {
    stubReset(() => Future.error(AuthRetryableFetchException(
        message: 'ClientException: Failed to fetch, uri=http://x/recover')));
    await tester.pumpWidget(_wrap(client));

    await send(tester, 'me@example.com');

    expect(
        find.text(
            'Could not reach the server. Check your connection and try again.'),
        findsOneWidget);
    expect(find.textContaining('ClientException'), findsNothing);
  });

  testWidgets('shows a spinner and blocks a second send while sending',
      (tester) async {
    final answer = Completer<void>();
    stubReset(() => answer.future);
    await tester.pumpWidget(_wrap(client));

    await tester.enterText(
        find.byKey(const Key('email-field')), 'me@example.com');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Reset Link'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);

    answer.complete();
    await tester.pumpAndSettle();
    expect(find.text('CHECK YOUR EMAIL'), findsOneWidget);
  });

  testWidgets('is left alone when the screen closes before a refusal',
      (tester) async {
    await closeBeforeAnswer(tester,
        (answer) => answer.completeError(const AuthException('Too many')));
  });

  testWidgets('is left alone when the screen closes before it succeeds',
      (tester) async {
    await closeBeforeAnswer(tester, (answer) => answer.complete());
  });

  testWidgets('hides the old error while trying again', (tester) async {
    var attempts = 0;
    final second = Completer<void>();
    stubReset(() => ++attempts == 1
        ? Future.error(const AuthException('Too many requests'))
        : second.future);
    await tester.pumpWidget(_wrap(client));
    await send(tester, 'me@example.com');
    expect(find.text('Too many requests'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Reset Link'));
    await tester.pump();

    expect(find.text('Too many requests'), findsNothing);
  });
}
