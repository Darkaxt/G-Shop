import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:retro_eshop/services/saves/emulator_family_settings.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/features/settings/save_backup_settings_screen.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/source.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/models/save_root_configuration.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/config_storage_service.dart';
import 'package:retro_eshop/services/sources_notifier.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/saves/drive_save_backup_area.dart';
import 'package:retro_eshop/services/saves/save_backup_setup.dart';
import 'package:retro_eshop/services/saves/save_capture.dart';
import 'package:retro_eshop/models/emulator_family_registry.dart';

import '../helpers/pump_helpers.dart';

class _Driver implements DriveAuthorizationDriver {
  final started = Completer<void>();
  final consent = Completer<String?>();
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive}) async {
    if (interactive) {
      if (!started.isCompleted) started.complete();
      return consent.future;
    }
    return 'token';
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) async {}
  @override
  Future<void> signOut({required bool revoke}) async {}
}

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<Uint8List>? data,
      Future<void>? cancelFuture) async {
    requests.add(request);
    return ResponseBody.fromString(
        jsonEncode({
          'files': [
            {
              'id': 'area',
              'mimeType': 'application/vnd.google-apps.folder',
              'ownedByMe': true,
              'isAppAuthorized': true,
              'trashed': false,
              'shared': false,
              'appProperties': {'rshopSaveBackup': '1', 'kind': 'area'}
            }
          ],
          'incompleteSearch': false
        }),
        200);
  }

  @override
  void close({bool force = false}) {}
}

class _ConfigStorage extends ConfigStorageService {
  @override
  Future<AppConfig?> loadConfig() async => AppConfig.empty;
}

class _Sources extends SourcesNotifier {
  _Sources() : super(_ConfigStorage());
  void publish(String? account) {
    state = SourcesState(sources: [
      if (account != null)
        Source(
            id: 'same-source',
            name: 'Drive',
            type: SourceType.drive,
            drive: DriveSourceConfig(
                accountId: account,
                rootFolderId: 'root-id',
                serverClientId: 'settings-test-client')),
    ]);
  }
}

class _FamilyBundle extends CachingAssetBundle {
  final String contents;
  _FamilyBundle(this.contents);
  @override
  Future<String> loadString(String key, {bool cache = true}) async => contents;
  @override
  Future<ByteData> load(String key) async => throw UnimplementedError();
}

void main() {
  late EmulatorFamilySettings settings;
  late String defaults;
  setUpAll(() async {
    defaults = await rootBundle.loadString(EmulatorFamilyRegistry.assetPath);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory('D:/Temp/rshop-s10-family-settings-20261014');
    root.createSync(recursive: true);
    final directory = root.createTempSync('widget-');
    settings = await EmulatorFamilySettings.open(
        file: File('${directory.path}/emulator_families.json'),
        bundle: _FamilyBundle(defaults));
  });

  testWidgets(
      'common dialog writes the shared file; external changes reload without import',
      (tester) async {
    const channel = MethodChannel('com.retro.rshop/save_capture');
    final requested = <List<String>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final packages = List<String>.from(call.arguments['packages'] as List);
      requested.add(packages);
      return [
        if (packages.contains('org.example.switchfork'))
          {
            'packageName': 'org.example.switchfork',
            'versionName': '1',
            'documentAuthorities': <String>[],
          }
      ];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final sources = _Sources();
    await sources.ready;
    sources.publish(null);
    await tester.pumpWidget(ProviderScope(
        overrides: [sourcesProvider.overrideWith((_) => sources)],
        child: createTestApp(
            SaveBackupSettingsScreen(emulatorSettings: settings))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-nav-emulators')));
    await tester.pumpAndSettle();
    expect(find.text('Import'), findsNothing);
    expect(find.text('Export'), findsNothing);
    expect(find.byKey(const ValueKey('emulator-config-path')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-emulator-families-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('emulator-package')),
        'org.example.switchfork');
    await tester.enterText(
        find.byKey(const ValueKey('emulator-name')), 'My Switch fork');
    await tester.tap(find.byKey(const ValueKey('emulator-family')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eden / Yuzu').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('emulator-save')));
    await tester.pumpAndSettle();
    expect(
        settings.registry.packages['org.example.switchfork']!.family, 'eden');
    expect(find.text('My Switch fork'), findsOneWidget);
    expect(requested.last, contains('org.example.switchfork'));
    final saved = settings.file.readAsStringSync();
    await tester.tap(find.byKey(const ValueKey('save-emulator-families-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(settings.file.readAsStringSync(), saved);
    final external = jsonDecode(saved);
    (external['packages'] as List).last['name'] = 'External editor';
    settings.file.writeAsStringSync(jsonEncode(external), flush: true);
    // Resume is also the deterministic reload boundary for providers that do not
    // deliver shared-storage file events reliably.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('External editor'), findsOneWidget);
    settings.file.writeAsStringSync('{unfinished', flush: true);
    await tester.tap(find.byKey(const ValueKey('save-emulators-refresh')));
    await tester.pumpAndSettle();
    expect(find.textContaining('last working settings'), findsOneWidget);
    expect(find.text('External editor'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('save-emulator-families-add')))
            .onPressed,
        isNull);
    expect(settings.file.readAsStringSync(), '{unfinished');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final platform in ['ps2', 'dreamcast', 'gc']) {
    final filename = platform == 'gc' ? 'Game.rvz' : 'Game.chd';
    for (final resolved in [false, true]) {
      testWidgets(
          resolved
              ? '$platform resolved standard save folder is persisted without manual mapping'
              : '$platform unresolved standard save folder keeps custom mapping and backup setup available',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        const channel = MethodChannel('com.retro.rshop/save_capture');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'standardSaveRoot') {
            return resolved
                ? {
                    'schema': 1,
                    'directory': platform == 'ps2'
                        ? '/storage/emulated/0/Android/data/xyz.aethersx2.android/files/memcards'
                        : '/storage/emulated/0/Android/data/com.flycast.emulator/files/data',
                    'emulator': platform == 'ps2'
                        ? 'xyz.aethersx2.android'
                        : 'com.flycast.emulator',
                    'core': platform == 'ps2' ? 'pcsx2' : 'flycast',
                    'kind': 'save',
                    'format': platform == 'ps2'
                        ? 'ps2-shared-memory-cards-v1'
                        : 'dreamcast-vmu-v1',
                    'profile': platform == 'ps2'
                        ? 'nether-cards-v1'
                        : 'flycast-shared-vmus-v1',
                    'resourceId':
                        platform == 'ps2' ? 'memory-cards' : 'vmu-cards',
                    'files': platform == 'ps2'
                        ? ['Mcd001.ps2', 'Mcd002.ps2']
                        : ['vmu_save_A1.bin', 'vmu_save_A2.bin'],
                    'folders': <String>[],
                    'required': <String>[],
                    if (platform == 'gc') ...{
                      'directory':
                          '/storage/emulated/0/Android/data/org.dolphinemu.dolphinemu/files/GC',
                      'emulator': 'org.dolphinemu.dolphinemu',
                      'core': 'dolphin',
                      'format': 'gamecube-gci-cards-v1',
                      'profile': 'dolphin-gci-cards-v1',
                      'resourceId': 'gc-memory-cards',
                      'files': <String>[],
                      'folders': [
                        'EUR/Card A',
                        'JAP/Card A',
                        'USA/Card A',
                        'DEV/Card A'
                      ],
                    }
                  }
                : throw PlatformException(code: 'save_settings_unresolved');
          }
          return null;
        });
        addTearDown(() => TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));
        final sources = _Sources();
        await sources.ready;
        sources.publish('account');
        final game = GameItem(
            filename: filename,
            displayName: 'Game',
            url: 'drive:fixture',
            remoteArtifact: RemoteArtifact(
                id: RemoteArtifactId(
                    providerId: 'drive',
                    sourceId: 'same-source',
                    accountId: 'account',
                    providerFileId: 'file'),
                displayPath: filename,
                displayName: filename));
        await tester.pumpWidget(ProviderScope(
            overrides: [sourcesProvider.overrideWith((_) => sources)],
            child: createTestApp(SaveBackupSettingsScreen(
                editionId: 'edition',
                gameTitle: 'Game',
                game: game,
                system: SystemModel(
                    id: platform,
                    name: platform == 'gc'
                        ? 'GameCube'
                        : platform == 'ps2'
                            ? 'PlayStation 2'
                            : 'Dreamcast',
                    manufacturer: platform == 'gc'
                        ? 'Nintendo'
                        : platform == 'ps2'
                            ? 'Sony'
                            : 'Sega',
                    releaseYear: 2000),
                targetFolder: '/storage/1234-ABCD/Roms/$platform'))));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('save-import-mapping')), findsOneWidget);
        if (resolved) {
          final preferences = await SharedPreferences.getInstance();
          final saved = jsonDecode(preferences.getString(
              SaveRootConfiguration.storageKey(game.remoteArtifact!.id.key))!);
          expect(
              saved['profile'],
              platform == 'gc'
                  ? 'dolphin-gci-cards-v1'
                  : platform == 'ps2'
                      ? 'nether-cards-v1'
                      : 'flycast-shared-vmus-v1');
          expect(
              saved['files'],
              platform == 'gc'
                  ? <String>[]
                  : platform == 'ps2'
                      ? ['Mcd001.ps2', 'Mcd002.ps2']
                      : ['vmu_save_A1.bin', 'vmu_save_A2.bin']);
          expect(
              tester
                  .widget<DropdownButtonFormField<bool>>(
                      find.byKey(const ValueKey('game-backup-scope')))
                  .initialValue,
              isTrue);
        }
        await tester.tap(find.byKey(const ValueKey('save-nav-area')));
        await tester.pumpAndSettle();
        expect(find.byType(SaveBackupSetupPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets(
      'coverage keeps the existing save workspace mounted but unfocusable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('com.retro.rshop/save_capture');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => <Object>[]);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final sources = _Sources();
    await sources.ready;
    sources.publish('account');
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sourcesProvider.overrideWith((_) => sources),
        ],
        child: createTestApp(
            SaveBackupSettingsScreen(emulatorSettings: settings))));
    await tester.pumpAndSettle();
    final workspace = find.byWidgetPredicate(
        (widget) => widget is FutureBuilder<SaveBackupSetup>,
        skipOffstage: false);
    final original = tester.state(workspace);
    await tester.tap(find.byKey(const ValueKey('save-nav-emulators')));
    await tester.pumpAndSettle();
    expect(workspace, findsOneWidget);
    expect(tester.state(workspace), same(original));
    expect(find.byType(SaveBackupSetupPanel), findsNothing);
    final exclusion = tester.widget<ExcludeFocus>(find.ancestor(
        of: workspace,
        matching: find.byKey(const ValueKey('save-workspace-focus'),
            skipOffstage: false)));
    expect(exclusion.excluding, isTrue);
    await tester.tap(find.byKey(const ValueKey('save-nav-area')));
    await tester.pumpAndSettle();
    expect(tester.state(workspace), same(original));
    expect(find.byType(SaveBackupSetupPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('emulator coverage is a separate offline section without Drive',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('com.retro.rshop/save_capture');
    final calls = <MethodCall>[];
    var failInventory = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (failInventory) throw PlatformException(code: 'inventory_unavailable');
      return [
        {
          'packageName': 'org.dolphinemu.dolphinemu',
          'versionName': '2606',
          'documentAuthorities': ['org.dolphinemu.dolphinemu.user']
        },
        {
          'packageName': 'org.ppsspp.ppsspp',
          'versionName': 'v1.20.4',
          'documentAuthorities': <String>[]
        }
      ];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final sources = _Sources();
    await sources.ready;
    sources.publish(null);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sourcesProvider.overrideWith((_) => sources),
        ],
        child: createTestApp(
            SaveBackupSettingsScreen(emulatorSettings: settings))));
    await tester.pumpAndSettle();
    expect(calls, isEmpty); // Not a startup scan or a permission prompt.
    await tester.tap(find.byKey(const ValueKey('save-nav-emulators')));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'installedSaveEmulators');
    expect(find.text('Dolphin'), findsOneWidget);
    expect(find.textContaining('GameCube card folders share one history'),
        findsOneWidget);
    expect(find.text('States: Verified · reviewed PPSSPP state slot'),
        findsOneWidget);
    expect(
        find.text('Saves: In-game saves · complete PPSSPP SAVEDATA folders.'),
        findsOneWidget);
    expect(find.byType(SaveBackupSetupPanel), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-nav-status')));
    await tester.pumpAndSettle();
    expect(find.text('Dolphin'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-nav-emulators')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2)); // Section entry reloads external configuration.
    await tester.tap(find.byKey(const ValueKey('save-emulators-refresh')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(3));
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.text('Dolphin'), findsOneWidget);
    failInventory = true;
    final refresh = find.byKey(const ValueKey('save-emulators-refresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.textContaining('emulator list could not be loaded'),
        findsOneWidget);
    expect(find.text('Dolphin'), findsNothing); // Not stale success or empty.
    await tester.tap(find.byKey(const ValueKey('save-nav-emulators')));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-content-status')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final melon in [false, true]) {
    testWidgets(
        '${melon ? 'MelonDualDS' : 'PPSSPP'} mapping requires file selection and edition confirmation',
        (tester) async {
      final prefix = melon ? 'melon' : 'ppsspp';
      final directory = melon
          ? '/storage/emulated/0/Saves/MelonDualDS'
          : '/storage/emulated/0/PSP/PPSSPP_STATE';
      final name = melon ? 'Game.sav' : 'ULUS10041_1.00_0.ppst';
      const channel = MethodChannel('com.retro.rshop/save_capture');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'melonSaveSettings') {
          return {'mode': 'rom', 'directory': null, 'extension': 'sav'};
        }
        return [name];
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final mapped = <String>[];
      final commit = Completer<void>();
      var cancelled = 0;
      await tester.pumpWidget(createTestApp(Scaffold(
          body: SingleChildScrollView(
              child: StandaloneSaveMappingPanel(
                  melon: melon,
                  title: 'Reviewed edition',
                  capture: SaveCapture(),
                  chooseDirectory: () async => directory,
                  onCancel: () => cancelled++,
                  onMapped: (directory, slot) async {
                    await commit.future;
                    mapped.add('$directory/$slot');
                  })))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('$prefix-map-folder')));
      await tester.pumpAndSettle();
      expect(calls.last.method, melon ? 'melonNames' : 'ppssppNames');
      final save = find.byKey(ValueKey('$prefix-map-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.byKey(ValueKey('$prefix-map-slot')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.ensureVisible(find.byKey(ValueKey('$prefix-map-confirm')));
      await tester.tap(find.byKey(ValueKey('$prefix-map-confirm')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      final cancel = find.byKey(const ValueKey('save-change-location-cancel'));
      expect(tester.widget<TextButton>(cancel).onPressed, isNull,
          reason: 'A location commit must finish before cancelling the editor');
      expect(mapped, isEmpty);
      commit.complete();
      await tester.pumpAndSettle();
      expect(mapped, ['$directory/$name']);
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      expect(cancelled, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Melon standard folder is available without the Android folder picker',
      (tester) async {
    const channel = MethodChannel('com.retro.rshop/save_capture');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'melonSaveSettings') {
        return {'mode': 'rom', 'directory': null, 'extension': 'sav'};
      }
      return ['Game.sav'];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    var pickerCalled = false;
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: StandaloneSaveMappingPanel(
                melon: true,
                title: 'Reviewed DS edition',
                capture: SaveCapture(),
                chooseDirectory: () async {
                  pickerCalled = true;
                  return null;
                },
                onMapped: (_, __) async {})))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('melon-map-standard')));
    await tester.pumpAndSettle();
    expect(pickerCalled, isFalse);
    expect(calls.last.method, 'melonNames');
    expect(calls.last.arguments['directory'],
        '/storage/emulated/0/Android/data/me.magnum.melondualds/files/saves');
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('melon-map-save')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Melon discovers its configured folder without opening the picker',
      (tester) async {
    const channel = MethodChannel('com.retro.rshop/save_capture');
    const directory = '/storage/75D7-DC5F/Saves/DS';
    final calls = <MethodCall>[];
    var pickerCalls = 0, mappingCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'melonSaveSettings') {
        return {'mode': 'custom', 'directory': directory, 'extension': 'srm'};
      }
      if (call.method == 'melonNames') return ['Game.srm'];
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(Scaffold(
            body: SingleChildScrollView(
                child: StandaloneSaveMappingPanel(
                    melon: true,
                    title: 'Reviewed DS edition',
                    capture: SaveCapture(),
                    chooseDirectory: () async {
                      pickerCalls++;
                      return null;
                    },
                    onMapped: (_, __) async {
                      mappingCalls++;
                    }))))));
    await tester.pumpAndSettle();
    expect(
        calls.map((call) => call.method), ['melonSaveSettings', 'melonNames']);
    expect(calls.last.arguments['directory'], directory);
    expect(pickerCalls, 0);
    expect(mappingCalls, 0); // Location discovery is not edition evidence.
    expect(find.text(directory), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('melon-map-save')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'DS launch-bound mapping finds the exact destination even before the first save',
      (tester) async {
    const channel = MethodChannel('com.retro.rshop/save_capture');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String>[];
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    var pickerCalls = 0;
    final mapped = <String>[];
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: StandaloneSaveMappingPanel(
      melon: true,
      title: 'Reviewed DS edition',
      capture: SaveCapture(),
      resolveMelonSave: () async =>
          (directory: SaveCapture.melonStandardDirectory, name: 'Game.sav'),
      chooseDirectory: () async {
        pickerCalls++;
        return null;
      },
      onMapped: (directory, name) async => mapped.add('$directory/$name'),
    )))));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'melonNames');
    expect(pickerCalls, 0);
    expect(find.text('Game.sav'), findsOneWidget);
    final save = find.byKey(const ValueKey('melon-map-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('melon-map-confirm')));
    await tester.tap(find.byKey(const ValueKey('melon-map-confirm')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(mapped, ['${SaveCapture.melonStandardDirectory}/Game.sav']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('save settings has persistent independent left-hand sections',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sources = _Sources();
    await sources.ready;
    sources.publish('account');
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sourcesProvider.overrideWith((_) => sources),
        ],
        child: createTestApp(
            SaveBackupSettingsScreen(emulatorSettings: settings))));
    await tester.pumpAndSettle();
    final navigation = find.byKey(const ValueKey('save-backup-navigation'));
    expect(navigation.hitTestable(), findsOneWidget);
    final area = find.byKey(const ValueKey('save-nav-area'));
    final status = find.byKey(const ValueKey('save-nav-status'));
    expect(tester.getRect(area).right,
        lessThan(tester.getRect(find.byType(SaveBackupSetupPanel)).left));
    await tester.tap(status);
    await tester.pumpAndSettle();
    expect(find.byType(SaveBackupSetupPanel), findsNothing);
    expect(find.textContaining('No game selected'), findsOneWidget);
    // Portrait and enlarged text keep navigation beside independently scrolling
    // content rather than turning the sections into another long page.
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.tap(area);
    await tester.pumpAndSettle();
    expect(navigation.hitTestable(), findsOneWidget);
    expect(find.byType(SaveBackupSetupPanel), findsOneWidget);
    // Touch selection establishes the same single focus target used by D-pad.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.byType(SaveBackupSetupPanel), findsNothing);
    expect(find.byKey(const ValueKey('save-content-backup')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('same source account change retires the old backup setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SaveBackupSetup.storageKey('settings-test-client', 'first-account'):
          jsonEncode({'areaId': 'first-area', 'ready': true}),
    });
    final sources = _Sources();
    await sources.ready;
    sources.publish('first-account');
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sourcesProvider.overrideWith((_) => sources),
        ],
        child: createTestApp(
            SaveBackupSettingsScreen(emulatorSettings: settings))));
    await tester.pumpAndSettle();
    expect(find.text('Drive backups are ready to set up for your games'),
        findsOneWidget);
    sources.publish('second-account');
    await tester.pumpAndSettle();
    expect(find.text('Drive backups are ready to set up for your games'),
        findsNothing);
    expect(find.byKey(const ValueKey('save-backup-authorize')), findsOneWidget);
    final panel =
        tester.widget<SaveBackupSetupPanel>(find.byType(SaveBackupSetupPanel));
    expect(panel.setup.accountId, 'second-account');
    expect(panel.setup.areaId, isNull);
    sources.publish(null);
    await tester.pumpAndSettle();
    expect(find.byType(SaveBackupSetupPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'setup explains its boundary and remains touch/controller reachable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final driver = _Driver();
    final authorization = DriveAuthorization(driver);
    final transport = _Transport();
    final setup = SaveBackupSetup(
        accountId: 'account',
        clientId: 'client',
        preferences: prefs,
        authorization: authorization,
        api: DriveSaveBackupAreaApi(
            authorization: authorization,
            accountId: 'account',
            transport: transport));
    addTearDown(setup.dispose);
    await setup.load();
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(SaveBackupSetupPanel(setup: setup))));
    await tester.pumpAndSettle();
    expect(find.textContaining('not your cloud ROMs'), findsOneWidget);
    expect(find.textContaining('No saves selected yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-backup-authorize')));
    await tester.pump();
    await driver.started.future;
    expect(setup.busy, isTrue);
    expect(find.byKey(const ValueKey('save-backup-cancel')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('save-backup-authorize')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('save-backup-cancel')));
    driver.consent.complete('token');
    await tester.pumpAndSettle();
    expect(setup.ready, isFalse);
    expect(transport.requests, isEmpty);
    final authorize = find.byKey(const ValueKey('save-backup-authorize'));
    final context = tester.element(authorize);
    Focus.of(context).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(2));
    expect(transport.requests.last.uri.path, endsWith('/files/area'));
    expect(setup.issue, isNotNull); // Synthetic response fails exact root GET.
    expect(find.textContaining('Setup needs attention:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
