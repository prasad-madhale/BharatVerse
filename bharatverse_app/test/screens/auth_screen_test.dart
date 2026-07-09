import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:bharatverse_app/screens/auth_screen.dart';
import 'package:bharatverse_app/state/auth_state.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class FakeAuthResponse extends Fake implements AuthResponse {}

Widget _wrapWithProvider(MockGoTrueClient mockAuthClient) {
  return ChangeNotifierProvider(
    create: (_) => AuthState(authClient: mockAuthClient),
    child: const MaterialApp(home: AuthScreen()),
  );
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

    expect(find.widgetWithText(AppBar, 'Sign In'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
  });

  testWidgets('toggles to sign-up mode', (tester) async {
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    await tester.tap(find.text("Don't have an account? Sign Up"));
    await tester.pump();

    expect(find.widgetWithText(AppBar, 'Sign Up'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign Up'), findsOneWidget);
  });

  testWidgets('shows a validation error for an invalid email', (tester) async {
    await tester.pumpWidget(_wrapWithProvider(mockAuthClient));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'password123');
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
        find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'password123');
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
        find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'wrongpassword');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid login credentials'), findsOneWidget);
  });
}
