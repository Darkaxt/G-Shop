import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/widgets/unboxing_preview.dart';

void main() {
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
