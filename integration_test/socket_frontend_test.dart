import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/features/game_detail/widgets/cover_section.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/utils/game_metadata.dart';
import 'package:retro_eshop/widgets/physical_media_view.dart';

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
    await binding.takeScreenshot(name);
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
      expect(find.byType(HandwrittenMediaSticker), findsOneWidget);
      results[format.assetName] = result;
      if ({PhysicalMediaFormat.gameBoyColorDual, PhysicalMediaFormat.vita}
          .contains(format)) {
        await capture('normal-cover-${format.assetName}', tester);
      }
    }
    binding.reportData!['normalCovers'] = results;
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
