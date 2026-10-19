import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/widgets/unboxing_preview.dart';

void main() {
  testWidgets('decoding panels does not remount the visible preparation image',
      (tester) async {
    final key = GlobalKey<UnboxingPreviewState>();
    final front = File.fromUri(
        File('assets/brand_logos/publisher_nintendo.png').absolute.uri);
    await FileImage(front).evict();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() => precacheImage(
        FileImage(front), tester.element(find.byType(SizedBox).first)));
    await tester.pumpWidget(MaterialApp(
        home: UnboxingPreview(
            key: key,
            identity: 'stable-cover',
            title: 'Fixture',
            style: 'gray',
            resources: {
              'outer-box-front': [front.uri.toString()]
            },
            resourcesReady: false,
            cartridgeLabel: const SizedBox(),
            labelIdentity: 'fixture')));
    final image = find.byKey(const ValueKey('unboxing-preparation-cover'));
    final before = tester.element(image);
    await tester.pump();
    expect(key.currentState!.snapshot['imagesReady'], true,
        reason: '${key.currentState!.snapshot}');
    expect(tester.element(image), same(before),
        reason:
            'Reparenting the Image discards its decoded frame during handoff.');
    expect(tester.widget<Image>(image).gaplessPlayback, true,
        reason: 'Within the same game, retain the cover until its classified '
            'replacement has decoded. The identity subtree resets on selection.');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('the cover stays visible while the scene is preparing',
      (tester) async {
    final key = GlobalKey<UnboxingPreviewState>();
    final front = File.fromUri(File('assets/icon.png').absolute.uri);
    // Resolve file IO outside FakeAsync before the first Image creates a cached
    // stream; a pending stream must not leak into the next widget test's zone.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() => precacheImage(
        FileImage(front), tester.element(find.byType(SizedBox).first)));
    await tester.pumpWidget(MaterialApp(
        home: UnboxingPreview(
            key: key,
            identity: 'preparing',
            title: 'Fixture',
            style: 'blue',
            resources: {
              'box-2D': [front.uri.toString()]
            },
            resourcesReady: false,
            cartridgeLabel: const ColoredBox(color: Colors.white),
            labelIdentity: 'fixture')));
    await tester.pump();
    expect(key.currentState!.snapshot['imagesReady'], true);
    expect(key.currentState!.snapshot['started'], false);
    expect(find.byKey(const ValueKey('unboxing-preparation-cover')),
        findsOneWidget);
    final canvas = tester.getSize(find.byType(UnboxingPreview));
    final cover = tester
        .getRect(find.byKey(const ValueKey('unboxing-preparation-cover')));
    expect(cover.width, closeTo(canvas.shortestSide * .9, .001));
    expect(cover.height, closeTo(canvas.shortestSide * .9, .001));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('the prepared cover uses the same English front as the carton',
      (tester) async {
    final key = GlobalKey<UnboxingPreviewState>();
    final front = File.fromUri(File('assets/icon.png').absolute.uri);
    final waiting = FileImage(File.fromUri(
        File('assets/brand_logos/publisher_nintendo.png').absolute.uri));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() =>
        precacheImage(waiting, tester.element(find.byType(SizedBox).first)));
    await tester.runAsync(() => precacheImage(
        FileImage(front), tester.element(find.byType(SizedBox).first)));
    Widget preview(Map<String, List<String>> resources) => MaterialApp(
        home: UnboxingPreview(
            key: key,
            identity: 'handoff',
            title: 'Fixture',
            style: 'blue',
            resources: resources,
            waitingCover: waiting,
            resourcesReady: false,
            cartridgeLabel: const ColoredBox(color: Colors.white),
            labelIdentity: 'fixture'));
    await tester.pumpWidget(preview(const {}));
    await tester.pump();
    final before = tester.widget<Image>(
        find.byKey(const ValueKey('unboxing-preparation-cover')));
    await tester.pumpWidget(preview({
      'outer-box-front': [front.uri.toString()]
    }));
    await tester.pump();
    final after = tester.widget<Image>(
        find.byKey(const ValueKey('unboxing-preparation-cover')));
    expect(identical(before.image, waiting), true);
    expect(after.image, FileImage(front),
        reason:
            'The catalog cover can be a different English scan. The waiting '
            'front must match the exact classified face used by the GPU atlas.');
    expect(key.currentState!.snapshot['started'], false);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('double-tapping the inspected booklet requests the reader',
      (tester) async {
    final key = GlobalKey<UnboxingPreviewState>();
    var read = 0;
    final front = File.fromUri(File('assets/icon.png').absolute.uri);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() => precacheImage(
        FileImage(front), tester.element(find.byType(SizedBox).first)));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UnboxingPreview(
                key: key,
                identity: 'booklet',
                title: 'Fixture',
                style: 'blue',
                resources: {
                  'booklet-front': [front.uri.toString()]
                },
                cartridgeLabel: const ColoredBox(color: Colors.white),
                labelIdentity: 'fixture',
                initiallySettled: true,
                initialInspectionPart: 'booklet',
                onReadManual: () => read++))));
    await tester.pump();
    expect(key.currentState!.snapshot['imagesReady'], true);
    await tester.tap(find.byType(UnboxingPreview));
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(find.byType(UnboxingPreview));
    await tester.pump();
    expect(read, 1);
    expect(key.currentState!.snapshot['inspectedPart'], 'booklet');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('pinching an inspected object back out restores the tableau',
      (tester) async {
    final key = GlobalKey<UnboxingPreviewState>();
    final changes = <String?>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UnboxingPreview(
                key: key,
                identity: 'inspection',
                title: 'Fixture',
                style: 'blue',
                resources: const {},
                cartridgeLabel: const ColoredBox(color: Colors.white),
                labelIdentity: 'fixture',
                initiallySettled: true,
                initialInspectionPart: 'cartridge',
                onInspectionChanged: changes.add))));
    await tester.pump();
    expect(key.currentState!.snapshot['inspectedPart'], 'cartridge');
    expect(key.currentState!.snapshot['inspection'], 1,
        reason: '${key.currentState!.snapshot}');
    final centre = tester.getCenter(find.byType(UnboxingPreview));
    final left =
        await tester.startGesture(centre - const Offset(120, 0), pointer: 1);
    final right =
        await tester.startGesture(centre + const Offset(120, 0), pointer: 2);
    await left.moveTo(centre - const Offset(110, 0));
    await right.moveTo(centre + const Offset(110, 0));
    await tester.pump();
    await left.moveTo(centre - const Offset(40, 0));
    await right.moveTo(centre + const Offset(40, 0));
    await tester.pump();
    await left.up();
    await right.up();
    expect(key.currentState!.snapshot['returning'], true,
        reason: '${key.currentState!.snapshot}');
    // Advance the inspection transition, not the unavailable host GPU loader.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The terminal AnimationStatus is emitted on the frame after the endpoint.
    await tester.pump(const Duration(milliseconds: 16));
    expect(key.currentState!.snapshot['inspectedPart'], isNull,
        reason: '${key.currentState!.snapshot}');
    expect(changes.last, isNull);
    expect(key.currentState!.snapshot['progress'], 1);
    await tester.pumpWidget(const SizedBox());
  });
}
