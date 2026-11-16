import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Scroll from the list padding, outside the map's pan gesture region.
Future<void> revealDetail(WidgetTester tester, Finder target) async {
  final list = find.byKey(const ValueKey('vehicle-detail-scroll'));
  for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
    final rect = tester.getRect(list);
    await tester.dragFrom(
      rect.bottomRight - const Offset(10, 30),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
  }
  expect(target, findsWidgets);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}
