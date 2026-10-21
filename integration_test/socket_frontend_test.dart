import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:g_shop/core/theme/app_theme.dart';
import 'package:g_shop/features/game_detail/widgets/cover_section.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/utils/game_metadata.dart';
import 'package:g_shop/widgets/physical_media_view.dart';

import '../test/widgets/console_discovery_test.dart'
    show ConsoleOfflineRequests;
import '../test/widgets/library_discovery_test.dart'
    show defineLibraryDiscoveryChecks;

/// Actual CoverSection and Library widgets, native GPU/SQLite and isolated
/// synthetic data. Never bootstraps the production database, ROMs or accounts.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Native model loading and label/GPU completion request their own frames.
  // Keep those frames live while awaiting renderReady, as in the real app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final offline = ConsoleOfflineRequests();
  final previous = HttpOverrides.current;
  var converted = false;
  // integration_test reverts the Android screenshot surface after each test.
  setUp(() => converted = false);
  setUpAll(() async {
    expect(Platform.isAndroid && kDebugMode, isTrue);
    expect((await PackageInfo.fromPlatform()).packageName,
        'com.darkaxt.rshop.sharedproof');
    // Resolve the normal theme's public fonts before blocking cover requests.
    AppTheme.darkTheme;
    await GoogleFonts.pendingFonts();
    HttpOverrides.global = offline;
    binding.reportData = {'productionBootstrap': false, 'romRequests': 0};
  });
  tearDownAll(() => HttpOverrides.global = previous);

  Future<void> capture(String name, WidgetTester tester) async {
    if (!converted) {
      await binding.convertFlutterSurfaceToImage();
      converted = true;
    }
    await tester.pump();
    final png = await binding.takeScreenshot(name);
    if (name == 'normal-cover-nes') {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
      final image = (await codec.getNextFrame()).image;
      try {
        final rgba =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final rect = tester.getRect(find.byType(PhysicalMediaView));
        final factor = image.width /
            (tester.view.physicalSize.width / tester.view.devicePixelRatio);
        final x = ((rect.left + rect.width * .52) * factor).round();
        final y = ((rect.top + rect.height * .74) * factor).round();
        final pixel = (y * image.width + x) * 4;
        final channels = List.generate(3, (i) => rgba.getUint8(pixel + i));
        binding.reportData!['nes-front-lighting-rgb'] = channels;
      } finally {
        image.dispose();
        codec.dispose();
      }
    }
  }

  testWidgets('native normal cover binds every recovered media variant',
      (tester) async {
    const systems = {
      PhysicalMediaFormat.gameBoy: 'gb',
      PhysicalMediaFormat.gameBoyColor: 'gbc',
      PhysicalMediaFormat.gameBoyColorDual: 'gbc',
      PhysicalMediaFormat.gba: 'gba',
      PhysicalMediaFormat.n64: 'n64',
      PhysicalMediaFormat.nes: 'nes',
      PhysicalMediaFormat.snesPal: 'snes',
      PhysicalMediaFormat.snesUs: 'snes',
      PhysicalMediaFormat.nds: 'nds',
      PhysicalMediaFormat.n3ds: 'n3ds',
      PhysicalMediaFormat.switchCard: 'switch',
      PhysicalMediaFormat.genesis: 'megadrive',
      PhysicalMediaFormat.megadrive: 'megadrive',
      PhysicalMediaFormat.psp: 'psp',
      PhysicalMediaFormat.vita: 'psvita',
      PhysicalMediaFormat.disc: 'psx',
    };
    final results = <String, Object?>{};
    for (final format in PhysicalMediaFormat.values) {
      final system = SystemModel.supportedSystems
          .singleWhere((s) => s.id == systems[format]);
      final region = {
        PhysicalMediaFormat.snesPal,
        PhysicalMediaFormat.megadrive
      }.contains(format)
          ? 'Europe'
          : 'USA';
      final game = GameItem(
          filename: 'Renderer sample ($region).rom',
          displayName: 'Renderer sample',
          url: '');
      final key = GlobalKey<PhysicalMediaViewState>();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              backgroundColor: const Color(0xff39070d),
              body: CoverSection(
                  game: game,
                  system: system,
                  physicalMediaKey: key,
                  coverUrls: const [],
                  gbcDualMode: format == PhysicalMediaFormat.gameBoyColorDual
                      ? 'no'
                      : 'yes',
                  reducedMotion: true,
                  metadata: GameMetadata.parse(game.filename)))));
      await tester.pump();
      expect(
          tester
              .widget<PhysicalMediaView>(find.byType(PhysicalMediaView))
              .format,
          format);
      final result = await key.currentState!.renderReady;
      expect(result['error'], isNull, reason: format.name);
      expect(result['frameRendered'], isTrue, reason: format.name);
      expect(result['environmentMipLevels'], 11,
          reason: 'Source HDR studio lighting must reach the actual GPU');
      expect(result['environmentPrefixMipLevels'], 9);
      expect(result['environmentTailTextures'], 2,
          reason:
              'Flutter allocation limits must not discard source tail mips');
      const materialTextureCounts = {
        PhysicalMediaFormat.nes: 2,
        PhysicalMediaFormat.psp: 4,
        PhysicalMediaFormat.snesPal: 3,
        PhysicalMediaFormat.genesis: 3,
        PhysicalMediaFormat.snesUs: 5,
      };
      if (materialTextureCounts.containsKey(format)) {
        expect(result['materialTextures'], materialTextureCounts[format],
            reason: 'Source material maps must reach the native GPU');
      }
      expect(find.byType(HandwrittenMediaSticker), findsOneWidget);
      results[format.assetName] = result;
      if (materialTextureCounts.containsKey(format)) {
        await capture('normal-cover-${format.assetName}', tester);
      }
    }
    binding.reportData!['normalCovers'] = results;
    await tester.pumpWidget(const SizedBox());
    final channels = binding.reportData!['nes-front-lighting-rgb'] as List;
    expect(channels.every((v) => v > 90 && v < 220), isTrue,
        reason: 'Source gray casing must receive direct lighting; '
            'authored front normals must not become ambient-only');
  }, timeout: Timeout.none);

  testWidgets(
      'native selected UMD reuses a cached raster and stays within the frame budget',
      (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    final system =
        SystemModel.supportedSystems.singleWhere((s) => s.id == 'psp');
    const game = GameItem(
        filename: 'Cached raster fixture (USA).iso',
        displayName: 'Cached raster fixture',
        url: '');
    Widget view(String? label) => MaterialApp(
        home: Scaffold(
            backgroundColor: const Color(0xff39070d),
            body: CoverSection(
                game: game,
                system: system,
                physicalMediaKey: key,
                coverUrls: const [],
                physicalLabelUrl: label,
                metadata: GameMetadata.parse(game.filename))));
    await tester.pumpWidget(view(null));
    await tester.pump();
    expect((await key.currentState!.renderReady)['error'], isNull);
    final original = key.currentState;
    // Existing licensed raster is synthetic texture evidence, not a claim of
    // provider matching. App-private fixture disappears with the test APK.
    final raster =
        await rootBundle.load('assets/media_fallbacks/systematic/psp.png');
    final temp =
        await Directory.systemTemp.createTemp('rshop-s12-cached-label-');
    final file = File('${temp.path}/label.png');
    await file.writeAsBytes(
        raster.buffer.asUint8List(raster.offsetInBytes, raster.lengthInBytes));
    await precacheImage(ResizeImage(FileImage(file), width: 640),
        tester.element(find.byType(CoverSection)));
    await tester.pumpWidget(view(file.uri.toString()));
    await tester.pump();
    final ready = await key.currentState!.renderReady;
    expect(ready['error'], isNull);
    expect(ready['labelReady'], isTrue);
    expect(key.currentState, same(original));
    expect(ready['identity'], game.selectionKey);
    expect(find.byType(Image), findsOneWidget);
    binding.reportData!['native-cached-raster-same-identity'] = true;
    await capture('normal-cached-label-psp', tester);

    final frames = <ui.FrameTiming>[];
    final done = Completer<void>();
    void timings(List<ui.FrameTiming> batch) {
      frames.addAll(batch);
      if (frames.length >= 130 && !done.isCompleted) done.complete();
    }

    binding.addTimingsCallback(timings);
    try {
      await done.future;
    } finally {
      binding.removeTimingsCallback(timings);
    }
    final steady = frames.skip(10).take(120).toList();
    int percentile(List<int> values) {
      values.sort();
      return values[(values.length * .95).ceil() - 1];
    }

    final build =
        percentile(steady.map((f) => f.buildDuration.inMicroseconds).toList());
    final rasterTime =
        percentile(steady.map((f) => f.rasterDuration.inMicroseconds).toList());
    final status = await File('/proc/self/status').readAsLines();
    binding.reportData!['native-umd-steady'] = {
      'frames': steady.length,
      'warmupFrames': 10,
      'buildP95Us': build,
      'rasterP95Us': rasterTime,
      'rss': status.where((s) => s.startsWith('VmRSS:')).firstOrNull,
      'scope':
          'isolated native debug UI timings; not physical presentation or whole-library RSS',
    };
    expect(build, lessThan(16667));
    expect(rasterTime, lessThan(16667));
    await tester.pumpWidget(const SizedBox());
  }, timeout: Timeout.none);

  group('native normal Library', () {
    defineLibraryDiscoveryChecks(
        factory: databaseFactory,
        checkpoint: (name, tester) async {
          final media = find.byType(PhysicalMediaView);
          if (media.evaluate().isNotEmpty) {
            final result =
                await tester.state<PhysicalMediaViewState>(media).renderReady;
            expect(result['error'], isNull);
            expect(result['frameRendered'], isTrue);
          }
          binding.reportData![name] = true;
          if (name == 'library-top-10-scope') await capture(name, tester);
        });
  });
}
