import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver für integration_test/screenshots_test.dart: legt die vom Test
/// aufgenommenen Screenshots unter store/screenshots/ ab.
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/screenshots_test.dart -d <device>
Future<void> main() {
  return integrationDriver(
    onScreenshot: (String name, List<int> bytes,
        [Map<String, Object?>? args]) async {
      final file = File('store/screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
