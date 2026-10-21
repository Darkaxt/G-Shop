import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:g_shop/features/onboarding/onboarding_controller.dart';
import 'package:g_shop/features/settings/config_mode_screen.dart';
import 'package:g_shop/l10n/app_localizations.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/source.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/providers/game_providers.dart';
import 'package:g_shop/services/config_storage_service.dart';
import 'package:g_shop/services/storage_service.dart';

class _MemoryConfigStorage extends ConfigStorageService {
  _MemoryConfigStorage(this.config);
  AppConfig config;
  @override
  Future<AppConfig?> loadConfig() async => config;
  @override
  Future<File> saveConfig(String json) async {
    config = AppConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    return File('unused-config.json');
  }
}

void main() {
  for (final nativeBack in [false, true]) {
    testWidgets(
        '${nativeBack ? 'Android' : 'HUD'} Back saves console edits and mappings',
        (tester) async {
      const original = AppConfig(systems: [
        SystemConfig(
          id: 'gc',
          name: 'Nintendo GameCube',
          targetFolder: '/original/gc',
          providers: [],
          enabledSourceIds: ['fixture'],
          manualMappings: [
            SystemSourceMapping(sourceId: 'fixture', remotePath: 'root')
          ],
        )
      ]);
      final configStorage = _MemoryConfigStorage(original);
      // The bootstrap result is isolated from network/database setup; the
      // controller and persisted config service below are real implementations.
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final container = ProviderContainer(overrides: [
        bootstrappedConfigProvider.overrideWith((ref) async => original),
        configStorageServiceProvider.overrideWithValue(configStorage),
        storageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              localizationsDelegates: L.localizationsDelegates,
              supportedLocales: L.supportedLocales,
              home: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const ConfigModeScreen())),
                      child: const Text('Configure'))))));
      await tester.tap(find.text('Configure'));
      await tester.pumpAndSettle();
      final controller = container.read(onboardingControllerProvider.notifier);
      controller.selectConsole('gc');
      controller.setTargetFolder('/isolated/gc');
      controller.setAutoExtract(true);
      await tester.pumpAndSettle();
      if (nativeBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('Back'));
      }
      await tester.pumpAndSettle();
      expect(controller.state.hasConsoleSelected, isFalse);
      expect(controller.state.configuredSystems['gc']!.targetFolder,
          '/isolated/gc');
      if (nativeBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('Back'));
      }
      await tester.pumpAndSettle();
      final persisted = (await configStorage.loadConfig())!.systemById('gc')!;
      expect(persisted.targetFolder, '/isolated/gc');
      expect(persisted.autoExtract, isTrue);
      expect(persisted.enabledSourceIds, ['fixture']);
      expect(persisted.manualMappings.single.remotePath, 'root');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
