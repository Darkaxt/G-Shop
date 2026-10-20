import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/preview/game_watch_preview.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/widgets/base_game_card.dart';

void main() {
  testWidgets(
      'library uses the exact handheld; only selected cards have subtle motion',
      (tester) async {
    Widget card(bool selected) => ProviderScope(
        child: MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: Scaffold(
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
                        accentColor: Colors.red,
                        onTap: () {})))));
    await tester.pumpWidget(card(true));
    final preview =
        tester.widget<GameWatchPreview>(find.byType(GameWatchPreview));
    expect(preview.filename, 'Mario Bros. (World).7z');
    expect(preview.transparentBackground, true);
    expect(preview.reducedMotion, false);
    expect(find.byKey(const ValueKey('game-card-caption')), findsOneWidget);
    await tester.pumpWidget(card(false));
    expect(
        tester
            .widget<GameWatchPreview>(find.byType(GameWatchPreview))
            .reducedMotion,
        true);
    await tester.pumpWidget(const SizedBox());
  });
}
