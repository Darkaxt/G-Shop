import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/core/input/input.dart';
import 'package:retro_eshop/features/library/patch_library_screen.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/patch_catalogue.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/providers/download_providers.dart';
import 'package:retro_eshop/services/drive/drive_patch_catalogue.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/input_debouncer.dart';
import 'package:retro_eshop/services/patch_build_service.dart';
import 'package:retro_eshop/services/patch_build_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../helpers/pump_helpers.dart';

class _ImmediateInput extends InputDebouncer {
  @override
  bool canPerformAction() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  test('patch failure guidance distinguishes offline from changed resources',
      () {
    expect(
        patchCatalogueFailureMessage(const DriveAuthorizationException(
            DriveAuthorizationIssue.unavailable)),
        contains('Check your connection'));
    expect(
        patchCatalogueFailureMessage(
            const DriveTransferException(DriveTransferIssue.sourceChanged)),
        contains('Sync the console'));
    expect(patchCatalogueFailureMessage(StateError('private-path/token')),
        isNot(contains('private-path')));
  });
  const config = ProviderConfig(
      type: ProviderType.drive,
      priority: 1,
      sourceId: 'fixture',
      path: 'folder',
      drive: DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'root',
          serverClientId: 'public-client'));
  final system = SystemModel.supportedSystems.singleWhere((s) => s.id == 'gba');
  final game = IndexedPatchGame(
      'game', 'Advance Wars', PatchRelativePath('GBA/Patches/AW/game.json'));
  final patch = IndexedRomPatch(
      source: 'Synthetic',
      section: 'hacks',
      sourceId: '1',
      title: 'Balance',
      version: '1.0',
      description: 'Balance changes',
      bases: [
        IndexedPatchBase(
            relativePath: PatchRelativePath('GBA/base.gba'),
            sizeBytes: 4,
            checksums: {'sha256': 'a' * 64})
      ],
      payloads: [
        IndexedPatchPayload(
            relativePath: 'GBA/Patches/balance.ips',
            sizeBytes: 14,
            sha256: 'b' * 64,
            format: PatchFormat.ips)
      ],
      unsupportedFiles: []);

  for (final size in [const Size(1920, 1080), const Size(800, 450)]) {
    testWidgets(
        'patch sections use L1 R1 and material controller focus at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db =
          await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      await PatchBuildSchema.install(db);
      final service = PatchBuildService(database: Future.value(db));
      final recipe = PatchRecipe(
          platformId: 'gba',
          base: patch.bases.single,
          steps: [PatchRecipeStep.fromPatch(patch, patch.payloads.single)],
          engineRevision: 'fixture');
      await service.store.begin(
          buildId: 'build',
          recipe: recipe,
          sourceGameId: 'game',
          gameTitle: game.title,
          gameIndexPath: game.indexPath.value,
          providerSourceId: 'fixture',
          title: 'Advance Wars — Balance',
          jobRoot: '/private/fixture',
          targetRoot: '/roms/Hacks',
          filename: 'balance.gba');
      await tester.pumpWidget(ProviderScope(
          overrides: [
            inputDebouncerProvider.overrideWith((_) => _ImmediateInput()),
            hasQueueItemsProvider.overrideWithValue(false),
          ],
          child: GlobalInputWrapper(
              child: createTestApp(PatchGameScreen(
                  system: system,
                  targetFolder: '/roms',
                  service: service,
                  row: PatchGameData(
                      DrivePatchCatalogue(config),
                      game,
                      [patch],
                      {
                        'GBA/base.gba': const GameItem(
                            filename: 'base.gba',
                            displayName: 'Advance Wars',
                            url: '')
                      },
                      sourceId: 'fixture'))))));
      await tester.pumpAndSettle();
      expect(find.text('Balance changes'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
      await tester.pumpAndSettle();
      expect(find.text('Advance Wars — Balance'), findsOneWidget);
      expect(find.text('Balance changes'), findsNothing);
      final info = find.byTooltip('Build details');
      Focus.of(tester
              .element(find.descendant(of: info, matching: find.byType(Icon))))
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Synthetic · 1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
      await tester.pumpAndSettle();
      expect(find.text('Balance changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.close();
    });
  }
}
