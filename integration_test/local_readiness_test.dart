import 'scroll_helpers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fleetbridge_flutter/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('local search and command completion after closing detail', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'vehicle-2');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.byKey(const ValueKey('vehicle-2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vehicle-2')));
    await tester.pumpAndSettle();
    await revealDetail(tester, find.text('냉동기 전환'));
    await tester.tap(find.text('냉동기 전환'));
    await tester.pump();
    expect(find.text('처리 중…'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('vehicle-2')));
    await tester.pumpAndSettle();
    await revealDetail(tester, find.text('냉동기 전환'));
    expect(find.text('현재: 켜짐'), findsOneWidget);
    expect(find.text('명령 성공'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vehicle-1')), findsOneWidget);
  });
}
