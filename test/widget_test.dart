import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fleetbridge_flutter/main.dart';
import 'package:fleetbridge_flutter/vehicle.dart';

void main() {
  test('initial vehicles, lookup and simulation parity', () {
    final now = DateTime(2026);
    final repo = VehicleRepository(clock: () => now);
    addTearDown(repo.dispose);
    expect(repo.vehicles.length, 10);
    expect(repo.vehicles.map((v) => v.id).toSet().length, 10);
    for (var i = 0; i < 10; i++) {
      final v = repo.vehicles[i];
      final n = i + 1;
      expect(v.id, 'vehicle-$n');
      expect(v.name, '차량 $n');
      expect(v.model, 'Fleet Model $n');
      expect(v.latitude, closeTo(37.55 + n * .003, 1e-10));
      expect(v.longitude, closeTo(126.96 + n * .003, 1e-10));
      expect(v.status, VehicleStatus.values[i % 3]);
      expect(v.battery, 95 - n * 3);
      expect(v.revision, 0);
      expect(v.updatedAt, now);
      expect(v.refrigerationOn, isFalse);
    }
    expect(repo.vehicle('missing'), isNull);
    final before = repo.vehicle('vehicle-1')!;
    final offline = repo.vehicle('vehicle-3')!;
    repo.advance();
    expect(repo.vehicle('vehicle-1')!.latitude, greaterThan(before.latitude));
    expect(
      repo.vehicle('vehicle-1')!.longitude,
      closeTo(before.longitude + .0001, 1e-10),
    );
    expect(repo.vehicle('vehicle-2')!.latitude, closeTo(37.556, 1e-10));
    expect(repo.vehicle('vehicle-3'), same(offline));
    for (var i = 0; i < 5; i++) {
      repo.advance();
    }
    expect(repo.vehicle('vehicle-1')!.status, VehicleStatus.idle);
    for (var i = 0; i < 6; i++) {
      repo.advance();
    }
    expect(repo.vehicle('vehicle-1')!.battery, before.battery - 1);
  });
  test('rejects duplicate and reversed revisions', () {
    final repo = VehicleRepository();
    addTearDown(repo.dispose);
    final v = repo.vehicle('vehicle-1')!;
    expect(repo.apply(v.copyWith(revision: 2)), isTrue);
    expect(repo.apply(v.copyWith(revision: 2)), isFalse);
    expect(repo.apply(v.copyWith(revision: 1)), isFalse);
  });
  test('command outcomes, duplicate and offline', () async {
    final pending = <Completer<void>>[];
    final repo = VehicleRepository(
      delay: (_) {
        final c = Completer<void>();
        pending.add(c);
        return c.future;
      },
    );
    addTearDown(repo.dispose);
    final first = repo.setRefrigeration(
      'vehicle-1',
      true,
      CommandScenario.success,
    );
    expect(
      await repo.setRefrigeration('vehicle-1', true, CommandScenario.success),
      CommandResult.busy,
    );
    expect(
      await repo.setRefrigeration('vehicle-3', true, CommandScenario.success),
      CommandResult.failure,
    );
    pending.removeAt(0).complete();
    expect(await first, CommandResult.success);
    expect(repo.vehicle('vehicle-1')!.refrigerationOn, isTrue);
    for (final scenario in [CommandScenario.failure, CommandScenario.timeout]) {
      final command = repo.setRefrigeration('vehicle-1', false, scenario);
      pending.removeAt(0).complete();
      expect(
        await command,
        scenario == CommandScenario.failure
            ? CommandResult.failure
            : CommandResult.timeout,
      );
    }
  });
  testWidgets(
    'list search, detail, delayed response after closing and lifecycle',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final completion = Completer<void>();
      final repo = VehicleRepository(delay: (_) => completion.future);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWith((ref) {
              ref.onDispose(repo.dispose);
              repo.start();
              return repo;
            }),
          ],
          child: const FleetApp(mapEnabled: false),
        ),
      );
      await tester.enterText(find.byType(TextField), 'vehicle-1');
      await tester.pump();
      expect(find.byKey(const ValueKey('vehicle-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vehicle-1')));
      await tester.pumpAndSettle();
      expect(find.text('차량 상세'), findsOneWidget);
      await tester.ensureVisible(find.text('냉동기 전환'));
      await tester.tap(find.text('냉동기 전환'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      completion.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(repo.isRunning, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(repo.isRunning, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
