import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/providers/library_providers.dart';
import 'package:g_shop/services/metadata/effective_overall_rating.dart';
import 'package:g_shop/widgets/base_game_card.dart';
import 'package:g_shop/widgets/box_face_badges.dart';
import 'package:g_shop/widgets/nes_box_tile.dart';
import '../helpers/pump_helpers.dart';
import 'cover_rating_test.dart' show score;

void main() {
  testWidgets(
      'late NES score and preference changes belong to the carton badge texture',
      (tester) async {
    final rating = Completer<EffectiveOverallRating?>();
    final visible = ValueNotifier(true);
    final selection = <({String platform, String selection})>[];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          cachedSelectionRatingProvider.overrideWith((ref, key) {
            selection.add(key);
            return rating.future;
          }),
        ],
        child: createTestApp(Center(
            child: SizedBox(
                width: 300,
                height: 300,
                child: ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, show, __) => BaseGameCard(
                        displayName: 'Fixture',
                        systemId: 'nes',
                        gameIdentity: 'exact-artifact',
                        filename: 'Fixture.nes',
                        coverUrls: const [],
                        cachedUrl: null,
                        isInstalled: false,
                        isRemoteAvailable: true,
                        isSelected: false,
                        accentColor: Colors.red,
                        showRating: show,
                        onTap: () {})))))));
    expect(tester.widget<NesBoxTile>(find.byType(NesBoxTile)).score, isNull);
    rating.complete(score(value: 84));
    await tester.pump();
    await tester.pump();
    final tile = tester.widget<NesBoxTile>(find.byType(NesBoxTile));
    expect(selection, [(platform: 'nes', selection: 'exact-artifact')]);
    expect(tile.score, isNotNull);
    expect(tile.availability, isNotNull);
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('cover-rating')),
            matching: find.byType(BoxFaceBadges)),
        findsOneWidget);
    visible.value = false;
    await tester.pump();
    expect(tester.widget<NesBoxTile>(find.byType(NesBoxTile)).score, isNull);
    expect(find.byKey(const ValueKey('cover-rating')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
  });

  testWidgets('front texture reserves matching top and bottom corners',
      (tester) async {
    const scoreKey = ValueKey('score'), availableKey = ValueKey('availability');
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox(
                width: 384,
                height: 548,
                child: BoxFaceBadges(
                    score: SizedBox(key: scoreKey, width: 70, height: 30),
                    availability:
                        SizedBox(key: availableKey, width: 30, height: 30))))));
    final front = tester.getRect(find.byType(BoxFaceBadges));
    final score = tester.getRect(find.byKey(scoreKey));
    final availability = tester.getRect(find.byKey(availableKey));
    expect(score.right, closeTo(availability.right, .001));
    expect(score.top, greaterThan(front.top));
    expect(availability.bottom, lessThan(front.bottom));
    expect(score.top, lessThan(availability.top));
    await tester.pumpWidget(const SizedBox());
  });
}
