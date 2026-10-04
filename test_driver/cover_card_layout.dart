import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() =>
    integrationDriver(onScreenshot: (name, bytes, [args]) async {
      const names = {
        'cover-source-indicators',
        'cover-localized-badges',
        'cover-transfer-badges',
        'layout-console-top-10',
        'layout-console-tags-all',
        'layout-console-restored-filters',
        'layout-console-cleared-filters',
        'layout-library-top-10-scope',
        'layout-library-manual-shelf',
        'layout-library-explicit-rating-order',
        'layout-library-restored-filters',
        'layout-library-independent-tags-any',
        'layout-library-independent-tags-all',
        'layout-library-unrated-top-empty',
        'layout-library-unrated-browsable',
      };
      if (!names.contains(name)) return false;
      final root = Directory('D:/Temp/rshop-s5-native-20261004');
      await root.create(recursive: true);
      await File('${root.path}/$name.png').writeAsBytes(bytes);
      return true;
    }, responseDataCallback: (data) async {
      final summary = {...?data}..remove('screenshots');
      await writeResponseData(summary,
          testOutputFilename: 'native-cover-card-layout-report',
          destinationDirectory: 'D:/Temp/rshop-s5-native-20261004');
    });
