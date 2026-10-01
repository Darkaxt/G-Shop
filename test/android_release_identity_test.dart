import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release keeps R-Shop branding with a separate fork package', () {
    final build = File('android/app/build.gradle.kts').readAsStringSync();
    final defaults = RegExp(r'defaultConfig\s*\{([\s\S]*?)\n    \}')
        .firstMatch(build)!
        .group(1)!;

    expect(defaults, contains('applicationId = "com.darkaxt.rshop"'));
    expect(defaults, contains('manifestPlaceholders["appLabel"] = "R-Shop"'));
    expect(build, isNot(contains('outputFileName')),
        reason: 'Keep the upstream APK naming route, not a fork rename');
  });
}
