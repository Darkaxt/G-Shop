import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/widgets/physical_media_view.dart';
import 'package:retro_eshop/features/game_detail/widgets/cover_section.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/utils/game_metadata.dart';

void main() {
  testWidgets(
      'cached artwork and missing-artwork recovery keep the same media identity',
      (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    final game = GameItem(
        filename: 'Long Game Name.7z', displayName: 'Long Game Name', url: '');
    final system = SystemModel.supportedSystems.firstWhere((s) => s.id == 'gb');
    Widget view(String? cached) => MaterialApp(
        home: CoverSection(
            game: game,
            system: system,
            coverUrls: const [],
            cachedUrl: cached,
            reducedMotion: true,
            physicalMediaKey: key,
            metadata: GameMetadata.parse(game.filename)));
    await tester.pumpWidget(view(null));
    final original = key.currentState;
    expect(find.byType(HandwrittenMediaSticker), findsOneWidget);
    final file = File('assets/media_fallbacks/systematic/gb.png').absolute;
    // Start I/O before mounting Image, outside the test clock. Joining a
    // fake-clock ImageCache load from runAsync would prevent its microtasks
    // from being pumped while waiting for that same load.
    await tester.runAsync(() => precacheImage(
        ResizeImage(FileImage(File.fromUri(file.uri)), width: 640),
        tester.element(find.byType(CoverSection))));
    final artwork = file.uri.toString();
    await tester.pumpWidget(view(artwork));
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
  test('format mapping distinguishes unsupported physical formats', () {
    expect(PhysicalMediaFormat.forSystem('n64'), PhysicalMediaFormat.n64);
    expect(PhysicalMediaFormat.forSystem('psx'), PhysicalMediaFormat.disc);
    for (final unsupported in ['psp', 'gc', 'gba', 'gbc', 'nes']) {
      expect(PhysicalMediaFormat.forSystem(unsupported), isNull);
    }
  });
  test('N64 shell follows exterior bounds; optical disc has a real hub hole',
      () {
    final cart = PhysicalMediaGeometry.n64;
    expect(cart.height / cart.width, closeTo(0.03 / 0.045, 0.0001));
    expect(cart.depth / cart.width, closeTo(0.0075 / 0.045, 0.0001));
    final disc = PhysicalMediaGeometry.disc;
    expect(disc.depth / disc.width, closeTo(0.001886 / 0.1239977, 0.0001));
    for (final face in disc.faces) {
      final path = Path()..moveTo(face.points.first.x, face.points.first.y);
      for (final point in face.points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      path.close();
      expect(path.contains(Offset.zero), isFalse,
          reason: 'No disc surface may fill the spindle hole');
    }
    for (final format in PhysicalMediaFormat.values) {
      expect(PhysicalMediaGeometry.forFormat(format).faces.length,
          lessThanOrEqualTo(256));
    }
  });
  for (final format in PhysicalMediaFormat.values) {
    testWidgets(
        '${format.name} insertion uses its duration and joins one launch',
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
  testWidgets('Game Boy straightens during spin before descending',
      (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    await tester.pumpWidget(MaterialApp(
        home: PhysicalMediaView(
            key: key,
            identity: 'game',
            title: 'Game',
            label: const Text('Artwork'))));
    final future = key.currentState!.playInsertion();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final transforms = tester.widgetList<Transform>(find.descendant(
        of: find.byType(PhysicalMediaView), matching: find.byType(Transform)));
    for (final transform in transforms) {
      for (final index in [1, 2, 4, 6]) {
        expect(transform.transform.storage[index], closeTo(0, 0.000001));
      }
    }
    key.currentState!.skipInsertion();
    expect(await future, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'completed insertion resets only after emulator background return',
      (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    await tester.pumpWidget(MaterialApp(
        home: PhysicalMediaView(
            key: key,
            identity: 'game',
            title: 'Game',
            label: const Text('Artwork'))));
    double labelY() => tester
        .widgetList<Transform>(find.descendant(
            of: find.byType(PhysicalMediaView),
            matching: find.byType(Transform)))
        .last
        .transform
        .storage[13];
    final insertion = key.currentState!.playInsertion();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 851));
    expect(await insertion, isTrue);
    final inserted = labelY();
    await tester.pump(const Duration(milliseconds: 100));
    expect(labelY(), closeTo(inserted, 0.001),
        reason: 'Android launch acceptance is not yet a background transition');
    key.currentState!.didChangeAppLifecycleState(AppLifecycleState.paused);
    key.currentState!.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(labelY(), lessThan(inserted - 20),
        reason:
            'Returning from the emulator restores the normal media position');
    await tester.pumpWidget(const SizedBox());
  });
  for (final systemId in ['n64', 'psx', 'ps2']) {
    testWidgets('$systemId detail uses its physical media without artwork',
        (tester) async {
      final system =
          SystemModel.supportedSystems.firstWhere((s) => s.id == systemId);
      final game =
          GameItem(filename: 'A Game.7z', displayName: 'A Game', url: '');
      await tester.pumpWidget(MaterialApp(
          home: SizedBox(
              width: 320,
              height: 400,
              child: CoverSection(
                  game: game,
                  system: system,
                  coverUrls: const [],
                  metadata: GameMetadata.parse(game.filename)))));
      expect(find.byType(PhysicalMediaView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('Game Boy shell has volume and reference exterior proportions', () {
    final model = PhysicalMediaGeometry.gameBoy;
    expect(model.width / model.height, closeTo(0.0564107 / 0.0648228, 0.001));
    expect(model.depth / model.width, closeTo(0.0074225 / 0.0564107, 0.001));
    expect(model.faces.any((f) => f.points.any((p) => p.z < 0)), isTrue);
    expect(model.faces.any((f) => f.points.any((p) => p.z > 0)), isTrue);
    expect(
        model.label.width / model.width, closeTo(0.0439713 / 0.0564107, 0.001));
    // Shell planes must not be split into overlapping depth-sorted triangles
    // which overpaint the nearer grip ribs during rotation.
    expect(model.faces.where((face) => face.points.length == 9), hasLength(4));
    expect(model.header.bottom, lessThan(model.label.top));
  });

  testWidgets('missing artwork is a stable readable title on the same model',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: SizedBox(
            width: 320,
            height: 400,
            child: PhysicalMediaView(
                identity: 'game-1',
                title: 'A long Game Boy title',
                reducedMotion: true,
                label: HandwrittenMediaSticker(
                    identity: 'game-1', title: 'A long Game Boy title')))));
    expect(find.byKey(const ValueKey('physical-media-shell')), findsOneWidget);
    expect(find.text('A long Game Boy title'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.text('A long Game Boy title'))
            .style!
            .fontFamily,
        'Kalam');
    expect(HandwrittenMediaSticker.colorFor('game-1'),
        HandwrittenMediaSticker.colorFor('game-1'));
    expect(HandwrittenMediaSticker.palette,
        contains(HandwrittenMediaSticker.colorFor('game-1')));
  });

  testWidgets(
      'insertion completes once, skips and cancels with the view lifecycle',
      (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            width: 320,
            height: 400,
            child: PhysicalMediaView(
                key: key,
                identity: 'game-1',
                title: 'Game',
                label: const Text('label')))));
    final first = key.currentState!.playInsertion();
    expect(identical(first, key.currentState!.playInsertion()), isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    key.currentState!.skipInsertion();
    expect(await first, isTrue);
    key.currentState!.resetInsertion();
    final second = key.currentState!.playInsertion();
    await tester.pumpWidget(const SizedBox());
    expect(await second, isFalse);
  });

  testWidgets('reduced motion never waits for an animation', (tester) async {
    final key = GlobalKey<PhysicalMediaViewState>();
    await tester.pumpWidget(MaterialApp(
        home: PhysicalMediaView(
            key: key,
            identity: 'game-1',
            title: 'Game',
            reducedMotion: true,
            label: const Text('label'))));
    expect(await key.currentState!.playInsertion(), isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
