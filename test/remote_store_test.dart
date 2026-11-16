import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleetbridge_flutter/remote_vehicle_store.dart';
import 'package:fleetbridge_flutter/vehicle.dart';
import 'package:fleetbridge_flutter/vehicle_api.dart';

import 'vehicle_api_test.dart' show sample;

void main() {
  test(
    'unknown delivery is retained across server 404, never resubmitted',
    () async {
      var posts = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          throw http.ClientException('connection lost');
        }
        if (request.url.path.startsWith('/commands/')) {
          return http.Response('{}', 404);
        }
        return http.Response(
          jsonEncode([sample()]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final store = RemoteVehicleStore(
        VehicleApi(baseUrl: Uri.parse('http://localhost'), client: client),
        requestId: () => 'stable',
      );
      addTearDown(store.dispose);
      await store.refresh();
      expect(
        await store.setRefrigeration(
          'vehicle-1',
          true,
          CommandScenario.success,
        ),
        CommandResult.unknown,
      );
      expect(await store.checkCommand('vehicle-1'), CommandResult.unknown);
      expect(store.requestIdFor('vehicle-1'), 'stable');
      expect(
        await store.setRefrigeration(
          'vehicle-1',
          false,
          CommandScenario.success,
        ),
        CommandResult.busy,
      );
      expect(posts, 1);
    },
  );
  test('stale snapshots, failed refresh and disposed responses cannot mutate state', () async {
    var revision = 2;
    var fail = false;
    final late = Completer<http.Response>();
    var delay = false;
    final store = RemoteVehicleStore(
      VehicleApi(
        baseUrl: Uri.parse('http://localhost'),
        client: MockClient((request) async {
          if (delay) return late.future;
          if (fail) return http.Response('{}', 503);
          return http.Response(
            jsonEncode([
              {...sample(), 'revision': revision},
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    await store.refresh();
    revision = 1;
    await store.refresh();
    expect(store.vehicles.single.revision, 2);
    fail = true;
    await store.refresh();
    expect(store.error, contains('503'));
    expect(store.vehicles.single.revision, 2);
    fail = false;
    revision = 3;
    await store.refresh();
    expect(store.error, isNull);
    expect(store.vehicles.single.revision, 3);
    delay = true;
    final response = store.refresh();
    store.dispose();
    late.complete(http.Response('[]', 200));
    await response;
    expect(store.vehicles.single.revision, 3);
  });
  testWidgets('remote polling pauses and discards a background response', (
    tester,
  ) async {
    var calls = 0;
    final response = Completer<http.Response>();
    final store = RemoteVehicleStore(
      VehicleApi(
        baseUrl: Uri.parse('http://localhost'),
        client: MockClient((_) async {
          calls++;
          if (calls == 1) return response.future;
          return http.Response('[]', 200);
        }),
      ),
    );
    store.start();
    await tester.pump();
    expect(calls, 1);
    store.stop();
    response.complete(
      http.Response(
        jsonEncode([sample()]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pump();
    expect(store.vehicles, isEmpty);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 1);
    store.start();
    await tester.pump();
    expect(calls, 2);
    store.dispose();
  });
}
