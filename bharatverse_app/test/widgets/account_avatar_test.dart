import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/screens/auth_screen.dart';
import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/settings_state.dart';
import 'package:bharatverse_app/state/theme_mode_state.dart';
import 'package:bharatverse_app/widgets/account_avatar.dart';
import 'package:bharatverse_app/widgets/settings_sheet.dart';

import '../support/like_fixtures.dart';

Future<Widget> _wrap(AuthState authState) async => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authState),
        ChangeNotifierProvider.value(
            value: ThemeModeState(await SharedPreferences.getInstance())),
        ChangeNotifierProvider.value(
            value: SettingsState(await SharedPreferences.getInstance())),
      ],
      child: const MaterialApp(home: Scaffold(body: AccountAvatar())),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('signed out shows a person icon and opens auth on tap',
      (tester) async {
    await tester
        .pumpWidget(await _wrap(AuthState(authClient: stubAuthClient())));

    expect(find.byIcon(Icons.person_outline), findsOneWidget);

    await tester.tap(find.byType(AccountAvatar));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
  });

  testWidgets('signed in shows the email initial and opens Settings on tap',
      (tester) async {
    await tester.pumpWidget(await _wrap(AuthState(
        authClient: stubAuthClient()
          ..signInAs(testUser(email: 'r@example.com')))));

    expect(find.text('R'), findsOneWidget);

    await tester.tap(find.byType(AccountAvatar));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSheet), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
  });
}
