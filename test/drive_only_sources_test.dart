import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/source.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/services/config_storage_service.dart';
import 'package:g_shop/services/source_resolver.dart';
import 'package:g_shop/services/provider_factory.dart';
import 'package:g_shop/services/sources_notifier.dart';

import 'package:g_shop/services/config_bootstrap.dart';
import 'package:g_shop/features/onboarding/onboarding_controller.dart';
import 'package:g_shop/services/download_queue_manager.dart';
import 'package:g_shop/services/storage_service.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/system_model.dart';

class _QueuePreferences extends StorageService {
  @override
  int getMaxConcurrentDownloads() => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const drive = DriveSourceConfig(
      accountId: 'account', rootFolderId: 'root', serverClientId: 'client');
  const source =
      Source(id: 'drive', name: 'Drive', type: SourceType.drive, drive: drive);
  const retired = Source(
      id: 'old',
      name: 'Old server',
      type: SourceType.web,
      url: 'https://example.invalid');
  const system = SystemConfig(
      id: 'gb',
      name: 'Game Boy',
      targetFolder: '/existing/roms/gb',
      providers: [],
      manualMappings: [
        SystemSourceMapping(sourceId: 'drive', remotePath: 'gb-folder'),
        SystemSourceMapping(sourceId: 'old', remotePath: '/gb'),
      ]);
  test('active view retires standalone consoles without rewriting stored data',
      () {
    const local = SystemConfig(
        id: 'nes', name: 'NES', targetFolder: '/preserved/nes', providers: []);
    final raw = AppConfig(systems: [system, local], sources: [source, retired]);
    final before = jsonEncode(raw.toJson());
    final active = ConfigBootstrap.active(raw);
    expect(active.sources.map((s) => s.id), ['drive']);
    expect(active.systems.map((s) => s.id), ['gb']);
    expect(active.systems.single.providers.map((p) => p.type),
        [ProviderType.drive]);
    expect(jsonEncode(raw.toJson()), before);
    final disabled = ConfigBootstrap.active(
        raw.copyWith(sources: [source.copyWith(enabled: false), retired]));
    expect(disabled.systems.single.providers, isEmpty);
    expect(disabled.systems.single.targetFolder, system.targetFolder);
  });
  test('retired downloads cannot enter an executable transfer queue', () async {
    final queue = DownloadQueueManager(_QueuePreferences());
    final game = GameItem(
        filename: 'old.gb',
        displayName: 'Old',
        url: 'https://example.invalid/old.gb',
        providerConfig:
            const ProviderConfig(type: ProviderType.web, priority: 0));
    expect(game.hasDownloadSource, isFalse);
    expect(
        () => queue.addToQueue(
            game,
            SystemModel.supportedSystems.firstWhere((s) => s.id == 'gb'),
            '/preserved/gb'),
        throwsUnsupportedError);
    expect(queue.state.queue, isEmpty);
    await queue.close();
    queue.dispose();
  });
  test(
      'Drive resolution retains explicit mapping, priority and source allowlists',
      () {
    final configured = system.copyWith(manualMappings: const [
      SystemSourceMapping(
          sourceId: 'drive', remotePath: 'opaque-folder', priorityOverride: 2),
    ]);
    final providers =
        SourceResolver.providersFor(configured, [source, retired]);
    expect(providers.single.sourceId, 'drive');
    expect(providers.single.path, 'opaque-folder');
    expect(providers.single.priority, 2);
    expect(
        SourceResolver.providersFor(
            configured.copyWith(enabledSourceIds: []), [source]),
        isEmpty);
    expect(
        SourceResolver.providersFor(
            configured, [source.copyWith(enabled: false)]),
        isEmpty);
    expect(
        SourceResolver.providersFor(
            system.copyWith(manualMappings: []), [source]),
        isEmpty);
  });
  test('legacy-only imports cannot finish Drive onboarding', () async {
    final root = await Directory.systemTemp.createTemp('gshop-onboarding-');
    final storage = ConfigStorageService(directoryProvider: () async => root);
    final controller = OnboardingController(storage);
    addTearDown(controller.dispose);
    controller.loadFromConfig(AppConfig(systems: [system], sources: [retired]));
    expect(controller.state.currentStep, OnboardingStep.welcome);
    await expectLater(controller.buildFinalConfig(), throwsStateError);
    final config = AppConfig(systems: [system], sources: [source, retired]);
    await storage.saveConfig(jsonEncode(config.toJson()));
    await controller.completeFromDriveSource('drive');
    expect(controller.state.currentStep, OnboardingStep.complete);
    expect(controller.state.configuredCount, 1);
    expect((await controller.buildFinalConfig()).toJson(), config.toJson());
  });
  test('only Drive is executable; legacy data still round-trips', () {
    final raw = AppConfig(systems: [system], sources: [source, retired]);
    expect(SourceResolver.providersFor(system, raw.sources).map((p) => p.type),
        [ProviderType.drive]);
    expect(
        () => ProviderFactory.getProvider(const ProviderConfig(
            type: ProviderType.web,
            priority: 0,
            url: 'https://example.invalid')),
        throwsUnsupportedError);
    final restored = AppConfig.fromJson(raw.toJson());
    expect(restored.sourceById('old')!.url, retired.url);
    expect(restored.systemById('gb')!.targetFolder, system.targetFolder);
  });
  test('editing Drive preserves retired source definitions and mappings',
      () async {
    final root = await Directory.systemTemp.createTemp('gshop-config-');
    final storage = ConfigStorageService(directoryProvider: () async => root);
    const oldProvider = ProviderConfig(
        type: ProviderType.web,
        priority: 7,
        sourceId: 'old',
        managedBySource: true,
        url: 'https://example.invalid/gb');
    await storage.saveConfig(jsonEncode(AppConfig(systems: [
      system.copyWith(providers: [oldProvider])
    ], sources: [
      source,
      retired
    ]).toJson()));
    final notifier = SourcesNotifier(storage);
    addTearDown(notifier.dispose);
    await notifier.ready;
    expect(notifier.state.sources.map((s) => s.id), ['drive']);
    await notifier.updateSource(source.copyWith(name: 'My Drive'));
    final raw = (await storage.loadConfig())!;
    expect(raw.sourceById('old')!.toJson(), retired.toJson());
    expect(
        raw
            .systemById('gb')!
            .providers
            .singleWhere((p) => p.sourceId == 'old')
            .toJson(),
        oldProvider.toJson());
    expect(raw.systemById('gb')!.manualMappings.any((m) => m.sourceId == 'old'),
        isTrue);
    await expectLater(notifier.addSource(retired), throwsUnsupportedError);
    await expectLater(notifier.setMappingsForSource('old', {'gb': '/changed'}),
        throwsStateError);
    expect(
        (await storage.loadConfig())!
            .systemById('gb')!
            .manualMappings
            .firstWhere((m) => m.sourceId == 'old')
            .remotePath,
        '/gb');
  });
}
