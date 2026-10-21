import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:g_shop/models/download_item.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/ra_models.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/metadata/effective_overall_rating.dart';
import 'package:g_shop/widgets/base_game_card.dart';
import '../helpers/pump_helpers.dart';
import 'package:g_shop/widgets/media_cover_fallback.dart';

EffectiveOverallRating score(
    {double value = 90,
    bool stale = false,
    bool original = false,
    String sourceId = 'igdb',
    String sourceLabel = 'IGDB users',
    RatingKind kind = RatingKind.communityAggregate}) {
  final game = GameIdentity(
      id: 'game',
      platformId: 'psx',
      title: 'Test',
      matchStatus: IdentityMatchStatus.manuallyMatched,
      providerIds: {sourceId: '123'});
  final edition = EditionIdentity(
      id: 'edition',
      gameId: game.id,
      tags: original ? {'Undub'} : {'official'});
  final at = DateTime.utc(2026, 10, 3);
  return selectEffectiveOverallRating(
      game: game,
      edition: edition,
      assessedBases: productionOverallScoreBases,
      staleProviderIds: stale ? {sourceId} : {},
      records: [
        MetadataRecord(
            gameId: game.id,
            editionId: edition.id,
            platformId: 'psx',
            providerId: sourceId,
            providerGameId: '123',
            retrievedAt: at,
            refreshGeneration: 1,
            matchMethod: 'verifiedProviderIdGlobalGame',
            titles: [
              const MetadataText(text: 'Test')
            ],
            ratings: [
              SourcedRating.parse(
                  sourceId: sourceId,
                  sourceLabel: sourceLabel,
                  providerGameId: '123',
                  rawValue: value,
                  scaleMinimum: 0,
                  scaleMaximum: 100,
                  voteCount: 100,
                  kind: kind,
                  retrievedAt: at)!
            ])
      ])!;
}

void main() {
  Widget card(EffectiveOverallRating? rating,
          {bool enabled = true,
          bool selected = false,
          bool crowded = false,
          double width = 180,
          Size screen = const Size(1280, 720)}) =>
      createTestApp(
          Center(
              child: SizedBox(
                  width: width,
                  height: width,
                  child: BaseGameCard(
                    displayName:
                        'A long game title with regional and revision information',
                    systemId: 'psx',
                    coverUrls: const [],
                    cachedUrl: null,
                    isInstalled: crowded,
                    isSelected: selected,
                    accentColor: Colors.cyan,
                    onTap: () {},
                    overallRating: rating,
                    showRating: enabled,
                    systemLabel: crowded ? 'PSX' : null,
                    isFavorite: crowded,
                    raAchievementCount: crowded ? 99 : null,
                    raMatchType: RaMatchType.hashVerified,
                    sourceDotColor: crowded ? Colors.green : null,
                    providerLabel: crowded ? 'Drive' : null,
                    variantCount: crowded ? 2 : 0,
                    downloadStatus: crowded ? DownloadStatus.queued : null,
                  ))),
          size: screen);

  testWidgets(
      'source-labelled score is optional; stale and original are explicit',
      (tester) async {
    await tester.pumpWidget(card(score()));
    expect(find.text('9.0'), findsOneWidget);
    expect(find.byKey(const ValueKey('rating-source-igdb')), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
        find.bySemanticsLabel(
            RegExp(r'IGDB users.*Original scale.*100 ratings')),
        findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(card(score(stale: true, original: true)));
    final explanation =
        tester.widget<Tooltip>(find.byType(Tooltip).first).message!;
    expect(explanation, contains('Needs a fresh rating'));
    expect(explanation, contains('Original game'));
    await tester.pumpWidget(card(score(), enabled: false));
    expect(find.text('9.0'), findsNothing);
    expect(find.byKey(const ValueKey('rating-source-igdb')), findsNothing);
    await tester.pumpWidget(card(null));
    expect(find.textContaining('/100'), findsNothing);
  });

  testWidgets('service icon replaces only its own source text offline',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(card(score()));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byKey(const ValueKey('rating-source-igdb')), findsOneWidget);
    expect(find.text('9.0'), findsOneWidget);
    expect(find.textContaining('IGDB'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'IGDB users.*100 ratings')),
        findsOneWidget);
    expect(tester.widget<Tooltip>(find.byType(Tooltip).first).message,
        contains('IGDB users'));
    semantics.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(card(score(
        sourceId: 'screenscraper',
        sourceLabel: 'ScreenScraper',
        kind: RatingKind.unknownAggregate)));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.text('ScreenScraper 90/100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final compact in [true, false]) {
    testWidgets('score shares top edge and height with availability ($compact)',
        (tester) async {
      await tester.pumpWidget(card(score(value: 84),
          crowded: true,
          width: compact ? 100 : 240,
          screen: compact ? const Size(640, 360) : const Size(1280, 720)));
      final rating = tester.getRect(find.byKey(const ValueKey('cover-rating')));
      final availability =
          tester.getRect(find.byKey(const ValueKey('cover-availability')));
      expect(rating.top, closeTo(availability.top, .01));
      expect(rating.height, closeTo(availability.height, .01));
      expect(rating.right, lessThanOrEqualTo(availability.left));
      expect(find.text('8.4'), findsOneWidget);
      expect(find.textContaining('/100'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'rating leaves title, selection and existing badges visible (${compact ? 'compact' : 'large'})',
        (tester) async {
      await tester.pumpWidget(card(score(stale: true, original: true),
          crowded: true,
          selected: true,
          width: compact ? 100 : 240,
          screen: compact ? const Size(640, 360) : const Size(1280, 720)));
      expect(tester.takeException(), isNull);
      // The disc label is painted around its hub; the footer owns the Text node.
      expect(find.textContaining('A long game title'), findsOneWidget);
      expect(find.text('PSX'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.text('99'), findsOneWidget);
      final title =
          tester.getRect(find.textContaining('A long game title').last);
      final badge = tester.getRect(find.byKey(const ValueKey('cover-rating')));
      expect(badge.bottom, lessThanOrEqualTo(title.top));
      final trophy =
          tester.getRect(find.byKey(const ValueKey('achievement-badge')));
      final platform = tester.getRect(find.text('PSX'));
      expect(badge.overlaps(trophy), isFalse,
          reason: 'badge=$badge trophy=$trophy title=$title');
      expect(badge.overlaps(platform), isFalse);
    });
  }

  testWidgets('existing compact footer is constrained even without a score',
      (tester) async {
    await tester.pumpWidget(card(null,
        crowded: true,
        selected: true,
        width: 100,
        screen: const Size(640, 360)));
  });

  testWidgets(
      'cover rating states match the compact and large reference render',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createTestApp(
        RepaintBoundary(
          key: const ValueKey('cover-rating-reference'),
          child: ColoredBox(
              color: Colors.black,
              child: Wrap(spacing: 16, runSpacing: 16, children: [
                for (final compact in [false, true])
                  for (final rating in [
                    score(),
                    score(stale: true, original: true),
                    null
                  ])
                    MediaQuery(
                        data: MediaQueryData(
                            size: compact
                                ? const Size(640, 360)
                                : const Size(1280, 720)),
                        child: SizedBox(
                            width: compact ? 100 : 200,
                            height: compact ? 100 : 200,
                            child: BaseGameCard(
                              displayName:
                                  'Long game title with edition information',
                              systemId: 'psx',
                              coverUrls: const [],
                              cachedUrl: null,
                              isInstalled: true,
                              isSelected: true,
                              isFavorite: true,
                              systemLabel: 'PSX',
                              accentColor: Colors.cyan,
                              onTap: () {},
                              overallRating: rating,
                              raAchievementCount: 99,
                              raMatchType: RaMatchType.hashVerified,
                              sourceDotColor: Colors.green,
                              providerLabel: 'Drive',
                              variantCount: 2,
                            ))),
              ])),
        ),
        size: const Size(1280, 720)));
    await tester.runAsync(() async {
      await precacheImage(AssetImage(mediaFallbackAsset('psx')),
          tester.element(find.byKey(const ValueKey('cover-rating-reference'))));
    });
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const ValueKey('cover-rating-reference')),
        matchesGoldenFile('goldens/cover_rating_states.png'));
  });
}
