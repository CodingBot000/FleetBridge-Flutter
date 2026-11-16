import 'dart:io';

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

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final detail = find.byKey(const ValueKey('vehicle-detail-scroll'));
      if (i % 5 == 4 &&
          finder.evaluate().isEmpty &&
          detail.evaluate().isNotEmpty) {
        final rect = tester.getRect(detail);
        await tester.dragFrom(
          rect.bottomRight - const Offset(20, 30),
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

    await tester.tap(find.byKey(const ValueKey('vehicle-1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('냉동기 전환'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('vehicle-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
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
    await tester.scrollUntilVisible(
      find.text('냉동기 전환'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('vehicle-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.text('명령 결과 조회'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicle-3')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('냉동기 전환'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('vehicle-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicle-1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(FilledButton),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('vehicle-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
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
        rect.bottomRight - const Offset(20, 30),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('명령 결과 조회'));
    await tester.tap(find.text('명령 결과 조회'));
    await tester.pump();
    await waitFor(tester, find.text('명령 성공'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('차량 목록'), findsOneWidget);
  });
}
