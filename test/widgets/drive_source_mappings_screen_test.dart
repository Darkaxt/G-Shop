import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/sources/drive_source_mappings_screen.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/source.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';
import 'package:retro_eshop/services/config_storage_service.dart';
import 'package:retro_eshop/services/sources_notifier.dart';
import 'package:retro_eshop/services/storage_service.dart';

class _RomPathStorage extends StorageService {
  @override
  String? getRomPath() => '/roms';
}

class _ConfigStorage extends ConfigStorageService {
  AppConfig config;
  int saves = 0;
  _ConfigStorage(this.config);

  @override
  Future<AppConfig?> loadConfig() async => config;

  @override
  Future<File> saveConfig(String json) async {
    config = AppConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    saves++;
    return File('unused-in-memory-config.json');
  }
}

class _Runtime extends DriveRuntime {
  final bool duplicate;
  final int extraFolders;
  final bool includeDsi;
  _Runtime(this.duplicate, {this.extraFolders = 0, this.includeDsi = false});
  @override
  Future<List<DriveFile>> folders(Source source) async => [
        DriveFile(
            id: 'first',
            name: 'SNES',
            mimeType: DriveFile.folderMime,
            parents: ['root-id']),
        if (includeDsi)
          DriveFile(
              id: 'dsi-folder',
              name: 'Nintendo - Nintendo DSi',
              mimeType: DriveFile.folderMime,
              parents: ['root-id']),
        if (duplicate)
          DriveFile(
              id: 'second',
              name: 'Super Famicom',
              mimeType: DriveFile.folderMime,
              parents: ['root-id']),
        for (var i = 0; i < extraFolders; i++)
          DriveFile(
              id: 'tool-$i',
              name: 'Tool folder $i with a deliberately long descriptive name',
              mimeType: DriveFile.folderMime,
              parents: ['root-id']),
      ];
}

void main() {
  testWidgets('folder search does not trigger the application I shortcut',
      (tester) async {
    var shortcutsInvoked = 0;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          bootstrappedConfigProvider.overrideWith((ref) => AppConfig.empty),
        ],
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyI): () =>
                shortcutsInvoked++,
          },
          child: MaterialApp(
              home: DriveSourceMappingsScreen(
            source: const Source(
                id: 'source', name: 'Drive', type: SourceType.drive),
            runtime: _Runtime(false),
          )),
        )));
    await tester.pump();
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    expect(shortcutsInvoked, 0);
  });

  testWidgets('folder options are only built for the opened selector',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          bootstrappedConfigProvider.overrideWith((ref) => AppConfig.empty),
        ],
        child: MaterialApp(
            home: DriveSourceMappingsScreen(
          source:
              const Source(id: 'source', name: 'Drive', type: SourceType.drive),
          runtime: _Runtime(false, extraFolders: 1335),
        ))));
    await tester.pump();
    // Closed console rows must not lay out every folder's text in hidden stacks.
    expect(find.textContaining('Tool folder'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Not mapped').first);
    await tester.pumpAndSettle();
    expect(tester.widgetList<ListTile>(find.byType(ListTile)).length,
        lessThan(20));
    await tester.enterText(find.byType(TextField), 'Tool folder 99 ');
    await tester.pump();
    expect(
        find.text(
            'Tool folder 99 with a deliberately long descriptive name · tool-99'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final duplicate in [false, true]) {
    testWidgets(
        'empty configuration offers consoles, ambiguous alias=$duplicate',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [
            bootstrappedConfigProvider.overrideWith((ref) => AppConfig.empty),
          ],
          child: MaterialApp(
              home: DriveSourceMappingsScreen(
            source: const Source(
                id: 'source', name: 'Drive', type: SourceType.drive),
            runtime: _Runtime(duplicate),
          ))));
      await tester.pump();
      expect(find.text('Nintendo Entertainment System'), findsWidgets);
      expect(find.text('Super Nintendo'), findsWidgets);
      final rows = tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .toList();
      expect(rows.length, greaterThanOrEqualTo(2));
      expect(
          find.descendant(
              of: find.byWidget(rows[0]), matching: find.text('Not mapped')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byWidget(rows[1]), matching: find.text('Not mapped')),
          findsOneWidget);
      expect(find.text('Suggested: SNES'),
          duplicate ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final addDsi in [false, true]) {
    testWidgets('saving preserves explicit mappings; add DSi=$addDsi',
        (tester) async {
      const source = Source(
          id: 'source',
          name: 'Drive',
          type: SourceType.drive,
          drive: DriveSourceConfig(
              accountId: 'account',
              rootFolderId: 'root-id',
              serverClientId: 'client'));
      const otherMapping = SystemSourceMapping(
          sourceId: 'other-source', remotePath: 'other-snes');
      const config = AppConfig(sources: [
        source
      ], systems: [
        SystemConfig(
            id: 'nes',
            name: 'Nintendo Entertainment System',
            targetFolder: '/roms/nes',
            providers: [],
            manualMappings: [
              SystemSourceMapping(
                  sourceId: 'source', remotePath: 'previously-observed-nes')
            ]),
        SystemConfig(
            id: 'snes',
            name: 'Super Nintendo',
            targetFolder: '/roms/snes',
            providers: [],
            manualMappings: [otherMapping]),
      ]);
      final storage = _ConfigStorage(config);
      final notifier = SourcesNotifier(storage);
      await notifier.ready;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            bootstrappedConfigProvider.overrideWith((ref) => storage.config),
            sourcesProvider.overrideWith((ref) => notifier),
            storageServiceProvider.overrideWithValue(_RomPathStorage()),
          ],
          child: MaterialApp(
              home: DriveSourceMappingsScreen(
                  source: source,
                  runtime: _Runtime(false, includeDsi: true)))));
      await tester.pump();
      expect(find.text('Previously mapped · previous…'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(OutlinedButton).at(1),
              matching: find.text('Not mapped')),
          findsOneWidget);
      if (addDsi) {
        await tester.scrollUntilVisible(find.text('Nintendo DSi'), 400);
        final dsiRow = find
            .ancestor(
                of: find.text('Nintendo DSi'), matching: find.byType(Column))
            .first;
        final selector =
            find.descendant(of: dsiRow, matching: find.byType(OutlinedButton));
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(
            ListTile, 'Nintendo - Nintendo DSi · dsi-fold…'));
        await tester.pumpAndSettle();
      }
      final save = find.widgetWithText(FilledButton, 'Save mappings');
      await tester.scrollUntilVisible(save, 500);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Failed to save Drive folder mappings'), findsNothing);
      expect(storage.saves, 1);
      expect(storage.config.systemById('nes')!.manualMappings.single.remotePath,
          'previously-observed-nes');
      final snesMappings = storage.config.systemById('snes')!.manualMappings;
      expect(snesMappings.map((mapping) => mapping.toJson()),
          [otherMapping.toJson()]);
      final dsi = storage.config.systemById('dsi');
      if (addDsi) {
        expect(dsi!.manualMappings.single.remotePath, 'dsi-folder');
      } else {
        expect(dsi, isNull);
      }
      expect(storage.config.sources.single.toJson(), source.toJson());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('folder choice, clear and cancel preserve explicit selections',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          bootstrappedConfigProvider.overrideWith((ref) => AppConfig.empty),
        ],
        child: MaterialApp(
            home: DriveSourceMappingsScreen(
          source:
              const Source(id: 'source', name: 'Drive', type: SourceType.drive),
          runtime: _Runtime(false),
        ))));
    await tester.pump();
    final firstSelector = find.byType(OutlinedButton).first;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'SNES · first'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: firstSelector, matching: find.text('SNES · first')),
        findsOneWidget);
    await tester.tap(firstSelector);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.descendant(of: firstSelector, matching: find.text('SNES · first')),
        findsOneWidget);
    // B restores the triggering Material control; A must reopen that selector
    // without invoking a global game-list action.
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: firstSelector, matching: find.text('SNES · first')),
        findsOneWidget);
    await tester.tap(firstSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Not mapped'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: firstSelector, matching: find.text('Not mapped')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
