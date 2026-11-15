import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Runs integration tests and saves their screenshots on the host:
///   SHOT_DIR=build/screenshots flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/features_test.dart
Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final dir = Platform.environment['SHOT_DIR'] ?? 'build/screenshots';
        final file = File('$dir/$name.png');
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);
        return true;
      },
    );
