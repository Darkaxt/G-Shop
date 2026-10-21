import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/game_list/logic/filter_state.dart';
import 'package:g_shop/features/game_list/widgets/filter_overlay.dart';
import 'package:g_shop/l10n/app_localizations.dart';

void main() {
  testWidgets('existing filter panel offers Top, independent tags and clear',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var filters = const ActiveFilters();
    await tester.pumpWidget(MaterialApp(
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
                body: FilterOverlay(
                    accentColor: Colors.cyan,
                    availableRegions: const [],
                    availableLanguages: const [],
                    selectedRegions: const {},
                    selectedLanguages: const {},
                    favoritesOnly: false,
                    localOnly: false,
                    isLocalSystem: false,
                    onToggleRegion: (_) {},
                    onToggleLanguage: (_) {},
                    onToggleFavorites: () {},
                    onToggleLocal: () {},
                    onClearAll: () =>
                        setState(() => filters = filters.clearAll()),
                    onClose: () {},
                    discoveryFilters: filters,
                    discoveryScope: 'PlayStation',
                    discoveryStatus: 'IGDB users · 20/30 ranked · provisional',
                    availableGenres: const ['Action'],
                    onDiscoveryChanged: (value) =>
                        setState(() => filters = value))))));
    await tester.pumpAndSettle();
    expect(find.textContaining('20/30 ranked'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('discovery-top-10')));
    await tester.pumpAndSettle();
    expect(filters.top, 10);
    for (final tag in ['T-Eng', 'Undub', 'Uncensor']) {
      await tester.ensureVisible(find.byKey(ValueKey('discovery-tag-$tag')));
      await tester.tap(find.byKey(ValueKey('discovery-tag-$tag')));
      await tester.pumpAndSettle();
    }
    expect(filters.selectedTags, {'T-Eng', 'Undub', 'Uncensor'});
    expect(filters.top, 10);
    await tester.ensureVisible(find.byKey(const ValueKey('discovery-match')));
    await tester.tap(find.byKey(const ValueKey('discovery-match')));
    await tester.pumpAndSettle();
    expect(filters.matchAllTags, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
    await tester.pumpAndSettle();
    expect(filters.isEmpty, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
