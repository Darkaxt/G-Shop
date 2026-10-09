import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Host wiring regression, not a substitute for the native launch/restore proof.
// Dolphin 2606 finishes MainActivity before EmulationActivity opens the ROM, so
// an intent-owned grant alone has already been revoked at the read boundary.
void main() {
  test('Sega cartridge launch menus name RetroArch rather than Dolphin', () {
    final source = File('lib/features/game_detail/game_detail_screen.dart')
        .readAsStringSync();
    final retroArchMenu = RegExp(
      r"label: const \{([^}]+)\}\.contains\(widget\.system\.id\)\s*\? 'Open in RetroArch'",
    ).firstMatch(source);
    expect(retroArchMenu, isNotNull);
    final consoles = RegExp(r"'([^']+)'")
        .allMatches(retroArchMenu!.group(1)!)
        .map((match) => match.group(1)!)
        .toSet();
    expect(consoles, containsAll(['megadrive', 'mastersystem', 'sg1000']));
    expect(consoles.intersection({'gc', 'wii', 'psp', 'ps2', 'wiiu'}), isEmpty);
  });
  test('read-only local inspection reaches the native storage dispatcher', () {
    final source =
        File('android/app/src/main/kotlin/com/retro/rshop/MainActivity.kt')
            .readAsStringSync();
    expect(source, contains('call.method == "localCopyInspect"'));
  });
  test('Dolphin exact read grant survives its launcher activity finishing', () {
    final source = File(
      'android/app/src/main/kotlin/com/retro/rshop/OwnedStorageService.kt',
    ).readAsStringSync();
    final preflight = source.indexOf('OwnedRomContentProvider.openCommitted');
    final grant = source.indexOf(
      'context.grantUriPermission(app, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)',
    );
    final start = source.indexOf('context.startActivity(intent)');
    expect(grant, greaterThan(preflight));
    expect(grant, lessThan(start));
    expect(source.substring(preflight, grant),
        contains('if (!retroArch && !psp && !ps2 && !wiiu)'));
    expect(source.substring(grant, start),
        isNot(contains('FLAG_GRANT_PREFIX_URI_PERMISSION')));
    expect(source.substring(grant, start),
        isNot(contains('FLAG_GRANT_PERSISTABLE_URI_PERMISSION')));
    expect(source.substring(grant, start),
        isNot(contains('FLAG_GRANT_WRITE_URI_PERMISSION')));
  });
}
