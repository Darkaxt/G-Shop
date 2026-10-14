import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/features/settings/widgets/general_tab.dart';
import '../helpers/pump_helpers.dart';

void main() {
  testWidgets('Display toggles persist classic view and reduced motion',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)]);
    addTearDown(container.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: createTestApp(SettingsGeneralTab(firstFocusNode: focus))));
    await tester.pumpAndSettle();
    expect(container.read(mediaPresentationProvider),
        (enabled: true, reducedMotion: false));
    await tester.scrollUntilVisible(find.text('3D MEDIA'), 200);
    await tester.tap(find.text('3D MEDIA'));
    await tester.pumpAndSettle();
    expect(container.read(mediaPresentationProvider).enabled, isFalse);
    await tester.scrollUntilVisible(find.text('REDUCED MOTION'), 200);
    await tester.tap(find.text('REDUCED MOTION'));
    await tester.pumpAndSettle();
    expect(container.read(mediaPresentationProvider).reducedMotion, isTrue);
    final reopened = StorageService();
    await reopened.init();
    final fresh = MediaPresentationNotifier(reopened);
    addTearDown(fresh.dispose);
    expect(fresh.state, (enabled: false, reducedMotion: true));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
