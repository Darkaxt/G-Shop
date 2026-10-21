import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/preview/game_watch_preview.dart';
import 'package:g_shop/l10n/app_localizations.dart';
import 'package:g_shop/widgets/base_game_card.dart';
import 'package:g_shop/widgets/library_model_presentation.dart';

void main() {
  testWidgets(
      'handheld library shares GBA sweep and halo, preserving card touch',
      (tester) async {
    var taps = 0;
    Widget card(bool selected,
            {bool reduced = false, bool systemReduced = false}) =>
        ProviderScope(
            child: MaterialApp(
                localizationsDelegates: L.localizationsDelegates,
                supportedLocales: L.supportedLocales,
                home: MediaQuery(
                    data: MediaQueryData(disableAnimations: systemReduced),
                    child: Scaffold(
                        body: SizedBox(
                            width: 360,
                            height: 300,
                            child: BaseGameCard(
                                systemId: 'gameandwatch',
                                filename: 'Mario Bros. (World).7z',
                                gameIdentity: 'owned-game',
                                displayName: 'Mario Bros.',
                                coverUrls: const [],
                                cachedUrl: null,
                                isInstalled: false,
                                isSelected: selected,
                                reducedMotion: reduced,
                                accentColor: Colors.red,
                                onTap: () {
                                  taps++;
                                }))))));
    await tester.pumpWidget(card(true));
    final preview =
        tester.widget<GameWatchPreview>(find.byType(GameWatchPreview));
    expect(preview.filename, 'Mario Bros. (World).7z');
    expect(preview.transparentBackground, true);
    expect(preview.reducedMotion, false);
    expect(find.byKey(const ValueKey('library-model-selection-halo')),
        findsOneWidget,
        reason: 'G&W must share the GBA 3D library selection presentation');
    expect(find.byType(LibraryModelPresentation), findsOneWidget);
    final mountedPreview = tester.state(find.byType(GameWatchPreview));
    double yaw() => tester
        .widget<GameWatchPreview>(find.byType(GameWatchPreview))
        .libraryPose!
        .ry;
    expect(yaw(), closeTo(-math.pi / 6, .0001));
    await tester.pump(const Duration(seconds: 2));
    expect(yaw(), closeTo(0, .0001));
    await tester.pump(const Duration(seconds: 2));
    expect(yaw(), closeTo(math.pi / 6, .0001));
    await tester.tapAt(tester.getCenter(find.byType(GameWatchPreview)));
    await tester.pump();
    expect(taps, 1,
        reason: 'The rendered handheld area must activate its library card');
    expect(find.byKey(const ValueKey('game-card-caption')), findsOneWidget);
    await tester.pumpWidget(card(false));
    expect(tester.state(find.byType(GameWatchPreview)), same(mountedPreview),
        reason: 'Changing selection must not remount/reload the handheld');
    expect(find.byKey(const ValueKey('library-model-selection-halo')),
        findsNothing);
    final still = yaw();
    await tester.pump(const Duration(seconds: 2));
    expect(yaw(), still);
    expect(
        tester
            .widget<GameWatchPreview>(find.byType(GameWatchPreview))
            .reducedMotion,
        true);
    for (final systemReduced in [false, true]) {
      await tester.pumpWidget(
          card(true, reduced: !systemReduced, systemReduced: systemReduced));
      expect(tester.state(find.byType(GameWatchPreview)), same(mountedPreview));
      final reducedYaw = yaw();
      await tester.pump(const Duration(seconds: 2));
      expect(yaw(), reducedYaw);
      expect(find.byKey(const ValueKey('library-model-selection-halo')),
          findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
