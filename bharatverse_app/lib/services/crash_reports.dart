import 'package:sentry_flutter/sentry_flutter.dart';

import '../config.dart';

/// Runs [app], reporting its crashes to Sentry when [dsn] is set (a build made
/// with `--dart-define=SENTRY_DSN=...`); otherwise just runs it. The release is
/// named `<application id>@<version>+<build number>`.
Future<void> runWithCrashReports(
  Future<void> Function() app, {
  String dsn = sentryDsn,
}) async {
  if (dsn.isEmpty) return app();
  await SentryFlutter.init(
    (options) => configureCrashReports(options, dsn),
    appRunner: app,
  );
}

/// Crash reports and nothing else: no personal data, and no session counts,
/// which would be usage analytics.
void configureCrashReports(SentryFlutterOptions options, String dsn) {
  options
    ..dsn = dsn
    ..sendDefaultPii = false
    ..enableAutoSessionTracking = false;
}
