import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:fleetbridge_flutter/main.dart';
import 'package:fleetbridge_flutter/vehicle.dart';

import 'map_retry_test.dart' show TestTiles;

class TrackedTiles extends TestTiles {
  TrackedTiles([super.fail = false]);
  bool closed = false;
  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

void main() {
  testWidgets(
    'vehicle refresh reuses the tile client and closing releases it',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clients = <TrackedTiles>[];
      final repo = VehicleRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWith((ref) {
              ref.onDispose(repo.dispose);
              return repo;
            }),
          ],
          child: MaterialApp(
            home: VehicleDetail(
              id: 'vehicle-1',
              tileProviderFactory: () {
                final c = TrackedTiles();
                clients.add(c);
                return c;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester
          .widget<TileLayer>(find.byType(TileLayer))
          .tileProvider;
      repo.advance();
      await tester.pumpAndSettle();
      expect(clients.length, 1);
      expect(
        tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
        same(first),
      );
      await tester.pumpWidget(const SizedBox());
      expect(clients.every((c) => c.closed), isTrue);
    },
  );
  testWidgets(
    'retry disposes failed tile client and route exit disposes the replacement',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clients = <TrackedTiles>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: VehicleDetail(
              id: 'vehicle-1',
              tileProviderFactory: () {
                final c = TrackedTiles(clients.isEmpty);
                clients.add(c);
                return c;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(clients.length, 1);
      expect(clients.first.closed, isFalse);
      expect(find.text('지도 다시 시도'), findsOneWidget);
      await tester.tap(find.text('지도 다시 시도'));
      await tester.pumpAndSettle();
      expect(clients.length, 2);
      expect(clients.first.closed, isTrue);
      expect(clients.last.closed, isFalse);
      expect(find.text('지도 다시 시도'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(clients.every((c) => c.closed), isTrue);
    },
  );
}
