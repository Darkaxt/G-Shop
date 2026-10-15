import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/core/input/input.dart';
import 'package:retro_eshop/features/settings/settings_screen.dart';
import 'package:retro_eshop/features/settings/widgets/settings_tabs.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/download_providers.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/services/input_debouncer.dart';
import 'package:retro_eshop/features/library/shelf_edit_screen.dart';
import 'package:retro_eshop/features/library/widgets/shelf_picker_dialog.dart';
import 'package:retro_eshop/features/game_detail/widgets/game_detail_overlay.dart';
import 'package:retro_eshop/models/custom_shelf.dart';
import 'package:retro_eshop/models/game_metadata_info.dart';
import 'package:retro_eshop/utils/game_metadata.dart';
import 'package:retro_eshop/features/settings/config_mode_screen.dart';
import 'package:retro_eshop/features/onboarding/onboarding_screen.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/services/config_storage_service.dart';
import '../helpers/pump_helpers.dart';

// These tests exercise route/shortcut ownership, not wall-clock rate limiting
// (covered separately by input_debouncer_test.dart).
class _ImmediateInput extends InputDebouncer {
  @override
  bool canPerformAction() => true;
}

class _ConfigPicker extends FilePicker {
  int calls = 0;
  @override
  Future<FilePickerResult?> pickFiles({String? dialogTitle,
      String? initialDirectory, FileType type = FileType.any,
      List<String>? allowedExtensions, Function(FilePickerStatus)? onFileLoading,
      bool allowCompression = true, int compressionQuality = 30,
      bool allowMultiple = false, bool withData = false,
      bool withReadStream = false, bool lockParentWindow = false,
      bool readSequential = false}) async {
    expect(type, FileType.custom);
    expect(allowedExtensions, ['json']);
    calls++;
    return null; // Cancel at the OS-owned picker boundary; change no settings.
  }
}

class _ConfigStorage extends ConfigStorageService {
  int exports = 0;
  @override
  Future<AppConfig?> loadConfig() async => AppConfig.empty;
  @override
  Future<void> exportConfig(AppConfig config) async => exports++;
}

void main() {
  // Widget tests do not register the operating system's FilePicker plugin.
  setUpAll(() => FilePicker.platform = _ConfigPicker());
  for (final configuration in [true, false]) {
    testWidgets('${configuration ? 'configuration' : 'welcome'} controller import/export matches its HUD',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final config = _ConfigStorage(), picker = _ConfigPicker();
      final priorPicker = FilePicker.platform;
      FilePicker.platform = picker;
      addTearDown(() => FilePicker.platform = priorPicker);
      await tester.pumpWidget(ProviderScope(overrides: [
        storageServiceProvider.overrideWithValue(storage),
        configStorageServiceProvider.overrideWithValue(config),
        bootstrappedConfigProvider.overrideWith((_) async => AppConfig.empty),
        hasQueueItemsProvider.overrideWithValue(false),
      ], child: GlobalInputWrapper(child: createTestApp(configuration
          ? const ConfigModeScreen() : const OnboardingScreen()))));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonSelect);
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      if (configuration) {
        await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
        await tester.pumpAndSettle();
        expect(config.exports, 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  test('deferred restoration cannot write into a closed app scope', () {
    final owner = FocusStateManager();
    owner.dispose();
    expect(() => owner.saveFocusState('closed-route', selectedIndex: 1),
        returnsNormally);
  });

  testWidgets(
      'settings headers activate by D-pad and A; L1 R1 retain ownership',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'R-Shop',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    final storage = StorageService();
    await storage.init();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          hasQueueItemsProvider.overrideWithValue(false),
          inputDebouncerProvider.overrideWith((_) => _ImmediateInput()),
        ],
        child:
            GlobalInputWrapper(child: createTestApp(const SettingsScreen()))));
    await tester.pumpAndSettle();
    expect(
        tester.widget<SettingsTabs>(find.byType(SettingsTabs)).selectedTab, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    expect(
        tester.widget<SettingsTabs>(find.byType(SettingsTabs)).selectedTab, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
    await tester.pumpAndSettle();
    expect(
        tester.widget<SettingsTabs>(find.byType(SettingsTabs)).selectedTab, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    final labels = ['GENERAL', 'AUDIO', 'ADVANCED', 'ABOUT'];
    bool focused(String label) =>
        Focus.of(tester.element(find.text(label))).hasFocus;
    expect(labels.any(focused), isTrue);
    // Directional traversal chooses the geometrically nearest header, which
    // depends on viewport width. Walk its actual row to Audio, then activate.
    while (!focused('AUDIO')) {
      final index = labels.indexWhere(focused);
      await tester.sendKeyEvent(index > 1
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(labels.indexWhere(focused), isNot(index));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(
        tester.widget<SettingsTabs>(find.byType(SettingsTabs)).selectedTab, 1);
    // The swapped content is still inside this page's Actions, not the route's
    // parent focus scope. A second bumper must continue switching sections.
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    expect(
        tester.widget<SettingsTabs>(find.byType(SettingsTabs)).selectedTab, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('Material dialogs and dropdown routes own A B and return focus',
      (tester) async {
    var accepted = 0;
    final launcher = FocusNode();
    addTearDown(launcher.dispose);
    await tester.pumpWidget(ProviderScope(
        child: GlobalInputWrapper(
            child: createTestApp(Builder(
                builder: (context) => ScreenActionsWrapper(
                      materialControls: true,
                      child: FocusScope(
                          child: Column(children: [
                        TextButton(
                            focusNode: launcher,
                            autofocus: true,
                            onPressed: () => showConsoleDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                        title: const Text('Edit'),
                                        actions: [
                                          TextButton(
                                              onPressed: () {
                                                accepted++;
                                                Navigator.pop(context);
                                              },
                                              child: const Text('Save'))
                                        ])),
                            child: const Text('Open')),
                        DropdownButton<String>(
                            value: 'one',
                            items: const [
                              DropdownMenuItem(
                                  value: 'one', child: Text('One')),
                              DropdownMenuItem(
                                  value: 'two', child: Text('Two')),
                            ],
                            onChanged: (_) => accepted++),
                      ])),
                    ))))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Save'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(accepted, 1);
    expect(launcher.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(accepted, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsNothing);
    expect(accepted, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('shelf editor scrolls selection and removes a rule with X',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: GlobalInputWrapper(
            child: createTestApp(ShelfEditScreen(
                shelf: CustomShelf(
          id: 'fixture',
          name: 'Fixture',
          createdAt: DateTime.utc(2026),
          filterRules: [
            for (var i = 0; i < 15; i++) ShelfFilterRule(textQuery: 'Rule $i')
          ],
        ))))));
    await tester.pumpAndSettle();
    for (var i = 0; i < 15; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(find.text('"Rule 14"').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
    await tester.pumpAndSettle();
    expect(find.text('"Rule 14"'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('shelf picker scrolls to an offscreen choice and confirms by A',
      (tester) async {
    String? selected;
    await tester.pumpWidget(ProviderScope(
        child: GlobalInputWrapper(
            child: createTestApp(Consumer(
                builder: (context, ref, _) => TextButton(
                    onPressed: () => showShelfPickerDialog(
                        context: context,
                        ref: ref,
                        shelves: [
                          for (var i = 0; i < 25; i++)
                            CustomShelf(
                                id: '$i',
                                name: 'Shelf $i',
                                createdAt: DateTime.utc(2026))
                        ],
                        onSelect: (id) => selected = id),
                    child: const Text('Choose')))))));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 24; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(find.text('Shelf 24').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(selected, '24');
    expect(find.text('Shelf 24'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('long Game Info scrolls with D-pad and closes with B',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closed = false;
    await tester.pumpWidget(ProviderScope(
        child: GlobalInputWrapper(
            child: createTestApp(GameDetailOverlay(
                gameTitle: 'Fixture',
                accentColor: Colors.red,
                fileMetadata: GameMetadata.parse('Fixture (USA).gba'),
                richMetadata: GameMetadataInfo(
                    filename: 'Fixture.gba',
                    systemSlug: 'gba',
                    lastUpdated: 0,
                    summary:
                        List.filled(80, 'Long game information.').join('\n')),
                onClose: () => closed = true)))));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.pixels, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
