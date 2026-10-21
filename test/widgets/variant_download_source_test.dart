import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/game_detail/widgets/variant_picker_overlay.dart';
import 'package:g_shop/features/game_detail/widgets/version_card.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/services/feedback_service.dart';
import '../helpers/pump_helpers.dart';

class _SilentFeedback implements FeedbackService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final system = SystemModel.supportedSystems.firstWhere((s) => s.id == 'nes');
  const local =
      GameItem(filename: 'Game (USA).nes', displayName: 'Game', url: '');
  final remote = GameItem(
      filename: 'Game (Europe).nes',
      displayName: 'Game',
      url: 'https://example.invalid/game',
      providerConfig:
          const ProviderConfig(type: ProviderType.web, priority: 0));
  for (final input in ['touch', 'controller']) {
    testWidgets('mixed picker rejects unavailable local selection via $input',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final downloads = <int>[];
      final container = ProviderContainer(overrides: [
        feedbackServiceProvider.overrideWithValue(_SilentFeedback())
      ]);
      try {
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: createTestApp(VariantPickerOverlay(
                variants: [local, remote],
                system: system,
                installedStatus: const {},
                onDownload: (index) async {
                  downloads.add(index);
                  return true;
                },
                onDelete: (_) => fail('No installed variant'),
                onClose: () {}))));
        await tester.pumpAndSettle();
        if (input == 'touch') {
          await tester.tap(find.byType(SingleVersionDisplay).first);
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
        }
        await tester.pump();
        expect(downloads, isEmpty);
        expect(find.text('UNAVAILABLE'), findsOneWidget);
        if (input == 'touch') {
          await tester.tap(find.byType(SingleVersionDisplay).last);
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
        }
        await tester.pump();
        expect(downloads, [1]);
        expect(tester.takeException(), isNull);
      } finally {
        // Dispose the overlay and join its deferred claim release while its
        // owning container is still alive, before the binding's final teardown.
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container, child: const SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      }
    });
  }
}
