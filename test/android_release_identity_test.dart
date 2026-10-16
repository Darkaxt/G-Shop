import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native preview entrypoint is declared in the root AOT library', () {
    final main = File('lib/main.dart').readAsStringSync();
    final native = File(
            'android/app/src/main/kotlin/com/retro/rshop/PreviewChannel.kt')
        .readAsStringSync();
    expect(native, contains('findAppBundlePath(), "previewMain"'));
    expect(
        RegExp(r"@pragma\('vm:entry-point'\)\s+Future<void> previewMain\(\)")
            .hasMatch(main),
        isTrue,
        reason: 'The native root-library lookup cannot resolve a re-export in AOT');
  });

  test('release keeps R-Shop branding with a separate fork package', () {
    final build = File('android/app/build.gradle.kts').readAsStringSync();
    final defaults = RegExp(r'defaultConfig\s*\{([\s\S]*?)\n    \}')
        .firstMatch(build)!
        .group(1)!;

    expect(defaults, contains('applicationId = "com.darkaxt.rshop"'));
    expect(defaults, contains('manifestPlaceholders["appLabel"] = "R-Shop"'));
    expect(build, isNot(contains('outputFileName')),
        reason: 'Keep the upstream APK naming route, not a fork rename');
    final release = build.substring(build.indexOf('        release {'));
    expect(release, isNot(contains('signingConfigs.getByName("debug")')),
        reason: 'Public packaging must not fall back to development signing');
    expect(build, contains('RSHOP_RELEASE_STORE_FILE'));
    expect(build, contains('check(hasReleaseSigning)'));
    final launcher = File('scripts/build_release.ps1').readAsStringSync();
    expect(launcher, contains('build apk --release --config-only --target-platform'));
    expect(launcher, isNot(contains('build apk --release --config-only --no-pub')));
    expect(launcher, contains('no Gradle request submitted'));
    expect(launcher, contains('invoke_gradle_build_gate.py'));
  });
}
