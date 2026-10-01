import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Drive native sign-in can discover its required Android packages', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final queries = RegExp(r'<queries\b[^>]*>([\s\S]*?)</queries>')
        .allMatches(manifest)
        .map((match) => match.group(1)!)
        .join('\n');
    final visiblePackages = RegExp(r'<package\s+android:name="([^"]+)"\s*/>')
        .allMatches(queries)
        .map((match) => match.group(1))
        .toSet();

    expect(visiblePackages, contains('com.android.vending'));
    expect(visiblePackages, contains('com.google.android.gms'));
    expect(
      manifest.contains('android.permission.QUERY_ALL_PACKAGES'),
      isFalse,
      reason: 'Sign-in needs explicit visibility, not unrestricted inventory',
    );
  });
}
