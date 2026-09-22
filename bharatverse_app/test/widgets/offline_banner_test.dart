import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bharatverse_app/widgets/offline_banner.dart';

void main() {
  testWidgets('appears while offline and goes away when back online',
      (tester) async {
    final offline = ValueNotifier<bool>(false);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: OfflineBanner(offline: offline))),
    );
    expect(find.text('OFFLINE · SHOWING SAVED ARTICLES'), findsNothing);

    offline.value = true;
    await tester.pump();
    expect(find.text('OFFLINE · SHOWING SAVED ARTICLES'), findsOneWidget);

    offline.value = false;
    await tester.pump();
    expect(find.text('OFFLINE · SHOWING SAVED ARTICLES'), findsNothing);
  });
}
