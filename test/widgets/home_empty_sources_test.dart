import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:g_shop/features/home/home_view.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/providers/download_providers.dart';
import 'package:g_shop/providers/game_providers.dart';
import 'package:g_shop/services/audio_manager.dart';
import 'package:g_shop/services/storage_service.dart';
import 'package:g_shop/widgets/quick_menu.dart';
import 'package:g_shop/widgets/exit_confirmation_overlay.dart';

import '../helpers/pump_helpers.dart';

class _SilentAudio extends AudioManager {
  @override
  Future<void> startBgm() async {}
}

void main() {
  testWidgets('empty home renders its menu so saved sources remain reachable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await tester.pumpWidget(createTestAppWithProviders(
      const HomeView(),
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        visibleSystemsProvider.overrideWith((ref) async => []),
        bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
        hasQueueItemsProvider.overrideWithValue(false),
        audioManagerProvider.overrideWithValue(_SilentAudio()),
      ],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No consoles configured'), findsOneWidget);
    await tester.tap(find.text('Menu'));
    await tester.pump();
    expect(find.byType(QuickMenuOverlay), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit'));
    await tester.pump();
    expect(find.byType(ExitConfirmationOverlay), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
