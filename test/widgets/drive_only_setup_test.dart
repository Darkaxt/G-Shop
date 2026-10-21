import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:g_shop/features/settings/sources_screen.dart';
import 'package:g_shop/features/settings/config_mode_screen.dart';
import 'package:g_shop/features/onboarding/widgets/welcome_chooser_step.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/source.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/providers/game_providers.dart';
import 'package:g_shop/services/config_bootstrap.dart';
import 'package:g_shop/services/config_storage_service.dart';
import 'package:g_shop/services/storage_service.dart';
import '../helpers/pump_helpers.dart';

class MemoryDriveConfig extends ConfigStorageService {
  MemoryDriveConfig(this.config);
  AppConfig config;
  @override
  Future<AppConfig?> loadConfig() async => config;
  @override
  Future<File> saveConfig(String json) async {
    config =
        AppConfig.fromJson((jsonDecode(json) as Map).cast<String, dynamic>());
    return File('unused-config.json');
  }
}

void main() => defineDriveOnlySetupChecks();
void defineDriveOnlySetupChecks(
    {bool native = false,
    void Function(String)? verified,
    Future<void> Function(String, WidgetTester)? checkpoint}) {
  const drive = Source(
      id: 'drive',
      name: 'Private Drive',
      type: SourceType.drive,
      drive: DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'root',
          serverClientId: 'client'));
  const retired = Source(
      id: 'old',
      name: 'Retired server',
      type: SourceType.web,
      url: 'https://example.invalid');
  const system = SystemConfig(
      id: 'gb',
      name: 'Game Boy',
      targetFolder: '/existing/gb',
      providers: [],
      manualMappings: [
        SystemSourceMapping(sourceId: 'drive', remotePath: 'gb-folder'),
        SystemSourceMapping(sourceId: 'old', remotePath: '/gb')
      ]);
  for (final size in [const Size(1920, 1080), const Size(800, 480)]) {
    testWidgets('Drive-only setup and destination options at ${size.width}',
        (tester) async {
      if (!native) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
      }
      addTearDown(() {
        if (!native) {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      });
      SharedPreferences.setMockInitialValues({'haptic_enabled': false});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final raw = MemoryDriveConfig(
          AppConfig(systems: [system], sources: [drive, retired]));
      final overrides = [
        configStorageServiceProvider.overrideWithValue(raw),
        storageServiceProvider.overrideWithValue(storage),
        bootstrappedConfigProvider
            .overrideWith((ref) async => ConfigBootstrap.active(raw.config))
      ];
      await tester.pumpWidget(createTestAppWithProviders(const SourcesScreen(),
          overrides: overrides));
      await tester.pumpAndSettle();
      expect(find.text('Private Drive'), findsOneWidget);
      expect(find.text('Retired server'), findsNothing);
      expect(find.textContaining('Pair RomM'), findsNothing);
      await tester.tap(find.text('Private Drive'));
      await tester.pumpAndSettle();
      expect(find.text('Edit mappings'), findsOneWidget);
      expect(find.text('Re-pair'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(createTestAppWithProviders(
          const ConfigModeScreen(),
          overrides: overrides));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Game Boy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto-extract: Off'));
      await tester.pumpAndSettle();
      expect(raw.config.systemById('gb')!.autoExtract, isTrue);
      expect(raw.config.systemById('gb')!.targetFolder, '/existing/gb');
      expect(raw.config.sourceById('old')!.toJson(), retired.toJson());
      expect(raw.config.systemById('gb')!.manualMappings.length, 2);
      expect(tester.takeException(), isNull);
      await checkpoint?.call('drive-only-${size.width.toInt()}', tester);
      verified?.call('drive-only-${size.width.toInt()}');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets('welcome offers Drive instead of standalone local/server paths',
      (tester) async {
    final raw = MemoryDriveConfig(AppConfig.empty);
    await tester.pumpWidget(createTestAppWithProviders(
        const WelcomeChooserStep(),
        overrides: [configStorageServiceProvider.overrideWithValue(raw)]));
    await tester.pumpAndSettle();
    expect(find.text('Connect Google Drive'), findsOneWidget);
    expect(find.textContaining('Local games only'), findsNothing);
    expect(find.textContaining('RomM'), findsNothing);
    expect(find.textContaining('SMB'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
