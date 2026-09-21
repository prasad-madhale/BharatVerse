import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:bharatverse_app/screens/auth_screen.dart';
import 'package:bharatverse_app/screens/forgot_password_screen.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import '../support/layout_fixtures.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class FakeAuthResponse extends Fake implements AuthResponse {}

Widget _wrapWithProvider(MockGoTrueClient mockAuthClient) {
  return ChangeNotifierProvider(
    create: (_) => AuthState(authClient: mockAuthClient),
    child: const MaterialApp(home: AuthScreen()),
  );
}

Future<void> _submitSignIn(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('email-field')), 'test@example.com');
  await tester.enterText(
      find.byKey(const Key('password-field')), 'password123');
  await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
}

void main() {
  late MockGoTrueClient mockAuthClient;

  setUpAll(() {
    registerFallbackValue(FakeAuthResponse());
  });

  setUp(() {
    mockAuthClient = MockGoTrueClient();
    when(() => mockAuthClient.onAuthStateChange)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockAuthClient.currentUser).thenReturn(null);
  });

  testWidgets('starts in sign-in mode', (tester) async {
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
  });

  testWidgets('toggles to sign-up mode', (tester) async {
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    await tester.tap(find.text("Don't have an account? Sign Up"));
    await tester.pump();

    expect(find.text('SIGN UP'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign Up'), findsOneWidget);
  });

  testWidgets('shows a validation error for an invalid email', (tester) async {
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    await tester.enterText(
        find.byKey(const Key('email-field')), 'not-an-email');
    await tester.enterText(
        find.byKey(const Key('password-field')), 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
    verifyNever(() => mockAuthClient.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ));
  });

  testWidgets('calls login and pops on success', (tester) async {
    when(() => mockAuthClient.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => FakeAuthResponse());

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => _wrapWithProvider(mockAuthClient)),
          ),
          child: const Text('Open'),
        );
      }),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('email-field')), 'test@example.com');
    await tester.enterText(
        find.byKey(const Key('password-field')), 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    verify(() => mockAuthClient.signInWithPassword(
          email: 'test@example.com',
          password: 'password123',
        )).called(1);
    expect(find.byType(AuthScreen), findsNothing);
  });

  testWidgets('shows an error message when login fails', (tester) async {
    when(() => mockAuthClient.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(const AuthException('Invalid login credentials'));

    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    await tester.enterText(
        find.byKey(const Key('email-field')), 'test@example.com');
    await tester.enterText(
        find.byKey(const Key('password-field')), 'wrongpassword');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid login credentials'), findsOneWidget);
  });

  testWidgets('keeps the form to a comfortable width on a wide screen',
      (tester) async {
    useWideScreen(tester);
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    expect(tester.getSize(find.byType(TextFormField).first).width, 420);
  });

  testWidgets('says so plainly when the server cannot be reached',
      (tester) async {
    when(() => mockAuthClient.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(AuthRetryableFetchException(
      message: 'ClientException: Failed to fetch, '
          'uri=http://127.0.0.1:54321/auth/v1/token',
    ));
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    await _submitSignIn(tester);
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Could not reach the server. Check your connection and try again.'),
        findsOneWidget);
    expect(find.textContaining('ClientException'), findsNothing);
  });

  testWidgets('shows a generic message for an unexpected error',
      (tester) async {
    when(() => mockAuthClient.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(StateError('boom'));
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    await _submitSignIn(tester);
    await tester.pumpAndSettle();

    expect(
        find.text('Something went wrong. Please try again.'), findsOneWidget);
  });

  testWidgets('is left alone when the screen closes before the answer',
      (tester) async {
    final answer = Completer<AuthResponse>();
    when(() => mockAuthClient.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) => answer.future);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _wrapWithProvider(mockAuthClient))),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _submitSignIn(tester);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    answer.completeError(const AuthException('Invalid login credentials'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers to reset a forgotten password, keeping the email typed',
      (tester) async {
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));
    await tester.enterText(
        find.byKey(const Key('email-field')), '  me@example.com ');

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller?.text, 'me@example.com');
  });

  testWidgets('has no reset link while signing up', (tester) async {
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    await tester.tap(find.text("Don't have an account? Sign Up"));
    await tester.pump();

    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('cannot open the reset page while signing in', (tester) async {
    when(() => mockAuthClient.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) => Completer<AuthResponse>().future);
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    await _submitSignIn(tester);
    await tester.pump();
    await tester.tap(find.text('Forgot password?'));
    await tester.pump(const Duration(seconds: 1));

    // A route pushed by that tap would still be offstage on its first frame.
    expect(
        find.byType(ForgotPasswordScreen, skipOffstage: false), findsNothing);
  });
}
