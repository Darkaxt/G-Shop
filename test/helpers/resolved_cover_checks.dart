import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/services/image_cache_service.dart';
import 'package:retro_eshop/widgets/base_game_card.dart';
import 'package:retro_eshop/widgets/media_cover_fallback.dart';
import 'package:retro_eshop/widgets/smart_cover_image.dart';

/// Isolate the real cover cache; never seed the normal app's cache or metadata.
class ResolvedCoverChecks {
  late Directory root;
  late PathProviderPlatform previousPaths;

  Future<void> setUp() async {
    previousPaths = PathProviderPlatform.instance;
    final temporary = await previousPaths.getTemporaryPath();
    root = await Directory(temporary ?? Directory.systemTemp.path)
        .createTemp('rshop-resolved-cover-');
    // Load the normal theme from its existing public font cache before isolating
    // cover storage. FontLoader retains fonts for the lifetime of the engine.
    final support = await previousPaths.getApplicationSupportPath();
    const fonts = [
      'Outfit_600_3b9c6753e282f674c8acfa64c24eba2057c1c123830595cba4e3adbf8c5e9f24.ttf',
      'Outfit_700_8d3a851bbdbcef9f4e7bbee2ffdb74271a80d745c40dbb68888e5759d5976477.ttf',
      'Inter_regular_ecdb53099b1a68cd24c6900ea5beeafec81bd3c8cb9d0f3c51b9986583ba3982.ttf',
      'Inter_600_d7ba633bab7f40576e539a7e934a1301d7618dceea59c743de477c2c493462fc.ttf',
    ];
    for (final font in fonts) {
      final source = File('$support/$font');
      expect(await source.exists(), isTrue,
          reason:
              'Normal font cache required for offline cover fixture: $font');
    }
    AppTheme.darkTheme;
    await GoogleFonts.pendingFonts();
    PathProviderPlatform.instance = _PrivatePaths(root.path);
    GameCoverCacheManager.init();
  }

  Future<void> tearDown() async {
    await GameCoverCacheManager.instance.emptyCache();
    await GameCoverCacheManager.instance.dispose();
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  }

  Future<void> verify(
      String view, WidgetTester tester, Future<void> Function() capture) async {
    final cardFinder = find.byWidgetPredicate(
        (w) => w is BaseGameCard && w.displayName == 'Game 01');
    BaseGameCard card() => tester.widget<BaseGameCard>(cardFinder);
    Finder inside(Type type) =>
        find.descendant(of: cardFinder, matching: find.byType(type));
    expect(inside(MediaCoverFallback), findsOneWidget,
        reason: '$view initially shows original media, not an empty square');
    final before = card();
    final container = ProviderScope.containerOf(tester.element(cardFinder));
    final db = await container.read(libraryDbProvider).database;
    final rows = await db
        .query('games', where: 'displayName = ?', whereArgs: ['Game 01']);
    expect(rows, hasLength(1));
    final row = rows.single;
    final url = 'https://example.invalid/$view-resolved-cover.png';
    final bytes = await rootBundle.load('assets/icon.png');
    await tester.runAsync(() async {
      await GameCoverCacheManager.instance.putFile(url,
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          fileExtension: 'png');
      final columns = await db.rawQuery('PRAGMA table_info(games)');
      if (!columns.any((c) => c['name'] == 'cover_url')) {
        // The minimal Library fixture omits unrelated historical columns.
        await db.execute('ALTER TABLE games ADD COLUMN cover_url TEXT');
      }
      expect(
          await db.update('games', {'cover_url': url},
              where: 'id = ?', whereArgs: [row['id']]),
          1);
    });
    await tester.runAsync(() async {
      if (view == 'console') {
        // Normal console startup reads its persisted cover pointer. Re-open the
        // same synthetic app scope, not a stand-in card or injected controller.
        final app = tester.widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app);
      } else {
        container.read(gameDbChangedProvider.notifier).state++;
      }
      await tester.pumpAndSettle();
      expect(card().cachedUrl, url);
      final provider = CachedNetworkImageProvider(url,
          cacheManager: GameCoverCacheManager.instance);
      final context = tester.element(inside(SmartCoverImage));
      // OctoImage decodes its resized key; its imageBuilder passes the original
      // provider to the real rendered Image. Join both actual decode streams.
      await precacheImage(
          ResizeImage.resizeIfNeeded(card().memCacheWidth, null, provider),
          context);
      await precacheImage(provider, context);
    });
    await tester.pumpAndSettle();
    expect(inside(MediaCoverFallback), findsNothing);
    final images = tester.widgetList<RawImage>(inside(RawImage));
    expect(images.any((image) => image.image != null), isTrue,
        reason: '$view displays decoded pixels, not just an Image wrapper');
    expect(card().displayName, before.displayName);
    expect(card().overallRating?.rating.normalizedValue,
        before.overallRating?.rating.normalizedValue);
    if (view != 'console') expect(card().isSelected, before.isSelected);
    expect(
        find.descendant(
            of: cardFinder,
            matching: find.byKey(const ValueKey('cover-rating'))),
        before.overallRating == null ? findsNothing : findsOneWidget);
    await capture();
    if (view != 'console') {
      // Return the shared normal-screen fixture to its original cover state.
      await db.update('games', {'cover_url': row['cover_url']},
          where: 'id = ?', whereArgs: [row['id']]);
      container.read(gameDbChangedProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(inside(MediaCoverFallback), findsOneWidget);
    }
  }
}

class _PrivatePaths extends PathProviderPlatform {
  final String root;
  _PrivatePaths(this.root);
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}
