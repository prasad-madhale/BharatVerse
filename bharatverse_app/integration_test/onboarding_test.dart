import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bharatverse_app/main.dart' as app;
import 'package:bharatverse_app/screens/auth_screen.dart';
import 'package:bharatverse_app/widgets/app_button.dart';

/// The real app on a device or emulator: a first launch walks every onboarding
/// slide with the device's own system bars, none of which may cover Skip or the
/// button (#30).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding slides stay clear of the system bars',
      (tester) async {
    await (await SharedPreferences.getInstance()).clear();
    await app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, 'Get started'));
    await tester.pumpAndSettle();

    for (final label in ['Continue', 'Continue', 'Get started']) {
      final button = find.widgetWithText(AppButton, label);
      final context = tester.element(button);
      final bars = MediaQuery.paddingOf(context);
      final height = MediaQuery.sizeOf(context).height;
      expect(tester.getRect(button).bottom,
          lessThanOrEqualTo(height - bars.bottom),
          reason: '"$label" is under the navigation bar (${bars.bottom} px)');
      expect(tester.getRect(find.widgetWithText(TextButton, 'Skip')).top,
          greaterThanOrEqualTo(bars.top),
          reason: 'Skip is under the status bar (${bars.top} px)');
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(find.byType(AuthScreen), findsOneWidget);
  });
}
