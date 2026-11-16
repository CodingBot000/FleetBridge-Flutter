import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleetbridge_flutter/remote_vehicle_store.dart';
import 'package:fleetbridge_flutter/vehicle_api.dart';

import 'vehicle_api_test.dart' show sample;

import 'package:fleetbridge_flutter/vehicle.dart';

http.Response snapshot(int revision) => http.Response(
  jsonEncode([
    {...sample(), 'revision': revision},
  ]),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test(
    'stop/start starts a new generation; old finally cannot release loading',
    () async {
      final requests = <Completer<http.Response>>[];
      final store = RemoteVehicleStore(
        VehicleApi(
          baseUrl: Uri.parse('http://localhost'),
          client: MockClient((_) {
            final c = Completer<http.Response>();
            requests.add(c);
            return c.future;
          }),
        ),
      );
      addTearDown(store.dispose);
      final old = store.refresh();
      await Future<void>.delayed(Duration.zero);
      store.stop();
      store.start();
      await Future<void>.delayed(Duration.zero);
      expect(requests.length, 2);
      requests[0].complete(snapshot(10));
      await old;
      expect(store.loading, isTrue);
      expect(store.vehicles, isEmpty);
      final current = store.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(requests.length, 2);
      requests[1].complete(snapshot(2));
      await current;
      expect(store.vehicles.single.revision, 2);
      expect(store.loading, isFalse);
    },
  );
  test('old error cannot overwrite a newer completed request', () async {
    final requests = <Completer<http.Response>>[];
    final store = RemoteVehicleStore(
      VehicleApi(
        baseUrl: Uri.parse('http://localhost'),
        client: MockClient((_) {
          final c = Completer<http.Response>();
          requests.add(c);
          return c.future;
        }),
      ),
    );
    addTearDown(store.dispose);
    final old = store.refresh();
    await Future<void>.delayed(Duration.zero);
    store.stop();
    final current = store.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(requests.length, 2);
    requests[1].complete(snapshot(2));
    await current;
    requests[0].complete(http.Response('{}', 503));
    await old;
    expect(store.error, isNull);
    expect(store.vehicles.single.revision, 2);
  });
  test(
    'list failure survives detail success and lower revisions cannot overwrite',
    () async {
      final list = Completer<http.Response>();
      final detail = Completer<http.Response>();
      final store = RemoteVehicleStore(
        VehicleApi(
          baseUrl: Uri.parse('http://localhost'),
          client: MockClient(
            (r) => r.url.path == '/vehicles' ? list.future : detail.future,
          ),
        ),
      );
      addTearDown(store.dispose);
      final a = store.refresh();
      final b = store.loadDetail('vehicle-1');
      list.complete(http.Response('{}', 503));
      await a;
      detail.complete(
        http.Response(
          jsonEncode(sample()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await b;
      expect(store.error, contains('503'));
    },
  );
  test(
    'refresh registration is reentrant-safe and detail operations are isolated',
    () async {
      final requests = <String, List<Completer<http.Response>>>{};
      final store = RemoteVehicleStore(
        VehicleApi(
          baseUrl: Uri.parse('http://localhost'),
          client: MockClient((r) {
            final c = Completer<http.Response>();
            requests.putIfAbsent(r.url.path, () => []).add(c);
            return c.future;
          }),
        ),
      );
      var reentered = false;
      store.addListener(() {
        if (!reentered) {
          reentered = true;
          store.refresh();
        }
      });
      final list = store.refresh();
      final detail = store.loadDetail('vehicle-1');
      expect(identical(detail, store.loadDetail('vehicle-1')), isTrue);
      final other = store.loadDetail('vehicle-2');
      await Future<void>.delayed(Duration.zero);
      expect(requests['/vehicles']!.length, 1);
      expect(requests['/vehicles/vehicle-1']!.length, 1);
      requests['/vehicles/vehicle-2']![0].complete(http.Response('{}', 404));
      await other;
      requests['/vehicles']![0].complete(snapshot(5));
      await list;
      requests['/vehicles/vehicle-1']![0].complete(
        http.Response(
          jsonEncode({...sample(), 'revision': 2}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await detail;
      expect(store.vehicles.single.revision, 5);
      expect(store.error, isNull);
      expect(store.errorFor('vehicle-1'), isNull);
      expect(store.errorFor('vehicle-2'), contains('404'));
      final oldDetail = store.loadDetail('vehicle-1');
      await Future<void>.delayed(Duration.zero);
      store.stop();
      final newDetail = store.loadDetail('vehicle-1');
      await Future<void>.delayed(Duration.zero);
      requests['/vehicles/vehicle-1']![1].complete(http.Response('{}', 503));
      await oldDetail;
      expect(store.loadingFor('vehicle-1'), isTrue);
      requests['/vehicles/vehicle-1']![2].complete(
        http.Response(
          jsonEncode({...sample(), 'revision': 6}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await newDetail;
      expect(store.vehicles.single.revision, 6);
      var notifications = 0;
      store.addListener(() => notifications++);
      final late = store.loadDetail('vehicle-1');
      await Future<void>.delayed(Duration.zero);
      store.dispose();
      final count = notifications;
      requests['/vehicles/vehicle-1']![3].complete(
        http.Response(
          jsonEncode({...sample(), 'revision': 10}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await late;
      expect(store.vehicles.single.revision, 6);
      expect(notifications, count);
    },
  );
  test('command success requests a fresh snapshot instead of joining a pre-command read', () async {
    final lists = <Completer<http.Response>>[];
    final store = RemoteVehicleStore(
      VehicleApi(
        baseUrl: Uri.parse('http://localhost'),
        client: MockClient((r) async {
          if (r.method == 'POST') {
            return http.Response(
              jsonEncode({
                'requestId': 'r1',
                'payload': {
                  'vehicleId': 'vehicle-1',
                  'enabled': true,
                  'scenario': 'success',
                },
                'result': 'success',
              }),
              200,
            );
          }
          final c = Completer<http.Response>();
          lists.add(c);
          return c.future;
        }),
      ),
      requestId: () => 'r1',
    );
    addTearDown(store.dispose);
    final initial = store.refresh();
    await Future<void>.delayed(Duration.zero);
    lists[0].complete(snapshot(0));
    await initial;
    final stale = store.refresh();
    await Future<void>.delayed(Duration.zero);
    final command = store.setRefrigeration(
      'vehicle-1',
      true,
      CommandScenario.success,
    );
    await Future<void>.delayed(Duration.zero);
    expect(lists.length, 3);
    lists[2].complete(
      http.Response(
        jsonEncode([
          {...sample(), 'revision': 1, 'refrigerationOn': true},
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await command;
    lists[1].complete(snapshot(0));
    await stale;
    expect(store.vehicles.single.refrigerationOn, isTrue);
    expect(store.vehicles.single.revision, 1);
  });
  testWidgets('listener stop during start cancels timer before issuing HTTP', (
    tester,
  ) async {
    var calls = 0;
    final store = RemoteVehicleStore(
      VehicleApi(
        baseUrl: Uri.parse('http://localhost'),
        client: MockClient((_) async {
          calls++;
          return snapshot(0);
        }),
      ),
    );
    addTearDown(store.dispose);
    var stopped = false;
    store.addListener(() {
      if (!stopped) {
        stopped = true;
        store.stop();
      }
    });
    store.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect(calls, 0);
    expect(store.loading, isFalse);
  });
}
