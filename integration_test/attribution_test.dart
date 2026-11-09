import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fleetbridge_flutter/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('open attribution in external browser', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vehicle-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenStreetMap contributors'));
    await tester.pump();
    // Allow an external observer to inspect the foreground activity and URL.
    // ignore: avoid_print
    print('ATTRIBUTION_LAUNCHED');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 20)),
    );
  });
}
