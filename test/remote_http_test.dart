import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fleetbridge_flutter/vehicle.dart';
import 'package:fleetbridge_flutter/vehicle_api.dart';
import 'package:fleetbridge_flutter/remote_vehicle_store.dart';

void main() {
  test(
    'real HTTP: server state, unknown command, blocking and reconciliation',
    () async {
      final server = await Process.start('python3', [
        '-u',
        'mock_server/server.py',
        '--no-ticks',
        '--port',
        '0',
      ]);
      addTearDown(() async {
        server.kill();
        await server.exitCode;
      });
      final line = await server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      final url = Uri.parse(line.substring('FleetBridge mock: '.length));
      final store = RemoteVehicleStore(
        VehicleApi(
          baseUrl: url,
          client: http.Client(),
          timeout: const Duration(milliseconds: 500),
        ),
      );
      addTearDown(store.dispose);
      await store.refresh();
      expect(store.vehicles.length, 10);
      await store.loadDetail('vehicle-1');
      expect(
        await store.setRefrigeration(
          'vehicle-1',
          true,
          CommandScenario.success,
        ),
        CommandResult.unknown,
      );
      expect(store.isPending('vehicle-1'), isTrue);
      expect(
        await store.setRefrigeration(
          'vehicle-1',
          false,
          CommandScenario.success,
        ),
        CommandResult.busy,
      );
      expect(await store.checkCommand('vehicle-1'), CommandResult.unknown);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(await store.checkCommand('vehicle-1'), CommandResult.success);
      expect(store.isPending('vehicle-1'), isFalse);
      expect(store.vehicle('vehicle-1')!.refrigerationOn, isTrue);
      expect(store.vehicle('vehicle-1')!.revision, 1);
      final before = store.vehicle('vehicle-1');
      server.kill();
      await server.exitCode;
      await store.refresh();
      expect(store.error, isNotNull);
      expect(store.vehicle('vehicle-1'), same(before));
    },
  );
}
