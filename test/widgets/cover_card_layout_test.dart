import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/models/download_item.dart';
import 'package:retro_eshop/models/ra_models.dart';
import 'package:retro_eshop/widgets/base_game_card.dart';
import 'package:retro_eshop/widgets/media_cover_fallback.dart';

import 'cover_rating_test.dart' show score;

const _title = 'A very long game title with regional and revision information';
const _provider = 'A long Google Drive source label';

void main() => defineCoverCardLayoutChecks();

/// Same shared-card layout on the host and Android; no bootstrap, cache, account
/// or network image is involved. Use the real localized badge components.
void defineCoverCardLayoutChecks({
  bool native = false,
  Future<void> Function(String name, WidgetTester tester)? checkpoint,
  void Function(String check)? verified,
}) {
  Future<void> open(WidgetTester tester,
      {required bool compact,
      required bool selected,
      Locale locale = const Locale('en'),
      double textScale = 1,
      bool footer = true,
      DownloadStatus? download,
      RaMatchType achievement = RaMatchType.hashVerified,
      bool mastered = false}) async {
    if (!native) {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      locale: locale,
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
            size: compact ? const Size(640, 360) : const Size(1280, 720),
            textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: compact ? 100 : 240,
              child: BaseGameCard(
                displayName: _title,
                systemId: 'n64',
                coverUrls: const [],
                cachedUrl: null,
                isInstalled: true,
                isSelected: selected,
                isFavorite: true,
                systemLabel: 'N64',
                accentColor: Colors.cyan,
                onTap: () {},
                overallRating: score(stale: true, original: true),
                raAchievementCount: 99,
                raMatchType: achievement,
                isMastered: mastered,
                sourceDotColor: Colors.blue,
                sourceDotBorrowed: true,
                extraSourceDots: const [
                  SourceDotData(color: Colors.green),
                  SourceDotData(color: Colors.purple),
                  SourceDotData(color: Colors.orange), // Existing cap: 3 total.
                ],
                providerLabel: footer ? _provider : null,
                variantCount: footer ? 12 : 0,
                downloadStatus: download,
                downloadProgress: 0.5,
              ),
            ),
          ),
        ),
      ),
    ));
    // Real bounded reveal animation; indeterminate transfer states continue to
    // animate, so pumpAndSettle would incorrectly wait for transfer completion.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  void checkGeometry(WidgetTester tester, {required bool footer}) {
    expect(tester.takeException(), isNull);
    expect(find.byType(MediaCoverFallback), findsOneWidget);
    final title = tester.getRect(find.text(_title));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(_title));
    // Android's selection rectangles retain fractional font metrics while its
    // paragraph line boxes round to logical pixels. Selection-box height is not
    // the paint/clipping boundary (RenderParagraph uses TextPainter.size).
    // Compare against a complete first line using the actual inherited font,
    // locale and paragraph configuration, not Ahem or a glyph selection box.
    final firstLine = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      textHeightBehavior: paragraph.textHeightBehavior,
      maxLines: 1,
      ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
    )..layout(maxWidth: paragraph.size.width);
    final firstLineHeight = firstLine.height;
    firstLine.dispose();
    expect(paragraph.size.height + precisionErrorTolerance,
        greaterThanOrEqualTo(firstLineHeight),
        reason: 'The title must paint a full first line, not merely exist');
    final rating = tester.getRect(find.byKey(const ValueKey('cover-rating')));
    expect(find.byKey(const ValueKey('rating-source-igdb')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cover-rating')),
            matching: find.textContaining('IGDB')),
        findsNothing);
    final trophy =
        tester.getRect(find.byKey(const ValueKey('achievement-badge')));
    // The borrowed primary dot's nearest Row is the complete capped dot group.
    final sourceDots = tester.getRect(find
        .ancestor(of: find.byIcon(Icons.share), matching: find.byType(Row))
        .first);
    expect(sourceDots.top + precisionErrorTolerance,
        greaterThanOrEqualTo(title.bottom),
        reason: 'Source indicators must not obscure title glyphs: '
            'dots=$sourceDots title=$title');
    expect(sourceDots.overlaps(rating), isFalse);
    expect(rating.overlaps(trophy), isFalse,
        reason: 'rating=$rating trophy=$trophy title=$title dots=$sourceDots');
    expect(rating.bottom, lessThanOrEqualTo(title.top));
    if (footer) {
      expect(sourceDots.left + precisionErrorTolerance,
          greaterThanOrEqualTo(tester.getRect(find.text(_provider)).right),
          reason: 'Source indicators need their own footer space');
    }
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('N64'), findsOneWidget);
    expect(find.text('99'), findsOneWidget);
  }

  testWidgets('source indicators never overlap title or provider footer',
      (tester) async {
    for (final compact in [true, false]) {
      for (final selected in [false, true]) {
        for (final footer in [true, false]) {
          await open(tester,
              compact: compact, selected: selected, footer: footer);
          checkGeometry(tester, footer: footer);
        }
      }
    }
    await checkpoint?.call('cover-source-indicators', tester);
    await tester.pumpWidget(const SizedBox());
    verified?.call('source_indicators_title_footer_geometry');
  });

  testWidgets(
      'localized installed and rating badges fit compact and large cards',
      (tester) async {
    for (final locale in L.supportedLocales) {
      for (final compact in [true, false]) {
        await open(tester,
            compact: compact, selected: true, locale: locale, textScale: 1.3);
        checkGeometry(tester, footer: true);
        final l = L.of(tester.element(find.byType(BaseGameCard)));
        expect(find.text(l.common_installed), findsOneWidget);
        expect(find.textContaining(l.metadata_staleScore), findsOneWidget);
        expect(find.textContaining(l.metadata_originalGame), findsOneWidget);
      }
    }
    await checkpoint?.call('cover-localized-badges', tester);
    await tester.pumpWidget(const SizedBox());
    verified?.call('six_locale_compact_large_badges');
  });

  testWidgets('active transfer overlays preserve shared card badges and title',
      (tester) async {
    for (final status in DownloadStatus.values) {
      if (status.isTerminal) continue;
      await open(tester,
          compact: true,
          selected: true,
          download: status,
          achievement: RaMatchType.hashIncompatible,
          mastered: true);
      checkGeometry(tester, footer: true);
      switch (status) {
        case DownloadStatus.queued:
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
        case DownloadStatus.downloading:
          expect(find.text('50%'), findsOneWidget);
        case DownloadStatus.paused:
          expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
        case DownloadStatus.awaitingAuthorization:
          expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
        default:
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
      final progress = tester.getRect(switch (status) {
        DownloadStatus.queued => find.byIcon(Icons.schedule_rounded),
        DownloadStatus.downloading => find.text('50%'),
        DownloadStatus.paused => find.byIcon(Icons.pause_rounded),
        DownloadStatus.awaitingAuthorization =>
          find.byIcon(Icons.lock_outline_rounded),
        _ => find.byType(CircularProgressIndicator),
      });
      expect(progress.overlaps(tester.getRect(find.text(_title))), isFalse,
          reason: '$status progress must not be covered by title');
      expect(
          progress.bottom,
          lessThanOrEqualTo(
              tester.getRect(find.byKey(const ValueKey('cover-rating'))).top +
                  precisionErrorTolerance),
          reason: '$status progress must not be covered by rating: '
              '$progress ${tester.getRect(find.byKey(const ValueKey('cover-rating')))}');
    }
    await checkpoint?.call('cover-transfer-badges', tester);
    await tester.pumpWidget(const SizedBox());
    verified?.call('all_active_transfer_badges');
  });
}
