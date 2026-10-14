import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() =>
    integrationDriver(onScreenshot: (name, bytes, [args]) async {
      if (!{
        'normal-cover-gbc_dual_mode',
        'normal-cover-vita',
        'library-top-10-scope'
      }.contains(name)) {
        return false;
      }
      const root = 'D:/Temp/rshop-socket07-integration-20261014';
      await File('$root/captures/$name.png').writeAsBytes(bytes);
      return true;
    }, responseDataCallback: (data) async {
      final summary = {...?data}..remove('screenshots');
      await writeResponseData(summary,
          testOutputFilename: 'native-normal-frontend',
          destinationDirectory: 'D:/Temp/rshop-socket07-integration-20261014');
    });
