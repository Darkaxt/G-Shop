import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/features/settings/widgets/general_tab.dart';
import 'package:retro_eshop/features/settings/metadata_settings_screen.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/metadata_providers.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/storage_service.dart';
import '../metadata_controls_test.dart'
    show controlsDatabase, MemorySecrets, ControlsProvider;
import '../helpers/pump_helpers.dart';

void main() {
  test('primary button labels retain contrast in enabled interaction states',
      () {
    final style = AppTheme.primaryButtonStyle;
    for (final states in <Set<WidgetState>>[
      {},
      {WidgetState.hovered},
      {WidgetState.focused},
      {WidgetState.pressed},
    ]) {
      final foreground = style.foregroundColor!.resolve(states)!;
      final background = style.backgroundColor!.resolve(states)!;
      final overlay = style.overlayColor!.resolve(states) ?? Colors.transparent;
      final painted = Color.alphaBlend(overlay, background);
      expect(foreground, Colors.white);
      expect(
          (foreground.computeLuminance() + 0.05) /
              (painted.computeLuminance() + 0.05),
          greaterThanOrEqualTo(4.5));
    }
    // Null disabled overrides preserve each screen's existing theme defaults.
    expect(style.foregroundColor!.resolve({WidgetState.disabled}), isNull);
    expect(style.backgroundColor!.resolve({WidgetState.disabled}), isNull);
    expect(AppTheme.primaryColor, Colors.redAccent);
  });

  testWidgets(
      'General settings opens metadata setup and fresh local-catalogue refresh',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = await controlsDatabase();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final secrets = MemorySecrets();
    final ss = ScreenScraperCredentialStore(storage: secrets);
    final provider = ControlsProvider();
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
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    final focus = FocusNode();
    addTearDown(() async {
      await controls.close();
      container.dispose();
      focus.dispose();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: createTestApp(SettingsGeneralTab(firstFocusNode: focus))));
    await tester.pumpAndSettle();
    expect(find.text('Game metadata'), findsOneWidget);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(provider.calls, isEmpty);
    final enabledSave = find.byKey(const ValueKey('metadata-save'));
    final saveMaterial = tester.widget<Material>(
        find.descendant(of: enabledSave, matching: find.byType(Material)));
    final saveLabel = tester
        .element(find.descendant(of: enabledSave, matching: find.byType(Text)));
    expect(saveMaterial.color, const Color(0xFFC62828));
    expect(DefaultTextStyle.of(saveLabel).style.color, Colors.white);
    final contrast = (Colors.white.computeLuminance() + 0.05) /
        (saveMaterial.color!.computeLuminance() + 0.05);
    expect(contrast, greaterThanOrEqualTo(4.5));
    final forget = find.byKey(const ValueKey('metadata-forget'));
    expect(tester.widget<FilledButton>(forget).onPressed, isNull);
    final forgetLabel = tester
        .element(find.descendant(of: forget, matching: find.byType(Text)));
    expect(
        DefaultTextStyle.of(forgetLabel).style.color!.toARGB32(),
        Theme.of(forgetLabel)
            .colorScheme
            .onSurface
            .withValues(alpha: 0.38)
            .toARGB32());
    await tester.ensureVisible(find.byKey(const ValueKey('metadata-save')));
    await tester.tap(find.byKey(const ValueKey('metadata-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Complete all required fields'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('metadata-username')), 'fixture-user');
    await tester.enterText(
        find.byKey(const ValueKey('metadata-password')), 'fixture-secret');
    final save = find.byKey(const ValueKey('metadata-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await ss.readUser())!.username, 'fixture-user');
    expect(find.text('fixture-secret'), findsNothing);
    expect(provider.calls, isEmpty);
    final refresh = find.byKey(const ValueKey('metadata-refresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await controls.pause();
    await tester.pumpAndSettle();
    // If pause won the lookup boundary, resume the same job to completion.
    if (controls.state.report!.state != 'completed') {
      await controls.resume();
      await tester.pumpAndSettle();
    }
    expect(controls.state.report!.state, 'completed');
    expect(controls.state.report!.counts, {'unmatched': 2});
    expect(find.textContaining('does not mean every game'), findsOneWidget);
    expect(tester.takeException(), isNull);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('metadata-provider')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'metadata form and committed coverage preserve dark layout geometry',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // SQLite's asynchronous lock/future ownership must stay in the real zone
    // when its complete operation is awaited through runAsync below.
    final db = (await tester.runAsync(controlsDatabase))!;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final secrets = MemorySecrets();
    final controls = (await tester.runAsync(() async {
      final controls = MetadataControlsController(
          database: Future.value(db),
          providers: {'screenscraper': ControlsProvider()},
          screenScraperCredentials:
              ScreenScraperCredentialStore(storage: secrets),
          igdbCredentials: IgdbCredentialStore(storage: secrets),
          catalogueChanged: () {});
      await controls.load();
      return controls;
    }))!;
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      metadataControlsProvider.overrideWith((_) => controls),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: const MetadataSettingsScreen())));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MetadataSettingsScreen),
        matchesGoldenFile('goldens/metadata_settings_setup.png'));
    await tester.runAsync(() => controls.refresh());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('does not mean every game'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MetadataSettingsScreen),
        matchesGoldenFile('goldens/metadata_settings_progress.png'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await controls.close();
    container.dispose();
    await db.close();
  });
}
