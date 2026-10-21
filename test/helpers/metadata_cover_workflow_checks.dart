import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/game_detail/widgets/screenshots_carousel.dart';
import 'package:g_shop/providers/library_providers.dart';
import 'package:g_shop/providers/metadata_providers.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';
import 'package:g_shop/widgets/base_game_card.dart';
import 'package:g_shop/widgets/media_cover_fallback.dart';

import '../metadata_controls_test.dart'
    show ControlsArtworkProvider, MemorySecrets;

/// Normal controller -> durable jobs -> shared cache-only callers. The only fake
/// boundary is the provider response; no cover URL/blob is injected into games.
Future<void> verifyMetadataCoverWorkflow(
    String view, WidgetTester tester) async {
  debugPrint('ARTWORK_WORKFLOW $view entered');
  final cardFinder = find.byWidgetPredicate(
      (w) => w is BaseGameCard && w.displayName == 'Game 01');
  BaseGameCard card() => tester.widget<BaseGameCard>(cardFinder);
  final container = ProviderScope.containerOf(tester.element(cardFinder));
  final db = await container.read(libraryDbProvider).database;
  debugPrint('ARTWORK_WORKFLOW $view database');
  final row = (await db
          .query('games', where: 'displayName = ?', whereArgs: ['Game 01']))
      .single;
  final oldCover = row['cover_url'];
  final before = card();
  final cache = await container.read(metadataArtworkCacheProvider);
  debugPrint('ARTWORK_WORKFLOW $view cache');
  final provider = ControlsArtworkProvider(includeScreenshot: true);
  Future<void> verify() async {
    // Producers, SQLite readers and file-image streams share the real-I/O clock.
    final secrets = MemorySecrets();
    MetadataControlsController controller() => MetadataControlsController(
        database: Future.value(db),
        providers: {'screenscraper': provider},
        screenScraperCredentials:
            ScreenScraperCredentialStore(storage: secrets),
        igdbCredentials: IgdbCredentialStore(storage: secrets),
        artworkCache: Future.value(cache),
        catalogueChanged: () =>
            container.read(gameDbChangedProvider.notifier).state++);
    var controls = controller();
    await controls.load();
    debugPrint('ARTWORK_WORKFLOW $view loaded');
    await controls.refresh(cacheRowId: row['id'] as int);
    debugPrint('ARTWORK_WORKFLOW $view refreshed');
    expect(controls.state.report!.counts, {'matched': 1});
    expect(controls.state.artworkReport!.counts, {'matched': 2});
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 2);
    // Join the actual cache-only view read, not pumpAndSettle's frame heuristic.
    await container.read(cachedMetadataCoversProvider(
            view == 'console' ? row['systemSlug'] as String : '')
        .future);
    await container.read(cachedCoverRatingsProvider(
            view == 'console' ? row['systemSlug'] as String : '')
        .future);
    await tester.pumpAndSettle();
    debugPrint('ARTWORK_WORKFLOW $view painted');
    final uri = card().cachedUrl;
    expect(uri, isNotNull, reason: '$view consumes the metadata cache');
    expect(Uri.parse(uri!).scheme, 'file');
    await precacheImage(
        ResizeImage.resizeIfNeeded(card().memCacheWidth, null,
            FileImage(File.fromUri(Uri.parse(uri)))),
        tester.element(cardFinder));
    debugPrint('ARTWORK_WORKFLOW $view cover decoded');
    final metadata = await container.read(libraryDbProvider).getGameMetadata(
        row['artifact_key'] == null
            ? row['filename'] as String
            : 'artifact:${row['artifact_key']}',
        row['systemSlug'] as String,
        artworkCache: cache);
    expect(metadata!.cachedCover, uri);
    expect(metadata.screenshotUrlList, hasLength(1));
    expect(Uri.parse(metadata.screenshotUrlList.single).scheme, 'file');
    debugPrint('ARTWORK_WORKFLOW $view details read');
    final dialog = showDialog<void>(
        context: tester.element(cardFinder),
        builder: (_) => Dialog(
            child: SizedBox(
                width: 500,
                height: 240,
                child: ScreenshotsCarousel(
                    screenshots: metadata.screenshotUrlList,
                    focusedIndex: 0,
                    accentColor: Colors.red,
                    onOpenViewer: () {}))));
    await tester.pumpAndSettle();
    await precacheImage(
        FileImage(File.fromUri(Uri.parse(metadata.screenshotUrlList.single))),
        tester.element(find.byType(Dialog)));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<RawImage>(find.descendant(
                of: find.byType(Dialog), matching: find.byType(RawImage)))
            .any((image) => image.image != null),
        isTrue);
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await dialog;
    debugPrint('ARTWORK_WORKFLOW $view screenshot done');
    await tester.pumpAndSettle();
    expect(
        (await db.query('games', where: 'id = ?', whereArgs: [row['id']]))
            .single['cover_url'],
        oldCover,
        reason: 'No legacy URL mutation hides the missing production link');
    final child = controls.state.artworkReport!.id;
    await controls.close();
    controls.dispose();
    controls = controller();
    await controls.load();
    expect(controls.state.artworkReport!.id, child);
    await controls.resume();
    debugPrint('ARTWORK_WORKFLOW $view restored');
    expect(provider.calls, hasLength(1));
    expect(provider.artworkCalls, 2,
        reason: 'Offline restore repeats no requests');
    await controls.close();
    controls.dispose();
  }

  await verify();
  // Resume also publishes the catalogue change. Join that final normal view
  // refresh before asserting pixels; a frame settling isn't an I/O completion.
  await container.read(cachedMetadataCoversProvider(
          view == 'console' ? row['systemSlug'] as String : '')
      .future);
  await container.read(cachedCoverRatingsProvider(
          view == 'console' ? row['systemSlug'] as String : '')
      .future);
  await precacheImage(
      ResizeImage.resizeIfNeeded(card().memCacheWidth, null,
          FileImage(File.fromUri(Uri.parse(card().cachedUrl!)))),
      tester.element(cardFinder));
  await tester.pumpAndSettle();
  expect(
      find.descendant(
          of: cardFinder, matching: find.byType(MediaCoverFallback)),
      findsNothing);
  expect(
      tester
          .widgetList<RawImage>(
              find.descendant(of: cardFinder, matching: find.byType(RawImage)))
          .any((w) => w.image != null),
      isTrue,
      reason: '$view renders actual decoded cache pixels');
  expect(card().displayName, before.displayName);
  expect(card().overallRating?.rating.normalizedValue,
      before.overallRating?.rating.normalizedValue);
}
