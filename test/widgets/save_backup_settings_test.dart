import 'dart:async';
import 'dart:convert';

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
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/config_storage_service.dart';
import 'package:retro_eshop/services/sources_notifier.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/saves/drive_save_backup_area.dart';
import 'package:retro_eshop/services/saves/save_backup_setup.dart';
import 'package:retro_eshop/services/saves/save_capture.dart';
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

void main() {
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
    await tester.pumpWidget(ProviderScope(overrides: [
      sourcesProvider.overrideWith((_) => sources),
    ], child: createTestApp(const SaveBackupSettingsScreen())));
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
    await tester.pumpWidget(ProviderScope(overrides: [
      sourcesProvider.overrideWith((_) => sources),
    ], child: createTestApp(const SaveBackupSettingsScreen())));
    await tester.pumpAndSettle();
    expect(calls, isEmpty); // Not a startup scan or a permission prompt.
    await tester.tap(find.byKey(const ValueKey('save-nav-emulators')));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'installedSaveEmulators');
    expect(find.text('Dolphin'), findsOneWidget);
    expect(find.textContaining('Document picker provider advertised'),
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
    expect(calls, hasLength(1)); // Section changes do not rescan/restart work.
    await tester.tap(find.byKey(const ValueKey('save-emulators-refresh')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
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
      await tester.pumpWidget(createTestApp(Scaffold(
          body: SingleChildScrollView(
              child: StandaloneSaveMappingPanel(
                  melon: melon,
                  title: 'Reviewed edition',
                  capture: SaveCapture(),
                  chooseDirectory: () async => directory,
                  onMapped: (directory, slot) async =>
                      mapped.add('$directory/$slot'))))));
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
      await tester.pumpAndSettle();
      expect(mapped, ['$directory/$name']);
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
    await tester.pumpWidget(ProviderScope(overrides: [
      sourcesProvider.overrideWith((_) => sources),
    ], child: createTestApp(const SaveBackupSettingsScreen())));
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
    await tester.pumpWidget(ProviderScope(overrides: [
      sourcesProvider.overrideWith((_) => sources),
    ], child: createTestApp(const SaveBackupSettingsScreen())));
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
