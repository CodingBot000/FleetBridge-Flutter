import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fleetbridge_flutter/vehicle.dart';
import 'package:fleetbridge_flutter/vehicle_api.dart';
import 'package:fleetbridge_flutter/remote_vehicle_store.dart';

void main() {
  test('real server loss/restart restores reads but cannot resolve a forgotten command', () async {
    final processes = <Process>[];
    addTearDown(() async {
      for (final p in processes) {
        p.kill();
        await p.exitCode;
      }
    });
    Future<(Process, Uri)> start(int port, {bool fail = false}) async {
      final p = await Process.start('python3', [
        '-u',
        'mock_server/server.py',
        '--no-ticks',
        '--port',
        '$port',
        if (fail) '--read-error',
      ]);
      processes.add(p);
      unawaited(p.stderr.drain<void>());
      final line = await p.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10));
      return (p, Uri.parse(line.substring('FleetBridge mock: '.length)));
    }

    final (server, url) = await start(0);
    final store = RemoteVehicleStore(
      VehicleApi(
        baseUrl: url,
        client: http.Client(),
        timeout: const Duration(milliseconds: 500),
      ),
      requestId: () => 'lost-on-restart',
    );
    addTearDown(store.dispose);
    await store.refresh();
    expect(
      await store.setRefrigeration('vehicle-1', true, CommandScenario.timeout),
      CommandResult.unknown,
    );
    expect(await store.checkCommand('vehicle-1'), CommandResult.unknown);
    server.kill();
    await server.exitCode;
    await store.refresh();
    expect(store.error, isNotNull);
    expect(store.vehicles.length, 10);
    final (failing, _) = await start(url.port, fail: true);
    await store.refresh();
    expect(store.error, contains('503'));
    failing.kill();
    await failing.exitCode;
    await start(url.port);
    final client = http.Client();
    addTearDown(client.close);
    final external = VehicleApi(baseUrl: url, client: client);
    expect(
      await external.command(
        'external',
        'vehicle-2',
        true,
        CommandScenario.success,
      ),
      CommandResult.success,
    );
    await store.refresh();
    expect(store.error, isNull);
    expect(store.vehicle('vehicle-2')!.refrigerationOn, isTrue);
    expect(await store.checkCommand('vehicle-1'), CommandResult.unknown);
    expect(store.requestIdFor('vehicle-1'), 'lost-on-restart');
    expect(
      await store.setRefrigeration('vehicle-1', false, CommandScenario.success),
      CommandResult.busy,
    );
  });
}
