import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/theme/app_colors.dart';
import 'package:bharatverse_app/theme/app_spacing.dart';
import 'package:bharatverse_app/widgets/app_back_bar.dart';
import 'package:bharatverse_app/widgets/auth_form_page.dart';

import '../support/layout_fixtures.dart';

Widget _page({
  bool submitting = false,
  String? error,
  bool showBack = true,
  VoidCallback? onSubmit,
  List<Widget> footer = const [],
}) =>
    MaterialApp(
      home: AuthFormPage(
        title: 'Reset Password',
        formKey: GlobalKey<FormState>(),
        fields: const [Text('first field'), Text('second field')],
        submitLabel: 'Send',
        onSubmit: onSubmit ?? () {},
        submitting: submitting,
        error: error,
        footer: footer,
        showBack: showBack,
      ),
    );

void main() {
  group('AuthFormPage', () {
    testWidgets('shows the title in capitals, the fields and the button',
        (tester) async {
      await tester.pumpWidget(_page());

      expect(find.text('RESET PASSWORD'), findsOneWidget);
      expect(find.text('first field'), findsOneWidget);
      expect(find.text('second field'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Send'), findsOneWidget);
    });

    testWidgets('spaces the fields evenly', (tester) async {
      await tester.pumpWidget(_page());

      final gap = tester.getTopLeft(find.text('second field')).dy -
          tester.getBottomLeft(find.text('first field')).dy;
      expect(gap, AppSpacing.space4);
    });

    testWidgets('submits when the button is tapped', (tester) async {
      var submitted = 0;
      await tester.pumpWidget(_page(onSubmit: () => submitted++));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));

      expect(submitted, 1);
    });

    testWidgets('shows a spinner and ignores taps while submitting',
        (tester) async {
      var submitted = 0;
      await tester
          .pumpWidget(_page(submitting: true, onSubmit: () => submitted++));

      await tester.tap(find.byType(ElevatedButton));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Send'), findsNothing);
      expect(submitted, 0);
    });

    testWidgets('shows an error between the fields and the button',
        (tester) async {
      await tester.pumpWidget(_page(error: 'That did not work'));

      final error = tester.getTopLeft(find.text('That did not work')).dy;
      expect(error,
          greaterThan(tester.getBottomLeft(find.text('second field')).dy));
      expect(
          error, lessThan(tester.getTopLeft(find.byType(ElevatedButton)).dy));
    });

    testWidgets('shows the error in the error colour', (tester) async {
      await tester.pumpWidget(_page(error: 'That did not work'));

      final error = tester.widget<Text>(find.text('That did not work'));
      expect(error.style?.color, AppColors.colorError);
    });

    testWidgets('lists the footer actions under the button', (tester) async {
      await tester
          .pumpWidget(_page(footer: const [Text('Other way'), Text('Skip')]));

      final button = tester.getBottomLeft(find.byType(ElevatedButton)).dy;
      expect(tester.getTopLeft(find.text('Other way')).dy, greaterThan(button));
      expect(tester.getTopLeft(find.text('Skip')).dy,
          greaterThan(tester.getTopLeft(find.text('Other way')).dy));
    });

    testWidgets('centres its content when there is room', (tester) async {
      await tester.pumpWidget(_page(footer: const [Text('Skip')]));

      final top = tester.getTopLeft(find.text('RESET PASSWORD')).dy;
      final bottom = tester.getBottomLeft(find.text('Skip')).dy;
      final bar = tester.getBottomLeft(find.byType(AppBackBar)).dy;
      final room = tester.getBottomLeft(find.byType(Scaffold)).dy;
      expect((top + bottom) / 2, closeTo((bar + room) / 2, 2));
    });

    testWidgets('scrolls to its last action on a short screen', (tester) async {
      useScreenSize(tester, const Size(430, 260));
      await tester
          .pumpWidget(_page(footer: const [Text('Other way'), Text('Skip')]));

      await tester.scrollUntilVisible(find.text('Skip'), 100);

      expect(
          tester.getBottomLeft(find.text('Skip')).dy, lessThanOrEqualTo(260));
    });

    testWidgets('has a back button unless it is the only page', (tester) async {
      await tester.pumpWidget(_page());
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.pumpWidget(_page(showBack: false));
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.byType(AppBackBar), findsOneWidget); // the bar's rules stay
    });
  });

  group('validateEmail', () {
    test('needs an @', () {
      expect(validateEmail('a@b.c'), isNull);
      expect(validateEmail('abc'), 'Enter a valid email');
      expect(validateEmail(''), 'Enter a valid email');
      expect(validateEmail(null), 'Enter a valid email');
    });
  });

  group('validatePassword', () {
    test('needs at least six characters', () {
      expect(validatePassword('abcdef'), isNull);
      expect(
          validatePassword('abcde'), 'Password must be at least 6 characters');
      expect(validatePassword(''), 'Password must be at least 6 characters');
      expect(validatePassword(null), 'Password must be at least 6 characters');
    });
  });
}
