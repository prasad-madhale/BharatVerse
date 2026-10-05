import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:bharatverse_app/config.dart';
import 'package:bharatverse_app/services/crash_reports.dart';

void main() {
  test(
      'a build without SENTRY_DSN, like this test, runs the app and reports '
      'nothing', () async {
    var ran = false;

    await runWithCrashReports(() async => ran = true);

    expect(sentryDsn, isEmpty);
    expect(ran, isTrue);
    expect(Sentry.isEnabled, isFalse);
  });

  test('sends crash reports only: no personal data, sessions or screenshots',
      () {
    final options = SentryFlutterOptions();

    configureCrashReports(options, 'https://key@sentry.example/1');

    expect(options.dsn, 'https://key@sentry.example/1');
    expect(options.sendDefaultPii, isFalse);
    expect(options.enableAutoSessionTracking, isFalse);
    expect(options.attachScreenshot, isFalse);
  });
}
