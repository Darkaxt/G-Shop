import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:g_shop/features/game_detail/patch_launch_selection.dart';
import 'package:g_shop/features/library/patch_library_screen.dart';
import 'package:g_shop/models/patch_catalogue.dart';
import 'package:g_shop/services/drive/drive_patch_catalogue.dart';
import 'package:g_shop/services/storage_service.dart';

void main() {
  for (final size in [const Size(1920, 1080), const Size(800, 450)]) {
    testWidgets(
        'launch chooser defaults to original and supports remember/cancel at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ({Object? choice, bool remember})? result;
      final ready = <String, dynamic>{'title': 'Original — Translation'};
      final row = PatchGameData(
          null,
          IndexedPatchGame(
              '1', 'Original', PatchRelativePath('GBA/Patches/game.json')),
          const [],
          const {},
          sourceId: 'fixture');
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: Scaffold(
                  body: Builder(
                      builder: (context) => FilledButton(
                          onPressed: () async {
                            result = await showPatchLaunchChoice(context,
                                builds: [ready], candidates: [row]);
                          },
                          child: const Text('Launch')))))));
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      expect(find.text('Play original'), findsOneWidget);
      expect(find.text('Original — Translation'), findsOneWidget);
      expect(find.text('Choose a compatible patch'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Remember my choice for this ROM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remember my choice for this ROM'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Play original'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play original'));
      await tester.pumpAndSettle();
      expect(result, (choice: 'original', remember: true));
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original — Translation'));
      await tester.pumpAndSettle();
      expect(identical(result?.choice, ready), isTrue);
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(result?.choice, isNull);
    });
  }
  test('saved decisions reset only this console and persist across instances',
      () async {
    SharedPreferences.setMockInitialValues({'secure_auth_migrated': true});
    final storage = StorageService();
    await storage.init();
    await storage.setPatchLaunchChoice('gba_content', 'original');
    await storage.setPatchLaunchChoice('nes_content', 'recipe');
    final reopened = StorageService();
    await reopened.init();
    expect(reopened.getPatchLaunchChoice('gba_content'), 'original');
    expect(reopened.getPatchLaunchChoice('gba_changed_content'), isNull);
    await reopened.resetPatchLaunchChoices('gba');
    expect(reopened.getPatchLaunchChoice('gba_content'), isNull);
    expect(reopened.getPatchLaunchChoice('nes_content'), 'recipe');
  });
}
