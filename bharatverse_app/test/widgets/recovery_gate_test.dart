import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:supabase_flutter/supabase_flutter.dart' as gotrue
    show AuthState;

import 'package:bharatverse_app/screens/reset_password_screen.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/widgets/recovery_gate.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class FakeUserResponse extends Fake implements UserResponse {}

void main() {
  late MockGoTrueClient client;
  late StreamController<gotrue.AuthState> changes;

  setUpAll(() => registerFallbackValue(UserAttributes()));

  setUp(() {
    client = MockGoTrueClient();
    changes = StreamController<gotrue.AuthState>.broadcast();
    addTearDown(changes.close);
    when(() => client.onAuthStateChange).thenAnswer((_) => changes.stream);
    when(() => client.currentUser).thenReturn(null);
  });

  Widget app({Uri? openedWith}) => ChangeNotifierProvider(
        create: (_) => AuthState(authClient: client),
        child: MaterialApp(
          home: RecoveryGate(
            openedWith: openedWith,
            child: const Scaffold(body: Text('the app')),
          ),
        ),
      );

  Future<void> emit(WidgetTester tester, AuthChangeEvent event) async {
    changes.add(gotrue.AuthState(event, null));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the app until a reset link is followed', (tester) async {
    await tester.pumpWidget(app());

    expect(find.text('the app'), findsOneWidget);
    expect(find.byType(ResetPasswordScreen), findsNothing);
  });

  testWidgets('shows the new-password form in its place once one is followed',
      (tester) async {
    await tester.pumpWidget(app());

    await emit(tester, AuthChangeEvent.passwordRecovery);

    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(find.text('the app'), findsNothing);
  });

  testWidgets('goes back to the app when the reader skips it', (tester) async {
    await tester.pumpWidget(app());
    await emit(tester, AuthChangeEvent.passwordRecovery);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(find.text('the app'), findsOneWidget);
    expect(find.byType(ResetPasswordScreen), findsNothing);
  });

  testWidgets('choosing a new password returns to the app and says so',
      (tester) async {
    when(() => client.updateUser(any()))
        .thenAnswer((_) async => FakeUserResponse());
    await tester.pumpWidget(app());
    await emit(tester, AuthChangeEvent.passwordRecovery);

    await tester.enterText(
        find.byKey(const Key('password-field')), 'new-secret');
    await tester.enterText(
        find.byKey(const Key('confirm-field')), 'new-secret');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Update Password'));
    await tester.pumpAndSettle();

    expect(find.text('the app'), findsOneWidget);
    expect(find.text('Password updated'), findsOneWidget);
  });

  group('a link that could not be used', () {
    testWidgets('is explained on the app', (tester) async {
      await tester.pumpWidget(app(
          openedWith: Uri.parse('https://app.example/?error=access_denied')));
      await tester.pump();

      expect(find.text('the app'), findsOneWidget);
      expect(find.textContaining('That reset link could not be used'),
          findsOneWidget);
      expect(find.textContaining('Request a new one from Sign In'),
          findsOneWidget);
    });

    testWidgets('stays up long enough to read', (tester) async {
      await tester.pumpWidget(
          app(openedWith: Uri.parse('https://app.example/?code=abc')));
      await tester.pump();

      // Once it has slid in, 6 s is past the default 4 s, and 1 s more is
      // enough for it to have slid out again.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('That reset link could not be used'),
          findsOneWidget);
    });

    testWidgets('is not mentioned when the page was opened normally',
        (tester) async {
      await tester
          .pumpWidget(app(openedWith: Uri.parse('https://app.example/')));
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('isUnusedAuthLink', () {
    bool unused(String url) => isUnusedAuthLink(Uri.parse(url));

    test('is true for the parameters a link leaves behind', () {
      expect(unused('https://app.example/?code=abc'), isTrue);
      expect(unused('https://app.example/?error=access_denied'), isTrue);
      expect(unused('https://app.example/?error_code=otp_expired'), isTrue);
      expect(unused('https://app.example/?error_description=Expired'), isTrue);
      expect(unused('https://app.example/?error=access_denied&error_code=x'),
          isTrue);
    });

    test('is false for an ordinary address', () {
      expect(unused('https://app.example/'), isFalse);
      expect(unused('https://app.example/#/'), isFalse);
      expect(unused('https://app.example/?page=2'), isFalse);
    });

    test('is false for an address whose query cannot be read', () {
      expect(unused('https://app.example/?a=%FF'), isFalse);
      expect(unused('https://app.example/?a=%FF&code=1'), isFalse);
    });
  });
}
