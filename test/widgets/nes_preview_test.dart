import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/preview/nes_media_preview.dart';
import 'package:g_shop/widgets/base_game_card.dart';
import 'package:g_shop/l10n/app_localizations.dart';
import 'cover_rating_test.dart' show score;

void main() {
  testWidgets('unbound hardware waits for resources before revealing metadata',
      (tester) async {
    var ready = 0;
    Widget view(bool resources) => MaterialApp(
        home: Scaffold(
            body: NesMediaPreview(
                filename: 'Fixture (Japan).7z',
                identity: 'fixture',
                title: 'Fixture',
                label: const Text('Label'),
                labelIdentity: 'label',
                reducedMotion: true,
                resourcesReady: resources,
                onReady: () => ready++)));
    await tester.pumpWidget(view(false));
    await tester.pump();
    expect(ready, 0);
    await tester.pumpWidget(view(true));
    await tester.pump();
    expect(ready, 1);
    await tester.pump();
    expect(ready, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('NES reference card retains rating, caption and selection touch',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: Scaffold(
                body: SizedBox(
                    width: 300,
                    height: 300,
                    child: BaseGameCard(
                        systemId: 'nes',
                        gameIdentity: 'fixture',
                        filename: 'Fixture (USA).7z',
                        displayName: 'Fixture',
                        coverUrls: const [],
                        cachedUrl: null,
                        isInstalled: false,
                        isSelected: true,
                        accentColor: Colors.cyan,
                        overallRating: score(stale: false, original: true),
                        onTap: () => tapped = true))))));
    await tester.pump();
    expect(find.byKey(const ValueKey('cover-rating')), findsOneWidget);
    expect(find.byKey(const ValueKey('game-card-caption')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game-card-caption')));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
