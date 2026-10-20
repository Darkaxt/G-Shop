import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show instantiateImageCodec;
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/widgets/physical_media_view.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';
import 'package:retro_eshop/widgets/smart_cover_image.dart';
import 'package:retro_eshop/widgets/media_cover_fallback.dart';
import 'package:retro_eshop/features/game_detail/widgets/cover_section.dart';
import 'package:retro_eshop/features/preview/game_watch_preview.dart';
import 'package:retro_eshop/widgets/cover_reveal.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/socket_media_model.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/utils/game_metadata.dart';
import '../helpers/socket_media_oracle.dart';

// Host checks cover binding, artwork roles and the existing launch lifecycle.
// Actual indexed GPU rendering is checked on Android, not inferred from these.
void main() {
  setUpAll(useSocketOracle);
  tearDownAll(() => SocketMediaModel.importedBundle = null);
  testWidgets(
      'integrated handheld bypasses carton reveal and settles honest fallback',
      (tester) async {
    final system =
        SystemModel.supportedSystems.singleWhere((s) => s.id == 'gameandwatch');
    const game = GameItem(
        filename: 'Donkey Kong (World).7z',
        displayName: 'Donkey Kong',
        url: '');
    var ready = 0;
    await tester.pumpWidget(MaterialApp(
        home: CoverSection(
            game: game,
            system: system,
            coverUrls: const [],
            physicalMediaEnabled: true,
            metadata: GameMetadata.parse(game.filename),
            onReady: () => ready++)));
    expect(find.byType(GameWatchPreview), findsOneWidget);
    expect(find.byType(CoverReveal), findsNothing);
    await tester.pump();
    await tester.pump();
    expect(ready, 1,
        reason: 'Missing private imports must not keep selection pending');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('UMD fallback uses the disc layout away from the central badge',
      (tester) async {
    final system =
        SystemModel.supportedSystems.singleWhere((s) => s.id == 'psp');
    const game =
        GameItem(filename: 'Sample (USA).iso', displayName: 'Sample', url: '');
    await tester.pumpWidget(MaterialApp(
        home: CoverSection(
      game: game,
      system: system,
      coverUrls: const [],
      physicalMediaEnabled: true,
      reducedMotion: true,
      metadata: GameMetadata.parse(game.filename),
    )));
    expect(
        tester
            .widget<HandwrittenMediaSticker>(
                find.byType(HandwrittenMediaSticker))
            .disc,
        isTrue);
    expect(
        tester
            .widget<HandwrittenMediaSticker>(
                find.byType(HandwrittenMediaSticker))
            .umd,
        true);
    await tester.pumpWidget(const SizedBox());
  });
  test('source materials retain normal depth and scalar texture channels', () {
    final uniform = SocketMediaGpu.materialUniforms({
      'color': [1, 1, 1, 1],
      'sourceProperties': {
        'normal_scale': 5,
        'metallic': .7,
        'metallic_texture_channel': 4,
        'roughness_texture_channel': 2,
      }
    });
    expect(uniform[6], 5);
    expect(uniform[16], 2);
    expect(uniform[17], 4);
    final casing = SocketMediaGpu.materialUniforms({
      'color': [1, 1, 1, 1],
      'shaderSource': 'res://cartridge_casing.gdshader',
      'sourceProperties': {
        'shader_parameter/normal_depth': .4,
        'shader_parameter/metallic_scale': .8,
        'shader_parameter/metallic_impact': .5,
      }
    });
    expect(casing[5], closeTo(.4, 1e-7));
    expect(casing[6], closeTo(.4, 1e-7));
  });
  test(
      'source camera keeps GBA and UMD label axes upright without face guesses',
      () async {
    for (final format in [
      PhysicalMediaFormat.gameBoy,
      PhysicalMediaFormat.gba,
      PhysicalMediaFormat.psp,
      PhysicalMediaFormat.n64,
      PhysicalMediaFormat.nds,
      PhysicalMediaFormat.vita
    ]) {
      final model = await SocketMediaModel.load(format);
      final pose = SocketMediaPose.sample(
          kind: model.motionKind, selected: 1, seconds: 0, reducedMotion: true);
      final transform = SocketMediaGpu.modelTransform(model, pose);
      final surface = model.surfaces.singleWhere((s) => s['role'] == 'label');
      final count = surface['vertexCount'] as int;
      var uMean = 0.0, vMean = 0.0;
      final points = <vm.Vector3>[];
      final uvs = <List<double>>[];
      for (var i = 0; i < count; i++) {
        final offset = (surface['vertexOffset'] as int) + i * 32;
        double read(int index) =>
            model.mesh.getFloat32(offset + index * 4, Endian.little);
        points
            .add(transform.transformed3(vm.Vector3(read(0), read(1), read(2))));
        uvs.add([read(6), read(7)]);
        uMean += read(6) / count;
        vMean += read(7) / count;
      }
      var right = 0.0, down = 0.0;
      for (var i = 0; i < count; i++) {
        right += (uvs[i][0] - uMean) * points[i].x;
        down += (uvs[i][1] - vMean) * points[i].y;
      }
      expect(right, greaterThan(0),
          reason: '${format.name}: U increases right');
      expect(down, lessThan(0), reason: '${format.name}: V increases down');
    }
  },
      skip: socketOracleRoot.isEmpty
          ? 'Requires private owner APK oracle'
          : false);

  test('camera depth keeps the positive-Z label in front of the casing back',
      () {
    final matrix = SocketMediaGpu.cameraProjection(832, 314, 160);
    expect(matrix.transformed(vm.Vector4(0, 1, 0, 1)).y, greaterThan(0),
        reason: 'GpuImageSurface presents positive clip Y at the image top');
    double depth(double z) {
      final point = matrix.transformed(vm.Vector4(0, 0, z, 1));
      return point.z / point.w;
    }

    expect(depth(.065), lessThan(depth(-.065)),
        reason: 'Less-equal depth must match the camera at positive Z');
  });

  testWidgets('renderer readiness reports unsupported backend as failure',
      (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    await tester.pumpWidget(MaterialApp(
        home: PhysicalMediaView(
            key: key,
            identity: 'failure',
            title: 'Backend failure',
            reducedMotion: true,
            label: const Text('Label'))));
    await tester.pumpAndSettle();
    final result = await key.currentState!.renderReady;
    expect(result['frameRendered'], isFalse);
    expect(result['error'], contains('Impeller'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('physical labels never reuse box-cover artwork', (tester) async {
    final system =
        SystemModel.supportedSystems.firstWhere((s) => s.id == 'gba');
    final game =
        GameItem(filename: 'Game (USA).gba', displayName: 'Game', url: '');
    final cover = File('assets/media_fallbacks/systematic/gba.png')
        .absolute
        .uri
        .toString();
    Widget view(bool physical) => MaterialApp(
        home: CoverSection(
            game: game,
            system: system,
            coverUrls: const ['https://example.invalid/box.png'],
            cachedUrl: cover,
            physicalMediaEnabled: physical,
            reducedMotion: true,
            metadata: GameMetadata.parse(game.filename)));
    await tester.pumpWidget(view(true));
    expect(
        tester.widget<PhysicalMediaView>(find.byType(PhysicalMediaView)).format,
        PhysicalMediaFormat.gba);
    final media =
        tester.widget<PhysicalMediaView>(find.byType(PhysicalMediaView));
    expect(media.label, isA<HandwrittenMediaSticker>());
    expect(
        tester
            .state<CoverSectionState>(find.byType(CoverSection))
            .renderSnapshot['labelExpected'],
        false);
    // Presentation buttons were removed in favor of gesture/external route
    // control; retain this artwork-separation contract through the view owner.
    tester.state<CoverSectionState>(find.byType(CoverSection)).toggleView();
    await tester.pump();
    expect(
        tester.widget<SmartCoverImage>(find.byType(SmartCoverImage)).cachedUrl,
        cover);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('flat previews bind physical labels separately from box art',
      (tester) async {
    final label = File('assets/media_fallbacks/systematic/gba.png')
        .absolute
        .uri
        .toString();
    final box = File('assets/media_fallbacks/systematic/n64.png')
        .absolute
        .uri
        .toString();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    await tester.runAsync(() async {
      await precacheImage(
          ResizeImage.resizeIfNeeded(
              640, null, FileImage(File.fromUri(Uri.parse(label)))),
          context);
      await precacheImage(FileImage(File.fromUri(Uri.parse(box))), context);
    });
    for (final id in ['gba', 'n64', 'ps2', 'psp']) {
      final system =
          SystemModel.supportedSystems.singleWhere((s) => s.id == id);
      const game = GameItem(
          filename: 'Sample (USA).rom', displayName: 'Sample', url: '');
      await tester.pumpWidget(MaterialApp(
          home: CoverSection(
              game: game,
              system: system,
              coverUrls: const [],
              cachedUrl: box,
              physicalLabelUrl: label,
              reducedMotion: true,
              metadata: GameMetadata.parse(game.filename))));
      final image = tester
          .widget<MediaCoverFallback>(find.byType(MediaCoverFallback))
          .physicalLabel! as RawImage;
      final decoded = await tester.runAsync(() async {
        final codec = await instantiateImageCodec(
            await File.fromUri(Uri.parse(label)).readAsBytes());
        final frame = await codec.getNextFrame();
        final size =
            Size(frame.image.width.toDouble(), frame.image.height.toDouble());
        frame.image.dispose();
        codec.dispose();
        return size;
      });
      expect(image.image, isNotNull,
          reason: '$id flat media must use the decoded label');
      expect(image.image!.width / image.image!.height, decoded!.aspectRatio);
      expect(image.fit, BoxFit.fill);
      expect(
          tester
              .state<CoverSectionState>(find.byType(CoverSection))
              .renderSnapshot['labelDecoded'],
          true);
      expect(find.byType(PhysicalMediaView), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'normal cover binds GBC compatibility and the physical label separately',
      (tester) async {
    final system =
        SystemModel.supportedSystems.firstWhere((s) => s.id == 'gbc');
    const game =
        GameItem(filename: 'Game (USA).gbc', displayName: 'Game', url: '');
    await tester.pumpWidget(MaterialApp(
        home: CoverSection(
            game: game,
            system: system,
            coverUrls: const [],
            cachedUrl: 'file:///box.png',
            physicalMediaEnabled: true,
            physicalLabelUrl: 'file:///label.png',
            gbcDualMode: 'no',
            metadata: GameMetadata.parse(game.filename))));
    expect(
        tester.widget<PhysicalMediaView>(find.byType(PhysicalMediaView)).format,
        PhysicalMediaFormat.gameBoyColorDual);
    final section = tester.state<CoverSectionState>(find.byType(CoverSection));
    expect(section.widget.physicalLabelUrl, 'file:///label.png');
    expect(section.renderSnapshot['labelExpected'], true);
    expect(section.renderSnapshot['labelDecoded'], false);
    expect(
        tester.widget<PhysicalMediaView>(find.byType(PhysicalMediaView)).label,
        isA<HandwrittenMediaSticker>());
    expect(
        PhysicalMediaFormat.forSystem('gbc', region: 'Japan', dualMode: 'no'),
        PhysicalMediaFormat.gameBoyColor);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'cached physical artwork updates without replacing the media identity',
      (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    final game =
        GameItem(filename: 'Long Game.gba', displayName: 'Long Game', url: '');
    final system =
        SystemModel.supportedSystems.firstWhere((s) => s.id == 'gba');
    Widget view(String? label) => MaterialApp(
        home: CoverSection(
            game: game,
            system: system,
            coverUrls: const [],
            physicalLabelUrl: label,
            physicalMediaEnabled: true,
            reducedMotion: true,
            physicalMediaKey: key,
            metadata: GameMetadata.parse(game.filename)));
    await tester.pumpWidget(view(null));
    final original = key.currentState;
    expect(find.byType(HandwrittenMediaSticker), findsOneWidget);
    final file = File('assets/media_fallbacks/systematic/gba.png').absolute;
    await tester.runAsync(() => precacheImage(
        ResizeImage.resizeIfNeeded(
            640, null, FileImage(File.fromUri(file.uri))),
        tester.element(find.byType(CoverSection))));
    await tester.pumpWidget(view(file.uri.toString()));
    await tester.pump();
    expect(key.currentState, same(original));
    expect(
        tester
            .state<CoverSectionState>(find.byType(CoverSection))
            .renderSnapshot['labelDecoded'],
        true);
    expect(find.byType(HandwrittenMediaSticker), findsNothing);
    await tester.pumpWidget(view(null));
    await tester.pump();
    expect(key.currentState, same(original));
    expect(find.byType(HandwrittenMediaSticker), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final format in PhysicalMediaFormat.values) {
    testWidgets(
        '${format.name} insertion joins, completes and cancels with the view',
        (tester) async {
      final key = GlobalKey<PhysicalMediaViewState>();
      await tester.pumpWidget(MaterialApp(
          home: PhysicalMediaView(
              key: key,
              format: format,
              identity: 'game',
              title: 'Game',
              label: const Text('Artwork'))));
      final future = key.currentState!.playInsertion();
      expect(identical(future, key.currentState!.playInsertion()), isTrue);
      var completed = false;
      future.then((_) => completed = true);
      await tester.pump();
      await tester
          .pump(Duration(milliseconds: format.insertionMilliseconds - 1));
      expect(completed, isFalse);
      await tester.pump(const Duration(milliseconds: 2));
      expect(await future, isTrue);
      key.currentState!.resetInsertion();
      final cancelled = key.currentState!.playInsertion();
      key.currentState!.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(await cancelled, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'selection and return preserve the reference pose and renderer binding',
      (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    await tester.pumpWidget(MaterialApp(
        home: PhysicalMediaView(
            key: key,
            identity: 'gba',
            title: 'Game',
            format: PhysicalMediaFormat.gba,
            label: const Text('Artwork'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    expect(find.byType(SocketMediaRenderer), findsOneWidget);
    expect(key.currentState!.pose.rz, greaterThan(0));
    final insertion = key.currentState!.playInsertion();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 701));
    expect(await insertion, isTrue);
    final inserted = key.currentState!.pose.y;
    await tester.pump(const Duration(milliseconds: 100));
    expect(key.currentState!.pose.y, closeTo(inserted, .001));
    key.currentState!.didChangeAppLifecycleState(AppLifecycleState.paused);
    key.currentState!.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(key.currentState!.pose.y, greaterThan(inserted + 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'reduced motion skips insertion; missing artwork retains the handwritten title',
      (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    await tester.pumpWidget(MaterialApp(
        home: PhysicalMediaView(
            key: key,
            identity: 'game-1',
            title: 'A long Game Boy title',
            reducedMotion: true,
            label: const HandwrittenMediaSticker(
                identity: 'game-1', title: 'A long Game Boy title'))));
    expect(await key.currentState!.playInsertion(), isTrue);
    expect(find.text('A long Game Boy title'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.text('A long Game Boy title'))
            .style!
            .fontFamily,
        'Kalam');
    expect(find.byKey(const ValueKey('physical-media-skip')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
