import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/features/settings/widgets/general_tab.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/features/settings/metadata_settings_screen.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/storage_service.dart';

import '../test/metadata_controls_test.dart'
    show controlsDatabase, MemorySecrets, ControlsProvider;

/// Native SQLite and normal settings UI, using only in-memory synthetic data.
/// Never starts main.dart, normal sources, a real provider or a ROM operation.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('S5 native settings controller entry, pause and fresh coverage',
      (tester) async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    final package = await PackageInfo.fromPlatform();
    expect(package.packageName, 'com.darkaxt.rshop.debug');
    final db = await controlsDatabase(factory: databaseFactory);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final secrets = MemorySecrets();
    final ss = ScreenScraperCredentialStore(storage: secrets);
    final provider = ControlsProvider();
    final started = Completer<void>();
    provider.reply = (_, cancel) async {
      started.complete();
      await cancel!.whenCancel;
      return MetadataLookupResult(
          status: MetadataLookupStatus.cancelled, message: 'Fixture paused');
    };
    final controls = MetadataControlsController(
        database: Future.value(db),
        providers: {
          'screenscraper': provider,
          'igdb': ControlsProvider('igdb')
        },
        screenScraperCredentials: ss,
        igdbCredentials: IgdbCredentialStore(storage: secrets),
        catalogueChanged: () {});
    await controls.load();
    final snapshot = controls.refresh();
    await controls.pause();
    await snapshot;
    expect(provider.calls, isEmpty);
    expect(controls.state.report!.state, 'paused');
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    final first = FocusNode();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: Scaffold(body: SettingsGeneralTab(firstFocusNode: first)))));
    await tester.pumpAndSettle();
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.byType(MetadataSettingsScreen), findsOneWidget);
    expect(provider.calls, isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('metadata-username')), 'synthetic-user');
    await tester.enterText(
        find.byKey(const ValueKey('metadata-password')), 'synthetic-secret');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('metadata-save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await ss.readUser())!.username, 'synthetic-user');
    expect(find.text('synthetic-secret'), findsNothing);
    expect(provider.calls, isEmpty);
    final refresh = find.byKey(const ValueKey('metadata-refresh'));
    await tester.ensureVisible(refresh);
    await tester.pumpAndSettle();
    await tester.tap(refresh);
    await started.future;
    await tester.pump();
    final pause = find.byKey(const ValueKey('metadata-pause'));
    await tester.ensureVisible(pause);
    await tester.pump();
    await tester.tap(pause);
    await controls.pause();
    await tester.pumpAndSettle();
    final pausedId = controls.state.report!.id;
    expect(controls.state.report!.state, 'paused');
    provider.reply = null;
    final finished = Completer<void>();
    final removeListener = controls.addListener((state) {
      if (!state.busy &&
          state.report?.state == 'completed' &&
          !finished.isCompleted) {
        finished.complete();
      }
    });
    final resume = find.byKey(const ValueKey('metadata-resume'));
    await tester.ensureVisible(resume);
    await tester.pumpAndSettle();
    await tester.tap(resume);
    await finished.future;
    removeListener();
    await tester.pumpAndSettle();
    expect(controls.state.report!.id, pausedId);
    expect(controls.state.report!.state, 'completed');
    expect(controls.state.report!.counts, {'unmatched': 2});
    expect(controls.state.report!.rated, 0);
    await tester.ensureVisible(find.textContaining('does not mean every game'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    binding.reportData = {
      'scope': 'S5 normal native settings entry and refresh',
      'package': package.packageName,
      'controller_entry': true,
      'touch_setup': true,
      'same_job_pause_resume': true,
      'pause_before_lookup': true,
      'requested': controls.state.report!.requested,
      'unmatched': 2,
      'rated': 0,
      'rom_requests': 0,
      'real_provider_access': false
    };
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MetadataSettingsScreen), findsNothing);
    // Leave the normal metadata screen visible for an actual-font screenshot.
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('does not mean every game'));
    await tester.pumpAndSettle();
    await controls.close();
    await db.close();
  });
}
