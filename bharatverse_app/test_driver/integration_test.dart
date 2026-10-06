import 'package:integration_test/integration_test_driver.dart';

/// Host side of `flutter drive` for the tests in integration_test/: reports
/// their results. scripts/e2e.sh runs them this way, against prebuilt APKs.
Future<void> main() => integrationDriver();
