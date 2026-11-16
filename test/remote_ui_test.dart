import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleetbridge_flutter/main.dart';
import 'package:fleetbridge_flutter/remote_vehicle_store.dart';
import 'package:fleetbridge_flutter/vehicle_api.dart';

import 'vehicle_api_test.dart' show sample;
import 'remote_command_test.dart' show jsonResponse;

void main() {
  testWidgets(
    'loading, recovery, unknown route reentry and vehicle isolation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initial = Completer<http.Response>();
      var first = true;
      var fail = false;
      var revision = 0;
      final store = RemoteVehicleStore(
        VehicleApi(
          baseUrl: Uri.parse('http://localhost'),
          client: MockClient((r) async {
            if (r.method == 'POST') throw http.ClientException('response lost');
            if (r.url.path.startsWith('/commands/')) {
              return jsonResponse({'error': 'not_found'}, 404);
            }
            if (r.url.path == '/vehicles') {
              if (first) {
                first = false;
                return initial.future;
              }
              if (fail) return jsonResponse({}, 503);
              return jsonResponse([
                {...sample(), 'revision': revision, 'battery': 80},
                {...sample(), 'id': 'vehicle-2'},
                {...sample(), 'id': 'vehicle-3', 'status': 'offline'},
              ]);
            }
            final id = r.url.path.split('/').last;
            return jsonResponse({
              ...sample(),
              'id': id,
              if (id == 'vehicle-3') 'status': 'offline',
            });
          }),
        ),
        requestId: () => 'route-stable',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWith((ref) {
              ref.onDispose(store.dispose);
              store.start();
              return store;
            }),
          ],
          child: const FleetApp(mapEnabled: false),
        ),
      );
      expect(find.text('Remote · 서버 조회 중…'), findsOneWidget);
      initial.complete(
        jsonResponse([
          {...sample()},
          {...sample(), 'id': 'vehicle-2'},
          {...sample(), 'id': 'vehicle-3', 'status': 'offline'},
        ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vehicle-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('냉동기 전환'));
      await tester.pumpAndSettle();
      expect(find.text('결과 확인 필요 — 서버 처리 여부가 불명확합니다.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vehicle-1')));
      await tester.pumpAndSettle();
      expect(find.text('요청 ID: route-stable'), findsOneWidget);
      await tester.tap(find.text('명령 결과 조회'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vehicle-2')));
      await tester.pumpAndSettle();
      expect(find.text('요청 ID: route-stable'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vehicle-3')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      fail = true;
      await store.refresh();
      await tester.pump();
      expect(find.textContaining('503'), findsOneWidget);
      expect(find.byKey(const ValueKey('vehicle-1')), findsOneWidget);
      fail = false;
      revision = 9;
      await store.refresh();
      await tester.pump();
      expect(find.textContaining('503'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('vehicle-1')));
      await tester.pumpAndSettle();
      expect(find.text('배터리 80%'), findsOneWidget);
      expect(store.vehicle('vehicle-1')!.revision, 9);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
