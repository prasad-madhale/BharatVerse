import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/state/auth_state.dart';
import 'package:bharatverse_app/state/settings_state.dart';
import 'package:bharatverse_app/state/theme_mode_state.dart';
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
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => SettingsSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

// The sheet's content is taller than the default 800x600 test surface, so
// rows near the bottom (appearance, about, sign out) never mount without a
// taller surface -- there's nothing to scroll a fixed-children ListView
// with, since shrinkWrap only affects sizing, not which children build.
Future<void> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the signed-in email and default preferences',
      (tester) async {
    await tester.pumpWidget(await _wrap(AuthState(
        authClient: stubAuthClient()
          ..signInAs(testUser(email: 'r@example.com')))));

    await _open(tester);

    expect(find.text('r@example.com'), findsOneWidget);
    expect(find.text('Daily story'), findsOneWidget);
    expect(find.text('About BharatVerse'), findsOneWidget);
  });

  testWidgets('Done closes the sheet', (tester) async {
    await tester
        .pumpWidget(await _wrap(AuthState(authClient: stubAuthClient())));
    await _open(tester);
    expect(find.byType(SettingsSheet), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsSheet), findsNothing);
  });

  testWidgets('toggling a notification switch updates SettingsState',
      (tester) async {
    await tester
        .pumpWidget(await _wrap(AuthState(authClient: stubAuthClient())));
    final settings =
        tester.element(find.byType(MaterialApp)).read<SettingsState>();
    await _open(tester);

    await tester.tap(find.byWidgetPredicate((w) => w is Switch).first);
    await tester.pumpAndSettle();

    expect(settings.notifDaily, isFalse);
  });

  testWidgets('selecting an appearance option sets ThemeModeState',
      (tester) async {
    await tester
        .pumpWidget(await _wrap(AuthState(authClient: stubAuthClient())));
    final themeModeState =
        tester.element(find.byType(MaterialApp)).read<ThemeModeState>();
    await _open(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(themeModeState.mode, ThemeMode.dark);
  });

  testWidgets('sign out logs out and closes the sheet', (tester) async {
    final authClient = stubAuthClient();
    when(() => authClient.signOut()).thenAnswer((_) async {});
    await tester.pumpWidget(await _wrap(AuthState(authClient: authClient)));
    await _open(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    verify(() => authClient.signOut()).called(1);
    expect(find.byType(SettingsSheet), findsNothing);
  });

  testWidgets('an About/Help row shows a coming-soon snackbar', (tester) async {
    await tester
        .pumpWidget(await _wrap(AuthState(authClient: stubAuthClient())));
    await _open(tester);

    await tester.tap(find.text('About BharatVerse'));
    await tester.pump();

    expect(find.text('Coming soon'), findsOneWidget);
  });
}
