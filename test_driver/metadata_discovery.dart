import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() =>
    integrationDriver(onScreenshot: (name, bytes, [args]) async {
      const names = {
        'library-top-10-scope',
        'library-manual-shelf',
        'library-explicit-rating-order',
        'library-restored-filters',
        'library-independent-tags-any',
        'library-independent-tags-all',
        'library-unrated-top-empty',
        'library-unrated-browsable',
      };
      if (!names.contains(name)) return false;
      final root = Directory('D:/Temp/rshop-s5-native-20261004');
      await root.create(recursive: true);
      await File('${root.path}/$name.png').writeAsBytes(bytes);
      return true;
    }, responseDataCallback: (data) async {
      final summary = {...?data}..remove('screenshots');
      await writeResponseData(summary,
          testOutputFilename: 'native-library-discovery-report',
          destinationDirectory: 'D:/Temp/rshop-s5-native-20261004');
    });
