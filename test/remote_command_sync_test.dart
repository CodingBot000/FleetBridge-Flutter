import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fleetbridge_flutter/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleetbridge_flutter/vehicle.dart';
import 'package:fleetbridge_flutter/remote_vehicle_store.dart';
import 'package:fleetbridge_flutter/vehicle_api.dart';

import 'remote_command_test.dart' show jsonResponse, record;
import 'vehicle_api_test.dart' show sample;

void main() {
  for (final viaLookup in [false, true]) {
    test(
      'confirmed success stays blocked through slow/failed state sync (lookup=$viaLookup)',
      () async {
        final reads = <Completer<http.Response>>[];
        final posts = <Map<String, dynamic>>[];
        final store = RemoteVehicleStore(
          VehicleApi(
            baseUrl: Uri.parse('http://localhost'),
            client: MockClient((r) async {
              if (r.method == 'POST') {
                final payload = jsonDecode(r.body) as Map<String, dynamic>;
                posts.add(payload);
                return jsonResponse({
                  ...record(
                    payload['requestId'] as String,
                    'vehicle-1',
                    viaLookup ? 'pending' : 'success',
                  ),
                  'payload': {
                    'vehicleId': 'vehicle-1',
                    'enabled': payload['enabled'],
                    'scenario': 'success',
                  },
                });
              }
              if (r.url.path.startsWith('/commands/')) {
                return jsonResponse(record('r1', 'vehicle-1', 'success'));
              }
              final c = Completer<http.Response>();
              reads.add(c);
              return c.future;
            }),
          ),
          requestId: () => 'r${posts.length + 1}',
        );
        addTearDown(store.dispose);
        final initial = store.refresh();
        await Future<void>.delayed(Duration.zero);
        reads[0].complete(jsonResponse([sample()]));
        await initial;
        final sent = store.setRefrigeration(
          'vehicle-1',
          true,
          CommandScenario.success,
        );
        late Future<CommandResult> confirmed;
        if (viaLookup) {
          expect(await sent, CommandResult.unknown);
          confirmed = store.checkCommand('vehicle-1');
        } else {
          confirmed = sent;
        }
        await Future<void>.delayed(Duration.zero);
        expect(reads.length, 2);
        expect(store.isPending('vehicle-1'), isTrue);
        expect(
          await store.setRefrigeration(
            'vehicle-1',
            true,
            CommandScenario.success,
          ),
          CommandResult.busy,
        );
        reads[1].complete(jsonResponse({}, 503));
        expect(await confirmed, CommandResult.success);
        expect(store.isPending('vehicle-1'), isTrue);
        expect(posts.length, 1);
        expect(store.vehicle('vehicle-1')!.refrigerationOn, isFalse);
        // Missing and unchanged snapshots cannot certify the new state either.
        for (final snapshot in [
          <Object>[],
          [sample()],
        ]) {
          final retry = store.refresh();
          await Future<void>.delayed(Duration.zero);
          reads.last.complete(jsonResponse(snapshot));
          await retry;
          expect(store.isPending('vehicle-1'), isTrue);
        }
        final retry = store.refresh();
        await Future<void>.delayed(Duration.zero);
        reads.last.complete(
          jsonResponse([
            {...sample(), 'revision': 1, 'refrigerationOn': true},
          ]),
        );
        await retry;
        expect(store.isPending('vehicle-1'), isFalse);
        expect(store.vehicle('vehicle-1')!.refrigerationOn, isTrue);
        final next = store.setRefrigeration(
          'vehicle-1',
          !store.vehicle('vehicle-1')!.refrigerationOn,
          CommandScenario.success,
        );
        await Future<void>.delayed(Duration.zero);
        expect(posts.last['enabled'], isFalse);
        if (!viaLookup) {
          reads.last.complete(
            jsonResponse([
              {...sample(), 'revision': 2, 'refrigerationOn': false},
            ]),
          );
        }
        await next;
      },
    );
  }
  testWidgets(
    'successful command with failed GET keeps toggle disabled until fresh state',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var failure = true;
      var revision = 0;
      var enabled = false;
      final payloads = <Map<String, dynamic>>[];
      final store = RemoteVehicleStore(
        VehicleApi(
          baseUrl: Uri.parse('http://localhost'),
          client: MockClient((r) async {
            if (r.method == 'POST') {
              final p = jsonDecode(r.body) as Map<String, dynamic>;
              payloads.add(p);
              enabled = p['enabled'] as bool;
              revision++;
              return jsonResponse({
                'requestId': p['requestId'],
                'payload': {
                  'vehicleId': p['vehicleId'],
                  'enabled': enabled,
                  'scenario': p['scenario'],
                },
                'result': 'success',
              });
            }
            if (revision > 0 && failure) return jsonResponse({}, 503);
            final v = {
              ...sample(),
              'revision': revision,
              'refrigerationOn': enabled,
            };
            return jsonResponse(r.url.path == '/vehicles' ? [v] : v);
          }),
        ),
      );
      await store.refresh();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWith((ref) {
              ref.onDispose(store.dispose);
              return store;
            }),
          ],
          child: const MaterialApp(
            home: VehicleDetail(id: 'vehicle-1', mapEnabled: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('냉동기 전환'));
      await tester.pumpAndSettle();
      expect(find.text('명령 성공'), findsOneWidget);
      expect(find.text('차량 상태 확인 필요'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(payloads.length, 1);
      failure = false;
      await tester.tap(find.text('차량 상태 다시 조회'));
      await tester.pumpAndSettle();
      expect(find.text('현재: 켜짐'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('냉동기 전환'));
      await tester.pumpAndSettle();
      expect(payloads.last['enabled'], isFalse);
      expect(find.text('현재: 꺼짐'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
