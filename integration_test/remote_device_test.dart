import 'scroll_helpers.dart';

import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fleetbridge_flutter/remote_vehicle_store.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fleetbridge_flutter/main.dart' as app;
import 'package:fleetbridge_flutter/vehicle.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var converted = false;
  Future<void> capture(WidgetTester tester, String name) async {
    if (!Platform.isAndroid) return;
    if (!converted) {
      await binding.convertFlutterSurfaceToImage();
      converted = true;
    }
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  Future<void> control(String action) async {
    const base = String.fromEnvironment(
      'FLEET_READINESS_CONTROL_URL',
      defaultValue: 'http://10.0.2.2:8083',
    );
    final response = await http
        .get(Uri.parse('$base/$action'))
        .timeout(const Duration(seconds: 30));
    expect(response.statusCode, 200, reason: response.body);
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final detail = find.byKey(const ValueKey('vehicle-detail-scroll'));
      if (i % 5 == 4 &&
          finder.evaluate().isEmpty &&
          detail.evaluate().isNotEmpty) {
        final rect = tester.getRect(detail);
        await tester.dragFrom(
          rect.bottomRight - const Offset(10, 30),
          const Offset(0, -150),
        );
        await tester.pumpAndSettle();
      }
    }
    if (finder.evaluate().isEmpty) debugDumpApp();
    expect(finder, findsWidgets);
  }

  testWidgets('remote HTTP command flow and uncertain completion', (
    tester,
  ) async {
    app.main();
    await tester.pump();
    await waitFor(tester, find.byKey(const ValueKey('vehicle-1')));
    final store = ProviderScope.containerOf(
      tester.element(find.byType(app.VehicleList)),
      listen: false,
    ).read(app.repositoryProvider) as RemoteVehicleStore;

    const readiness = bool.fromEnvironment('FLEET_READINESS_CONTROL');
    if (readiness) {
      expect(Platform.isAndroid, isTrue);
      await control('readiness-inject503');
      await tester.tap(find.text('서버 새로고침'));
      await tester.pump();
      await waitFor(tester, find.textContaining('503'));
      expect(store.vehicles.length, 10);
      await capture(tester, 'readiness-http503-visible');
      await control('readiness-stop-api');
      await tester.tap(find.text('서버 새로고침'));
      await tester.pump();
      for (
        var i = 0;
        i < 80 &&
            (store.loading ||
                store.error == null ||
                store.error!.contains('503'));
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(store.error, isNotNull);
      expect(store.error, isNot(contains('503')));
      expect(store.vehicles.length, 10);
      await capture(tester, 'readiness-connection-failure-visible');
      await control('readiness-restore-api');
      await tester.tap(find.text('서버 새로고침'));
      await tester.pump();
      await waitFor(tester, find.text('Remote · Mock API'));
      expect(store.error, isNull);
      expect(store.vehicles.length, 10);
      await capture(tester, 'readiness-recovered');
      final resumed = Completer<void>();
      var paused = false;
      final lifecycle = AppLifecycleListener(
        onStateChange: (state) {
          if (state == AppLifecycleState.paused ||
              state == AppLifecycleState.hidden) {
            paused = true;
          }
          if (paused &&
              state == AppLifecycleState.resumed &&
              !resumed.isCompleted) {
            resumed.complete();
          }
        },
      );
      try {
        await control('readiness-background');
        await tester.runAsync(
          () => resumed.future.timeout(const Duration(seconds: 40)),
        );
        await control('readiness-background-result');
      } finally {
        lifecycle.dispose();
      }
      await tester.pumpAndSettle();
      expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
      await capture(tester, 'readiness-background-resumed');
    }
    await tester.tap(find.byKey(const ValueKey('vehicle-1')));
    await tester.pumpAndSettle();
    await revealDetail(tester, find.text('냉동기 전환'));
    await tester.tap(find.text('냉동기 전환'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await waitFor(tester, find.text('명령 성공'));
    await capture(tester, 'v1.1-remote-success');
    await tester.tap(find.byType(DropdownButton<CommandScenario>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('실패 시나리오').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('냉동기 전환'));
    await tester.pump();
    await waitFor(tester, find.text('명령 실패'));
    await tester.tap(find.byType(DropdownButton<CommandScenario>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시간 초과 시나리오').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('냉동기 전환'));
    await tester.pump();
    // Closing the route must keep the repository's unresolved command.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicle-2')));
    await tester.pumpAndSettle();
    await revealDetail(tester, find.text('냉동기 전환'));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.text('명령 결과 조회'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicle-3')));
    await tester.pumpAndSettle();
    await revealDetail(tester, find.text('냉동기 전환'));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicle-1')));
    await tester.pumpAndSettle();
    await revealDetail(tester, find.byType(FilledButton));
    await tester.pump(const Duration(seconds: 3));
    // Start outside the interactive map so the parent list receives the drag.
    await tester.drag(find.byType(FilledButton), const Offset(0, -350));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('명령 결과 조회'));
    await tester.ensureVisible(find.text('결과 확인 필요 — 서버 처리 여부가 불명확합니다.'));
    expect(find.text('결과 확인 필요 — 서버 처리 여부가 불명확합니다.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('명령 결과 조회'));
    await capture(tester, 'v1.1-remote-unknown');
    await tester.pump(const Duration(seconds: 3));
    expect(store.isPending('vehicle-1'), isTrue);
    for (var i = 0; i < 15 && find.text('명령 결과 조회').evaluate().isEmpty; i++) {
      final rect = tester.getRect(
        find.byKey(const ValueKey('vehicle-detail-scroll')),
      );
      await tester.dragFrom(
        rect.bottomRight - const Offset(10, 30),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('명령 결과 조회'));
    await tester.tap(find.text('명령 결과 조회'));
    await tester.pump();
    await waitFor(tester, find.text('명령 성공'));
    expect(store.isPending('vehicle-1'), isFalse);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('차량 목록'), findsOneWidget);
  });
}
