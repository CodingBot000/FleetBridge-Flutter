import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:fleetbridge_flutter/main.dart' as app;
import 'package:fleetbridge_flutter/vehicle.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var converted = false;
  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!Platform.isAndroid) return;
    if (!converted) {
      await binding.convertFlutterSurfaceToImage();
      converted = true;
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await binding.takeScreenshot(name);
  }

  testWidgets('device navigation, commands and isolation', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicle-1')));
    await tester.pumpAndSettle();
    expect(find.text('차량 상세'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await screenshot(tester, 'android-detail');
    await tester.scrollUntilVisible(
      find.text('냉동기 전환'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('냉동기 전환'));
    await tester.pump();
    expect(find.text('처리 중…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('명령 성공'), findsOneWidget);
    expect(find.text('현재: 켜짐'), findsOneWidget);
    await screenshot(tester, 'android-command-success');
    await tester.tap(find.byType(DropdownButton<CommandScenario>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('실패 시나리오').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('냉동기 전환'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('명령 실패'), findsOneWidget);
    await screenshot(tester, 'android-command-failure');
    await tester.tap(find.byType(DropdownButton<CommandScenario>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시간 초과 시나리오').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('냉동기 전환'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('응답 시간 초과'), findsOneWidget);
    await screenshot(tester, 'android-command-timeout');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('차량 목록'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vehicle-3')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('냉동기 전환'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('현재: 꺼짐'), findsOneWidget);
    expect(find.text('응답 시간 초과'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicle-2')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('냉동기 전환'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('현재: 꺼짐'), findsOneWidget);
    expect(find.text('성공 시나리오'), findsOneWidget);
  });
}
