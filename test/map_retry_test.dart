import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:fleetbridge_flutter/main.dart';

class TestTiles extends TileProvider {
  TestTiles(this.fail);
  final bool fail;
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(
        fail
            ? Uint8List.fromList([1, 2, 3])
            : base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
              ),
      );
}

void main() {
  testWidgets(
    'tile failure is cleared by retry and stale errors do not return',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var fail = true;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: VehicleDetail(
              id: 'vehicle-1',
              tileProviderFactory: () => TestTiles(fail),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('지도 다시 시도'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('지도 다시 시도'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('지도 다시 시도'), findsNothing);
      expect(find.text('지도를 불러올 수 없습니다. 네트워크 연결을 확인해 주세요.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
