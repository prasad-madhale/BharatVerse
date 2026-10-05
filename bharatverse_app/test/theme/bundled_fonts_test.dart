import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:bharatverse_app/theme/app_typography.dart';

void main() {
  setUpAll(bundleFonts);

  testWidgets('every style loads its font from the bundled assets, offline',
      (tester) async {
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);

    final families = {
      for (final style in [
        AppTypography.display1,
        AppTypography.display2,
        AppTypography.headline,
        AppTypography.bodyLg,
        AppTypography.body,
        AppTypography.ui,
        AppTypography.label,
        AppTypography.caption,
      ])
        style.fontFamily,
    };

    // With fetching off, a variant missing from assets/google_fonts/ fails here.
    await tester.runAsync(GoogleFonts.pendingFonts);
    expect(families, {
      'Newsreader_700',
      'Newsreader_regular',
      'WorkSans_regular',
      'WorkSans_700',
    });
  });

  testWidgets('lists both font licences on the licences page', (tester) async {
    final packages = await tester.runAsync(() async => {
          await for (final entry in LicenseRegistry.licenses) ...entry.packages,
        });

    expect(packages, containsAll(['Newsreader', 'Work Sans']));
  });
}
