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

  Widget app() => ChangeNotifierProvider(
        create: (_) => AuthState(authClient: client),
        child: const MaterialApp(
          home: RecoveryGate(child: Scaffold(body: Text('the app'))),
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
}
