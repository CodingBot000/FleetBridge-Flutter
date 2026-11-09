import 'package:integration_test/integration_test.dart';

import '../test/map_retry_test.dart' as map_test;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  map_test.main();
}
