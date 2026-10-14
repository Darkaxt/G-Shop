import 'dart:io';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/widgets/physical_media_view.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';
import 'package:retro_eshop/widgets/smart_cover_image.dart';
import 'package:retro_eshop/features/game_detail/widgets/cover_section.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/utils/game_metadata.dart';

// Host checks cover binding, artwork roles and the existing launch lifecycle.
// Actual indexed GPU rendering is checked on Android, not inferred from these.
void main() {
  test('camera depth keeps the positive-Z label in front of the casing back',
      () {
    final matrix = SocketMediaGpu.cameraProjection(832, 314, 160);
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
    final label = tester.widget<SmartCoverImage>(find.byType(SmartCoverImage));
    expect(label.cachedUrl, isNull);
    expect(label.urls, isEmpty);
    await tester.pumpWidget(view(false));
    expect(
        tester.widget<SmartCoverImage>(find.byType(SmartCoverImage)).cachedUrl,
        cover);
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
            reducedMotion: true,
            physicalMediaKey: key,
            metadata: GameMetadata.parse(game.filename)));
    await tester.pumpWidget(view(null));
    final original = key.currentState;
    expect(find.byType(HandwrittenMediaSticker), findsOneWidget);
    final file = File('assets/media_fallbacks/systematic/gba.png').absolute;
    await tester.runAsync(() => precacheImage(
        ResizeImage(FileImage(File.fromUri(file.uri)), width: 640),
        tester.element(find.byType(CoverSection))));
    await tester.pumpWidget(view(file.uri.toString()));
    await tester.pumpAndSettle();
    expect(key.currentState, same(original));
    expect(find.byType(HandwrittenMediaSticker), findsNothing);
    await tester.pumpWidget(view(null));
    await tester.pumpAndSettle();
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
    expect(key.currentState!.pose.y, lessThan(inserted - 1));
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
