import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() =>
    integrationDriver(onScreenshot: (name, bytes, [args]) async {
      if (!const {
        'resolved-cover-console',
        'resolved-cover-library',
        'resolved-cover-shelf',
        'resolved-cover-source-indicators',
        'resolved-cover-localized-badges',
        'resolved-cover-transfer-badges',
        'resolved-console-top-10',
        'resolved-console-tags-all',
        'resolved-console-restored-filters',
        'resolved-console-cleared-filters',
        'resolved-library-top-10-scope',
        'resolved-library-manual-shelf',
        'resolved-library-explicit-rating-order',
        'resolved-library-restored-filters',
        'resolved-library-independent-tags-any',
        'resolved-library-independent-tags-all',
        'resolved-library-unrated-top-empty',
        'resolved-library-unrated-browsable',
      }.contains(name)) {
        return false;
      }
      final root = Directory('D:/Temp/rshop-s5-native-20261004');
      await root.create(recursive: true);
      await File('${root.path}/$name.png').writeAsBytes(bytes);
      return true;
    }, responseDataCallback: (data) async {
      final summary = {...?data}..remove('screenshots');
      await writeResponseData(summary,
          testOutputFilename: 'native-resolved-cover-report',
          destinationDirectory: 'D:/Temp/rshop-s5-native-20261004');
    });
