import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/features/settings/widgets/general_tab.dart';
import 'package:retro_eshop/features/settings/media_settings_screen.dart';
import 'package:retro_eshop/services/socket_media_import.dart';
import '../helpers/pump_helpers.dart';

void main() {
  testWidgets('Media settings starts flat and persists reduced motion',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    const channel = MethodChannel('com.retro.rshop/socket_import');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel,
            (call) async => call.method == 'startupCleanup' ? false : null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await storage.init();
    const parent = String.fromEnvironment('RSHOP_IMPORT_TEST_ROOT');
    final root = (await tester.runAsync(() async {
      final folder = parent.isEmpty
          ? Directory.systemTemp
          : await Directory(parent).create(recursive: true);
      return folder.createTemp('rshop-media-settings-');
    }))!;
    addTearDown(() => root.delete(recursive: true));
    final importer = SocketMediaImport(directory: root);
    await tester.runAsync(importer.initialize);
    final container = ProviderContainer(overrides: [
      storageServiceProvider.overrideWithValue(storage),
      socketMediaImportProvider.overrideWith((ref) => importer),
    ]);
    addTearDown(container.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: createTestApp(SettingsGeneralTab(firstFocusNode: focus))));
    await tester.pumpAndSettle();
    expect(container.read(mediaPresentationProvider),
        (enabled: false, reducedMotion: false));
    await tester.scrollUntilVisible(find.text('Media previews'), 200);
    await tester.ensureVisible(find.text('Media previews'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Media previews'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaSettingsScreen), findsOneWidget);
    expect(container.read(mediaPresentationProvider).enabled, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-enable-3d')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-enable-3d')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('media-enable-3d')))
            .onChanged,
        isNull);
    await tester.tap(find.byKey(const ValueKey('media-reduced-motion')));
    await tester.pumpAndSettle();
    expect(container.read(mediaPresentationProvider).reducedMotion, isTrue);
    final reopened = StorageService();
    await reopened.init();
    final fresh = MediaPresentationNotifier(reopened);
    addTearDown(fresh.dispose);
    expect(fresh.state, (enabled: false, reducedMotion: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    expect(find.text('Blur'), findsOneWidget);
    await tester.tap(find.byType(Slider).first);
    await tester.pumpAndSettle();
    final blur = storage.getPreviewSettings().blur;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(storage.getPreviewSettings().blur, greaterThan(blur),
        reason:
            'Controller arrows must adjust the focused slider, not leave it');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
