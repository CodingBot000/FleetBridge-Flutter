// Host-side test orchestration only. No fault-control endpoint in the app/API.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory(
    Platform.environment['FLEET_SCREENSHOT_DIR'] ??
        '/tmp/fleetbridge-readiness/remote',
  );
  await directory.create(recursive: true);
  final apiPort = Platform.environment['FLEET_TEST_API_PORT'] ?? '8082';
  final sdk =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'] ??
      '${Platform.environment['HOME']}/${Platform.isMacOS ? 'Library/Android/sdk' : 'Android/Sdk'}';
  final adb =
      Platform.environment['FLEET_TEST_ADB'] ?? '$sdk/platform-tools/adb';
  final serial =
      Platform.environment['FLEET_TEST_DEVICE'] ??
      (throw ArgumentError(
        'Set FLEET_TEST_DEVICE to the same device as flutter -d',
      ));
  final adbPort = Platform.environment['ANDROID_ADB_SERVER_PORT'] ?? '5037';
  Process? server;
  final lines = <String>[];
  final evidence = <String>[];
  int getCount() => lines.where((l) => l.contains('"GET /vehicles ')).length;
  Future<void> stop() async {
    final p = server;
    server = null;
    if (p != null) {
      p.kill();
      await p.exitCode;
    }
  }

  Future<void> start({bool failure = false}) async {
    if (server != null) throw StateError('API already running');
    final p = await Process.start('python3', [
      '-u',
      'mock_server/server.py',
      '--no-ticks',
      '--port',
      apiPort,
      if (failure) '--read-error',
    ]);
    server = p;
    p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add);
    final ready = await p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));
    if (!ready.contains(':$apiPort')) {
      throw StateError('Wrong API port: $ready');
    }
    evidence.add('API start: ${failure ? "503" : "healthy"}');
  }

  Future<String> shell(List<String> args) async {
    final r = await Process.run(adb, [
      '-P',
      adbPort,
      '-s',
      serial,
      'shell',
      ...args,
    ]).timeout(const Duration(seconds: 15));
    if (r.exitCode != 0) throw StateError('adb failed: ${r.stderr}');
    return '${r.stdout}';
  }

  HttpServer? control;
  Future<void>? backgroundTask;
  Object? backgroundError;
  Future<void> act(String name) async {
    switch (name) {
      case 'readiness-inject503':
        await stop();
        await start(failure: true);
      case 'readiness-stop-api':
        await stop();
        evidence.add('API stopped for connection failure');
      case 'readiness-restore-api':
        await start();
      case 'readiness-background':
        await shell([
          'am',
          'start',
          '-a',
          'android.intent.action.MAIN',
          '-c',
          'android.intent.category.HOME',
        ]);
        await Future<void>.delayed(const Duration(seconds: 1));
        final activity = await shell(['dumpsys', 'activity', 'activities']);
        final foreground = activity
            .split('\n')
            .where((l) => l.contains('topResumedActivity'))
            .join();
        if (foreground.isEmpty ||
            foreground.contains('com.codingbot000.fleetbridge_flutter')) {
          throw StateError('App did not leave foreground: $foreground');
        }
        final before = getCount();
        await Future<void>.delayed(const Duration(seconds: 6));
        final pollingStopped = getCount() == before;
        evidence.add(
          'Background: list requests $before -> ${getCount()} over 6 seconds; $foreground',
        );
        await shell([
          'am',
          'start',
          '-n',
          'com.codingbot000.fleetbridge_flutter/.MainActivity',
        ]);
        for (var i = 0; i < 50 && getCount() == before; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (getCount() <= before) {
          throw StateError('No list refresh after resume');
        }
        evidence.add('Foreground: list refresh resumed');
        if (!pollingStopped) {
          throw StateError('Polling continued in background');
        }
    }
  }

  Future<void> cleanup(Map<String, dynamic>? data) async {
    await backgroundTask;
    await control?.close(force: true);
    control = null;
    await stop();
    await File('${directory.path}/host-evidence.txt')
        .writeAsString([...evidence, ...lines].join('\n'));
  }

  try {
    await start();
    control = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      int.parse(Platform.environment['FLEET_TEST_CONTROL_PORT'] ?? '8083'),
    );
    control!.listen((request) async {
      try {
        final action = request.uri.path.substring(1);
        if (!{
          'readiness-inject503',
          'readiness-stop-api',
          'readiness-restore-api',
          'readiness-background',
          'readiness-background-result',
        }.contains(action)) {
          request.response.statusCode = 404;
        } else if (action == 'readiness-background') {
          if (backgroundTask != null) {
            throw StateError('Background already scheduled');
          }
          // Acknowledge before HOME: Android can close foreground sockets on pause.
          backgroundTask = Future<void>.delayed(const Duration(seconds: 1))
              .then((_) => act(action))
              .catchError((Object e) {
                backgroundError = e;
              });
          request.response.write('scheduled');
        } else if (action == 'readiness-background-result') {
          if (backgroundTask == null) {
            throw StateError('No background operation');
          }
          await backgroundTask;
          if (backgroundError != null) throw StateError('$backgroundError');
          request.response.write('ok');
        } else {
          await act(action);
          request.response.write('ok');
        }
      } catch (e) {
        evidence.add('CONTROL FAILED: $e');
        request.response.statusCode = 500;
        request.response.write('$e');
      } finally {
        await request.response.close();
      }
    });
    await integrationDriver(
      writeResponseOnFailure: true,
      responseDataCallback: cleanup,
      onScreenshot: (name, bytes, [args]) async {
        await File('${directory.path}/$name.png').writeAsBytes(bytes);
        return true;
      },
    );
  } finally {
    await cleanup(null);
  }
}
