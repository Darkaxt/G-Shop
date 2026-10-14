import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/widgets/physical_media_view.dart';

void main() {
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
                label: Text('label artwork')))));
    expect(find.byKey(const ValueKey('physical-media-shell')), findsOneWidget);
    expect(find.text('label artwork'), findsOneWidget);
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
