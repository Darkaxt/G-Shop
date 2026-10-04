import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() =>
    integrationDriver(onScreenshot: (name, bytes, [args]) async {
      const names = {
        'console-top-10',
        'console-tags-all',
        'console-restored-filters',
        'console-cleared-filters'
      };
      if (!names.contains(name)) return false;
      final root = Directory('D:/Temp/rshop-s5-native-20261004');
      await root.create(recursive: true);
      await File('${root.path}/$name.png').writeAsBytes(bytes);
      return true;
    }, responseDataCallback: (data) async {
      final summary = {...?data}..remove('screenshots');
      await writeResponseData(summary,
          testOutputFilename: 'native-console-discovery-report',
          destinationDirectory: 'D:/Temp/rshop-s5-native-20261004');
    });
