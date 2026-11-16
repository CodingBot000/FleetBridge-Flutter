import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleetbridge_flutter/vehicle.dart';
import 'package:fleetbridge_flutter/vehicle_api.dart';
import 'package:fleetbridge_flutter/remote_vehicle_store.dart';

import 'vehicle_api_test.dart' show sample;

http.Response jsonResponse(Object? data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object> record(String id, String vehicle, String result) => {
  'requestId': id,
  'payload': {'vehicleId': vehicle, 'enabled': true, 'scenario': 'success'},
  'result': result,
};
void main() {
  final cases = <(int, Object?, CommandResult)>[
    (400, {'error': 'invalid_command'}, CommandResult.failure),
    (409, {'error': 'vehicle_busy'}, CommandResult.failure),
    (409, {'error': 'request_id_conflict'}, CommandResult.failure),
    (422, {'error': 'unavailable_vehicle'}, CommandResult.failure),
    (404, {'error': 'not_found'}, CommandResult.unknown),
    (503, {'error': 'injected_error'}, CommandResult.unknown),
    (400, {'error': 'unexpected'}, CommandResult.unknown),
    (409, null, CommandResult.unknown),
    (200, record('wrong-id', 'vehicle-1', 'success'), CommandResult.unknown),
    (200, record('r1', 'vehicle-2', 'success'), CommandResult.unknown),
    (
      200,
      {
        ...record('r1', 'vehicle-1', 'success'),
        'payload': {
          'vehicleId': 'vehicle-1',
          'enabled': false,
          'scenario': 'success',
        },
      },
      CommandResult.unknown,
    ),
    (
      200,
      {
        ...record('r1', 'vehicle-1', 'success'),
        'payload': {
          'vehicleId': 'vehicle-1',
          'enabled': true,
          'scenario': 'failure',
        },
      },
      CommandResult.unknown,
    ),
    (200, record('r1', 'vehicle-1', 'invalid'), CommandResult.unknown),
  ];
  for (var i = 0; i < cases.length; i++) {
    test(
      'POST admission/response case $i preserves uncertainty unless rejection is explicit',
      () async {
        final (status, body, expected) = cases[i];
        var posts = 0;
        final store = RemoteVehicleStore(
          VehicleApi(
            baseUrl: Uri.parse('http://localhost'),
            client: MockClient((r) async {
              if (r.method == 'POST') {
                posts++;
                return jsonResponse(body, status);
              }
              return jsonResponse([sample()]);
            }),
          ),
          requestId: () => 'r1',
        );
        addTearDown(store.dispose);
        await store.refresh();
        expect(
          await store.setRefrigeration(
            'vehicle-1',
            true,
            CommandScenario.success,
          ),
          expected,
        );
        expect(store.isPending('vehicle-1'), expected == CommandResult.unknown);
        expect(posts, 1);
      },
    );
  }
  for (final terminal in ['success', 'failure']) {
    test(
      'pending, repeated lookup, $terminal, multiple vehicles and disposal',
      () async {
        final posts = <String, Completer<http.Response>>{};
        final queries = <Completer<http.Response>>[];
        var seq = 0;
        var lists = 0;
        final store = RemoteVehicleStore(
          VehicleApi(
            baseUrl: Uri.parse('http://localhost'),
            client: MockClient((r) async {
              if (r.method == 'POST') {
                final id = (jsonDecode(r.body) as Map)['vehicleId'] as String;
                final c = Completer<http.Response>();
                posts[id] = c;
                return c.future;
              }
              if (r.url.path.startsWith('/commands/')) {
                final c = Completer<http.Response>();
                queries.add(c);
                return c.future;
              }
              final committed = lists++ > 0 && terminal == 'success';
              return jsonResponse([
                {
                  ...sample(),
                  'revision': committed ? 1 : 0,
                  'refrigerationOn': committed,
                },
                {...sample(), 'id': 'vehicle-2'},
              ]);
            }),
          ),
          requestId: () => 'r${++seq}',
        );
        await store.refresh();
        final a = store.setRefrigeration(
          'vehicle-1',
          true,
          CommandScenario.success,
        );
        final b = store.setRefrigeration(
          'vehicle-2',
          true,
          CommandScenario.success,
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          await store.setRefrigeration(
            'vehicle-1',
            true,
            CommandScenario.success,
          ),
          CommandResult.busy,
        );
        posts['vehicle-1']!.completeError(
          http.ClientException('response lost'),
        );
        await a;
        final first = store.checkCommand('vehicle-1');
        expect(await store.checkCommand('vehicle-1'), CommandResult.busy);
        await Future<void>.delayed(Duration.zero);
        queries[0].complete(jsonResponse(record('r1', 'vehicle-1', 'pending')));
        expect(await first, CommandResult.unknown);
        expect(store.isPending('vehicle-2'), isTrue);
        final second = store.checkCommand('vehicle-1');
        await Future<void>.delayed(Duration.zero);
        queries[1].complete(jsonResponse(record('r1', 'vehicle-1', terminal)));
        expect(
          await second,
          terminal == 'success' ? CommandResult.success : CommandResult.failure,
        );
        expect(store.isPending('vehicle-1'), isFalse);
        expect(await store.checkCommand('vehicle-1'), CommandResult.busy);
        var notifications = 0;
        store.addListener(() => notifications++);
        store.dispose();
        final count = notifications;
        posts['vehicle-2']!.complete(
          jsonResponse(record('r2', 'vehicle-2', 'success')),
        );
        await b;
        expect(notifications, count);
        expect(store.results.containsKey('vehicle-2'), isFalse);
      },
    );
  }
  test(
    'malformed POST JSON and malformed or lost lookup never unlock',
    () async {
      var lookup = 0;
      final store = RemoteVehicleStore(
        VehicleApi(
          baseUrl: Uri.parse('http://localhost'),
          client: MockClient((r) async {
            if (r.method == 'POST') return http.Response('{', 200);
            if (r.url.path.startsWith('/commands/')) {
              lookup++;
              return switch (lookup) {
                1 => jsonResponse(record('other', 'vehicle-1', 'success')),
                2 => jsonResponse(record('r1', 'vehicle-2', 'failure')),
                3 => http.Response('{', 200),
                _ => http.Response('{}', 404),
              };
            }
            return jsonResponse([sample()]);
          }),
        ),
        requestId: () => 'r1',
      );
      addTearDown(store.dispose);
      await store.refresh();
      await store.setRefrigeration('vehicle-1', true, CommandScenario.success);
      for (var i = 0; i < 4; i++) {
        expect(await store.checkCommand('vehicle-1'), CommandResult.unknown);
        expect(store.isPending('vehicle-1'), isTrue);
      }
    },
  );
  for (final status in [400, 404, 409, 422, 503]) {
    test('lookup HTTP $status leaves request unresolved', () async {
      final store = RemoteVehicleStore(
        VehicleApi(
          baseUrl: Uri.parse('http://localhost'),
          client: MockClient((r) async {
            if (r.method == 'POST') {
              return jsonResponse(record('r1', 'vehicle-1', 'pending'));
            }
            if (r.url.path.startsWith('/commands/')) {
              return jsonResponse({'error': 'unavailable_vehicle'}, status);
            }
            return jsonResponse([sample()]);
          }),
        ),
        requestId: () => 'r1',
      );
      addTearDown(store.dispose);
      await store.refresh();
      await store.setRefrigeration('vehicle-1', true, CommandScenario.success);
      expect(await store.checkCommand('vehicle-1'), CommandResult.unknown);
      expect(store.isPending('vehicle-1'), isTrue);
    });
  }
}
