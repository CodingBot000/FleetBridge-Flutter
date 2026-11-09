import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    await File('docs/screenshots/$name.png').writeAsBytes(bytes);
    return true;
  },
);
