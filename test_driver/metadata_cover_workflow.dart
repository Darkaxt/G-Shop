import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() =>
    integrationDriver(onScreenshot: (name, bytes, [args]) async {
      if (!const {
        'metadata-artwork-console',
        'metadata-artwork-library-top-10-scope',
        'metadata-artwork-library-manual-shelf'
      }.contains(name)) {
        return false;
      }
      final root = Directory('D:/Temp/rshop-artwork-native-20261004');
      await root.create(recursive: true);
      await File('${root.path}/$name.png').writeAsBytes(bytes);
      return true;
    }, responseDataCallback: (data) async {
      final summary = {...?data}..remove('screenshots');
      await writeResponseData(summary,
          testOutputFilename: 'native-artwork-workflow-report',
          destinationDirectory: 'D:/Temp/rshop-artwork-native-20261004');
    });
