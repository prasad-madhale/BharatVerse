import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// Renders the next pumped widget on a screen of [size] logical pixels.
void useScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Renders the next pumped widget on a 1600 x 1000 desktop-sized screen.
void useWideScreen(WidgetTester tester) =>
    useScreenSize(tester, const Size(1600, 1000));
