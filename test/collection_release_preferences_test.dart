import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/core/input/input.dart';
import 'package:retro_eshop/features/settings/collection_filters_screen.dart';
import 'package:retro_eshop/models/commercial_release_preference.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/services/migration/migration_activation.dart';
import 'package:retro_eshop/services/migration/migration_archive.dart';
import 'helpers/pump_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('ordered versions survive restart and encrypted settings migration',
      () async {
    final storage = StorageService();
    await storage.init();
    final value =
        const CommercialReleasePreference().move(2, -2).showingAll(true);
    await storage.setCommercialReleasePreference(value);
    final reopened = StorageService();
    await reopened.init();
    expect(reopened.getCommercialReleasePreference().toJson(), value.toJson());
    final source = await const DeviceMigrationSettings().readPreferences();
    final root =
        await Directory.systemTemp.createTemp('rshop-region-migration-');
    // Retain the fixture until task-owned cleanup reviews its exact files.
    final archive = File('${root.path}/settings.rshop');
    final codec = MigrationArchive();
    await codec.write(archive,
        password: 'synthetic region preference password',
        state: {'preferences': source},
        files: const []);
    SharedPreferences.setMockInitialValues({});
    final restored = await codec.read(archive,
        password: 'synthetic region preference password',
        privateRoot: Directory('${root.path}/restored'));
    await const DeviceMigrationSettings().writePreferences(
        (restored.state['preferences'] as Map).cast<String, Object?>());
    final destination = StorageService();
    await destination.init();
    expect(
        destination.getCommercialReleasePreference().toJson(), value.toJson());
    expect(
        CommercialReleasePreference.fromJson(jsonDecode(
                (await SharedPreferences.getInstance())
                    .getString(StorageService.commercialReleasePreferenceKey)!))
            .regions,
        ['JPN', 'EUR', 'USA']);
  });

  testWidgets('sectioned filters support touch, controller reorder and reset',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = StorageService();
    await storage.init();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: GlobalInputWrapper(
            child: createTestApp(const CollectionFiltersScreen()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('show-all-versions')));
    await tester.pumpAndSettle();
    expect(storage.getCommercialReleasePreference().showAllVersions, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('region-up-USA')));
    await tester.pumpAndSettle();
    expect(storage.getCommercialReleasePreference().regions,
        ['USA', 'EUR', 'JPN']);
    await tester.tap(find.byKey(const ValueKey('region-up-JPN')));
    await tester.pumpAndSettle();
    // Establish focus on the actual Material control, then use the app's A
    // mapping. Touch devices do not promise keyboard focus after pointer taps.
    tester
        .widget<IconButton>(find.byKey(const ValueKey('region-up-JPN')))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(storage.getCommercialReleasePreference().regions.first, 'JPN');
    await tester.tap(find.byKey(const ValueKey('reset-region-order')));
    await tester.pumpAndSettle();
    expect(storage.getCommercialReleasePreference().regions,
        ['EUR', 'USA', 'JPN']);
    expect(storage.getCommercialReleasePreference().showAllVersions, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('show-all-versions')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
