import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_eshop/core/input/input.dart';
import 'package:retro_eshop/features/library/patch_library_screen.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/patch_catalogue.dart';
import 'package:retro_eshop/models/portable_patch_recipe.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/providers/download_providers.dart';
import 'package:retro_eshop/services/drive/drive_patch_catalogue.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/input_debouncer.dart';
import 'package:retro_eshop/services/metadata/shared_metadata_store.dart';
import 'package:retro_eshop/services/patch_build_service.dart';
import 'package:retro_eshop/services/patch_build_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../helpers/pump_helpers.dart';

class _ImmediateInput extends InputDebouncer {
  @override
  bool canPerformAction() => true;
}

class _RecipePaths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;
  _RecipePaths(this.root);
  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    FilePickerIO.registerWith();
  });
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
  final incompatible = IndexedRomPatch(
      source: 'Synthetic',
      section: 'hacks',
      sourceId: '2',
      title: 'Other revision',
      version: '2.0',
      description: 'Requires a different original; not a declared patch chain.',
      bases: [
        IndexedPatchBase(
            relativePath: PatchRelativePath('GBA/other.gba'),
            sizeBytes: 4,
            checksums: {'sha256': 'c' * 64})
      ],
      payloads: [
        IndexedPatchPayload(
            relativePath: 'GBA/Patches/other.ips',
            sizeBytes: 14,
            sha256: 'd' * 64,
            format: PatchFormat.ips)
      ],
      unsupportedFiles: []);

  for (final size in [const Size(1920, 1080), const Size(800, 450)]) {
    testWidgets(
        'recipe import/share and missing requirements support touch and controller at $size',
        (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = await Directory.systemTemp.createTemp('rshop-recipe-ui-');
        final db = await databaseFactoryFfiNoIsolate
            .openDatabase(inMemoryDatabasePath);
        await PatchBuildSchema.install(db);
        final shared = await SharedMetadataStore.open(root,
            factory: databaseFactoryFfiNoIsolate);
        final recipe = PortablePatchRecipe(
            recipe: PatchRecipe(
                platformId: 'gba',
                base: patch.bases.single,
                steps: [
                  PatchRecipeStep.fromPatch(patch, patch.payloads.single)
                ],
                engineRevision: 'fixture'),
            sourceGameId: game.sourceGameId,
            gameTitle: game.title,
            gameIndexPath: game.indexPath,
            title: 'Advance Wars — Balance');
        final input = File('${root.path}/input.json');
        await input.writeAsString(recipe.encode());
        final oldPicker = FilePicker.platform,
            oldPaths = PathProviderPlatform.instance;
        FilePickerIO.registerWith();
        PathProviderPlatform.instance = _RecipePaths(root.path);
        const picker = MethodChannel(
            'miguelruivo.flutter.plugins.filepicker', JSONMethodCodec());
        const share = MethodChannel('dev.fluttercommunity.plus/share');
        const engine = MethodChannel('patch-recipe-ui-engine');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        String? exported, transient;
        messenger.setMockMethodCallHandler(
            picker,
            (call) async => [
                  {
                    'path': input.path,
                    'name': 'input.json',
                    'size': recipe.encode().length
                  }
                ]);
        messenger.setMockMethodCallHandler(engine, (_) async => 'fixture');
        messenger.setMockMethodCallHandler(share, (call) async {
          expect(call.method, 'shareFiles');
          transient =
              ((call.arguments as Map)['paths'] as List).single as String;
          exported = await File(transient!).readAsString();
          return 'dev.fluttercommunity.plus/share/unavailable';
        });
        addTearDown(() async {
          messenger.setMockMethodCallHandler(picker, null);
          messenger.setMockMethodCallHandler(engine, null);
          messenger.setMockMethodCallHandler(share, null);
          FilePicker.platform = oldPicker;
          PathProviderPlatform.instance = oldPaths;
          await shared.close();
          await db.close();
        });
        final service = PatchBuildService(
            database: Future.value(db),
            native: engine,
            sharedStore: Future.value(shared));
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
                    row: PatchGameData(null, game, const [], const {},
                        sourceId: 'portable', portableOnly: true))))));
        await tester.pumpAndSettle();
        // Await the rendered callback through its real picker/SQLite completion.
        // pumpAndSettle observes frames, not filesystem operation completion.
        await (tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Import recipe'))
            .onPressed as dynamic)();
        await tester.pumpAndSettle();
        expect(find.text('Saved recipe · Not installed'), findsOneWidget);
        expect(await db.query('patch_builds'), isEmpty);
        final shareButton = find.byTooltip('Share recipe');
        Focus.of(tester.element(
                find.descendant(of: shareButton, matching: find.byType(Icon))))
            .requestFocus();
        await tester.pump();
        await (tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Share recipe'))
            .onPressed as dynamic)();
        await tester.pumpAndSettle();
        expect(
            PortablePatchRecipe.decode(exported!).recipe.id, recipe.recipe.id);
        expect(await File(transient!).exists(), isFalse);
        expect(await input.exists(), isTrue);
        final check = find.byTooltip('Check requirements');
        Focus.of(tester.element(
                find.descendant(of: check, matching: find.byType(Icon))))
            .requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
        // Checking owns an active progress indicator beneath its dialog. Wait
        // for that named UI state, not global animation idleness.
        while (find.text('Recipe requirements').evaluate().isEmpty) {
          await tester.pump();
        }
        while (primaryFocus?.context
                ?.findAncestorWidgetOfExactType<AlertDialog>() ==
            null) {
          await tester.pump();
        }
        expect(find.text('Recipe requirements'), findsOneWidget);
        expect(find.text('Configured original game'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Build'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
        await tester.pumpAndSettle();
        expect(find.text('No patches listed.'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
        await tester.pumpAndSettle();
        expect(find.text('Saved recipe · Not installed'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    });
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
                      [patch, incompatible],
                      {
                        'GBA/base.gba': const GameItem(
                            filename: 'base.gba',
                            displayName: 'Advance Wars',
                            url: '')
                      },
                      sourceId: 'fixture'))))));
      await tester.pumpAndSettle();
      expect(find.text('Balance changes'), findsOneWidget);
      // Existing indexes declare original bases, not compatible chain edges.
      // Selecting another patch replaces selection; it cannot stack silently.
      await tester.tap(find.widgetWithText(ListTile, 'Other revision'));
      await tester.pumpAndSettle();
      expect(find.text('Balance changes'), findsNothing);
      expect(find.text('The required original game is not in this collection.'),
          findsOneWidget);
      expect(
          tester
              .widgetList<ListTile>(find.byType(ListTile))
              .where((tile) => tile.selected),
          hasLength(1));
      await tester.tap(find.widgetWithText(ListTile, 'Balance'));
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
