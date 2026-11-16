import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleetbridge_flutter/vehicle_api.dart';
import 'package:fleetbridge_flutter/vehicle.dart';

Map<String, Object> sample() => {
  'id': 'vehicle-1',
  'name': '차량 1',
  'model': 'Fleet Model 1',
  'latitude': 37.553,
  'longitude': 126.963,
  'status': 'driving',
  'battery': 92,
  'revision': 0,
  'updatedAt': '2026-11-16T00:00:00Z',
  'refrigerationOn': false,
};
void main() {
  test('list and detail decode HTTP JSON without local seed data', () async {
    final api = VehicleApi(
      baseUrl: Uri.parse('http://localhost:8080'),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(request.url.path == '/vehicles' ? [sample()] : sample()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final vehicles = await api.list();
    expect(vehicles.length, 1);
    expect(vehicles.single.status, VehicleStatus.driving);
    expect((await api.detail('vehicle-1')).battery, 92);
  });
  test(
    'invalid JSON, invalid model, wrong ID, HTTP errors are surfaced',
    () async {
      for (final body in [
        'bad json',
        '{}',
        jsonEncode({...sample(), 'battery': 101}),
        jsonEncode({...sample(), 'id': 'other'}),
      ]) {
        final api = VehicleApi(
          baseUrl: Uri.parse('http://localhost'),
          client: MockClient(
            (_) async => http.Response(
              body,
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
        await expectLater(api.detail('vehicle-1'), throwsFormatException);
      }
      final api = VehicleApi(
        baseUrl: Uri.parse('http://localhost'),
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      await expectLater(api.list(), throwsA(isA<ApiException>()));
    },
  );
  test('connection failure and request timeout remain errors', () async {
    final failed = VehicleApi(
      baseUrl: Uri.parse('http://localhost'),
      client: MockClient(
        (_) async => throw http.ClientException('unreachable'),
      ),
    );
    await expectLater(failed.list(), throwsA(isA<http.ClientException>()));
    final delayed = VehicleApi(
      baseUrl: Uri.parse('http://localhost'),
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(delayed.list(), throwsA(isA<TimeoutException>()));
  });
}
