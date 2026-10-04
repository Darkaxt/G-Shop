import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/services/image_cache_service.dart';
import 'package:retro_eshop/widgets/base_game_card.dart';
import 'package:retro_eshop/widgets/media_cover_fallback.dart';
import 'package:retro_eshop/widgets/smart_cover_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all supported platforms map explicitly, unknown names remain neutral',
      () {
    expect(platformMediaFamilies.keys.toSet(),
        SystemModel.supportedSystems.map((s) => s.id).toSet());
    for (final platform in [
      'psx',
      'ps2',
      'psp',
      'gba',
      'n64',
      'nds',
      'tg16',
      'fds'
    ]) {
      expect(mediaFallbackAsset(platform),
          'assets/media_fallbacks/systematic/$platform.png');
    }
    for (final unknown in [
      null,
      '',
      'Game (USA).7z',
      'PS2',
      'romspedia',
      '.chd'
    ]) {
      expect(mediaFallbackAsset(unknown),
          'assets/media_fallbacks/systematic/neutral.png');
    }
  });

  test('mixed-media computers do not claim an unverified release medium', () {
    for (final platform in [
      'msx',
      'amstradcpc',
      'atarist',
      'c64',
      'vic20',
      'amiga',
      'zxspectrum',
      'oric',
      'x68000',
      'x1',
      'fmtowns',
      'appleii',
      'dos'
    ]) {
      expect(mediaFallbackAsset(platform),
          'assets/media_fallbacks/systematic/neutral.png',
          reason: platform);
    }
  });

  test('bundled family is real decodable transparent raster artwork', () async {
    for (final family in platformMediaFamilies.values.toSet()) {
      final data = await rootBundle
          .load('assets/media_fallbacks/systematic/$family.png');
      // Use the actual Flutter decoder, including the upstream 16-bit
      // grayscale-alpha PNGs. image 4.3.0's PixelUint16.a incorrectly reports
      // zero for two-channel grayscale-alpha data; the source PNG is valid.
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(
          data.offsetInBytes, data.lengthInBytes));
      final image = (await codec.getNextFrame()).image;
      try {
        expect(image.width, 256, reason: family);
        expect(image.height, 256, reason: family);
        final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        expect(rgba.getUint8(3), 0, reason: 'Transparent margin: $family');
        var visible = false;
        for (var alpha = 3; alpha < rgba.lengthInBytes; alpha += 4) {
          if (rgba.getUint8(alpha) > 0) {
            visible = true;
            break;
          }
        }
        expect(visible, isTrue, reason: 'Not an empty transparent file: $family');
      } finally {
        image.dispose();
        codec.dispose();
      }
    }
  });

  test('bundled PNGs are unchanged pinned Systematic content icons', () async {
    final manifest = jsonDecode(await rootBundle
            .loadString('assets/media_fallbacks/systematic/SOURCES.json'))
        as Map<String, dynamic>;
    expect(manifest['revision'], 'b177f250e42948708e753d30809bd4dd9c0a2cdc');
    final sources = manifest['assets'] as Map<String, dynamic>;
    expect(sources.keys.toSet(), platformMediaFamilies.values.toSet());
    for (final entry in sources.entries) {
      final source = entry.value as Map<String, dynamic>;
      expect(source['path'], startsWith('xmb/systematic/png/'));
      expect(source['path'], endsWith('-content.png'));
      final data = await rootBundle
          .load('assets/media_fallbacks/systematic/${entry.key}.png');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(
          sha1.convert([
            ...utf8.encode('blob ${bytes.length}\u0000'),
            ...bytes
          ]).toString(),
          source['git_blob_sha1'],
          reason: entry.key);
    }
  });

  test(
      'artwork attribution and complete license are bundled for offline access',
      () async {
    final entries = await mediaArtworkLicenses().toList();
    expect(entries, hasLength(1));
    expect(entries.single, isA<LicenseEntryWithLineBreaks>());
    expect(entries.single.packages, ['Systematic media icons']);
    final text = entries.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('libretro/retroarch-assets'));
    expect(text, contains('CC BY 4.0'));
    expect(text, contains('Systematic / RetroActive theme contributors'));
    expect(text, contains('Modifications: PNG filenames renamed'));
    expect(text, contains('Section 5 -- Disclaimer of Warranties'));
  });

  testWidgets('loading suppression and failed URLs use the same platform asset',
      (tester) async {
    const url = 'https://example.invalid/no-cover.png';
    final suppressed = ValueNotifier(true);
    addTearDown(suppressed.dispose);
    addTearDown(FailedUrlsCache.instance.clear);
    Widget cover() => MaterialApp(
        home: SizedBox(
            width: 180,
            height: 240,
            child: SmartCoverImage(
                systemId: 'psp',
                urls: const [url],
                scrollSuppression: suppressed)));
    await tester.pumpWidget(cover());
    expect(
        tester
            .widget<MediaCoverFallback>(find.byType(MediaCoverFallback))
            .systemId,
        'psp');
    FailedUrlsCache.instance.markFailed(url);
    await tester.pumpWidget(const SizedBox());
    suppressed.value = false;
    await tester.pumpWidget(cover());
    expect(
        tester
            .widget<MediaCoverFallback>(find.byType(MediaCoverFallback))
            .systemId,
        'psp');
    expect(find.byIcon(Icons.broken_image), findsNothing);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).width, 256,
        reason: 'Bundled PNG decoding remains bounded per shared asset');
  });

  testWidgets('explicit caller placeholder/error contract is preserved',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: SmartCoverImage(urls: [], errorWidget: Text('caller fallback'))));
    expect(find.text('caller fallback'), findsOneWidget);
    expect(find.byType(MediaCoverFallback), findsNothing);
  });

  testWidgets('missing cover uses bundled game media rather than black error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 180,
          height: 180,
          child: BaseGameCard(
            displayName: 'Unknown game.7z',
            coverUrls: const [],
            cachedUrl: null,
            isInstalled: false,
            isSelected: true,
            accentColor: Colors.teal,
            onTap: () {},
          ),
        ),
      ),
    ));
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.image is ResizeImage &&
            ((widget.image as ResizeImage).imageProvider as AssetImage)
                    .assetName ==
                'assets/media_fallbacks/systematic/neutral.png'),
        findsOneWidget);
    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(find.text('Unknown game.7z'), findsOneWidget);
  });

  testWidgets('decoded cached cover replaces media fallback without requests',
      (tester) async {
    const url = 'https://example.invalid/verified-cover.png';
    final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('rshop-cover-replacement-'));
    final previousPaths = PathProviderPlatform.instance;
    final previousHttp = HttpOverrides.current;
    final offline = _NoNetwork();
    PathProviderPlatform.instance = _FixturePaths(root!.path);
    HttpOverrides.global = offline;
    // Cache construction starts filesystem futures; keep those in the real IO
    // zone too, rather than awaiting a fake-clock future from runAsync.
    final cache =
        (await tester.runAsync(() async => GameCoverCacheManager.instance))!;
    addTearDown(() async {
      await cache.emptyCache();
      await cache.dispose();
      PathProviderPlatform.instance = previousPaths;
      HttpOverrides.global = previousHttp;
      await root.delete(recursive: true);
    });
    final bytes = await rootBundle.load('assets/icon.png');
    await tester.runAsync(() => cache.putFile(
        url, bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        fileExtension: 'png'));
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(
        home: SmartCoverImage(
            systemId: 'psx',
            urls: [url],
            cachedUrl: url,
            width: 180,
            height: 240),
      ));
      expect(find.byType(MediaCoverFallback), findsOneWidget,
          reason: 'No empty frame while cache validation/decode is pending');
      await precacheImage(CachedNetworkImageProvider(url, cacheManager: cache),
          tester.element(find.byType(SmartCoverImage)));
    });
    await tester.pumpAndSettle();
    expect(find.byType(MediaCoverFallback), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull,
        reason: 'A decoded cover, not an empty Image wrapper, is visible');
    expect(offline.attempts, isEmpty,
        reason: 'Bundled fallback and a valid cache need no network request');
    await tester.pumpWidget(const SizedBox());
  });
}

class _FixturePaths extends PathProviderPlatform {
  final String root;
  _FixturePaths(this.root);
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _NoNetwork extends HttpOverrides {
  final attempts = <Uri>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RejectClient(attempts);
}

class _RejectClient implements HttpClient {
  final List<Uri> attempts;
  _RejectClient(this.attempts);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    attempts.add(url);
    return Future.error(
        const SocketException('Cover fixture must remain offline'));
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
