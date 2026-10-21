import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/game_detail/widgets/cover_section.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/utils/game_metadata.dart';
import 'package:g_shop/widgets/cover_reveal.dart';
import 'package:g_shop/widgets/unboxing_preview.dart';

void main() {
  testWidgets('GBA retains its preparation owner when packaging arrives',
      (tester) async {
    final cover = FileImage(File.fromUri(File('assets/icon.png').absolute.uri));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() =>
        precacheImage(cover, tester.element(find.byType(SizedBox).first)));
    Widget view(Map<String, List<String>> resources, {bool ready = false}) =>
        MaterialApp(
            home: CoverSection(
                game: const GameItem(
                    filename: 'Fixture (USA).gba',
                    displayName: 'Fixture',
                    url: ''),
                system: SystemModel.supportedSystems
                    .firstWhere((s) => s.id == 'gba'),
                coverUrls: const [],
                cachedUrl: cover.file.uri.toString(),
                metadata: GameMetadata.parse('Fixture (USA).gba'),
                contentTags: const ['official'],
                physicalMediaEnabled: true,
                resourcesReady: ready,
                packagingResources: resources,
                showPresentationControls: false));
    await tester.pumpWidget(view(const {}));
    expect(find.byType(UnboxingPreview), findsOneWidget,
        reason:
            'Late packaging must not replace a different waiting-cover owner.');
    final owner = tester.element(find.byType(UnboxingPreview));
    await tester.runAsync(() => precacheImage(cover, owner));
    await tester.pump();
    await tester.pumpWidget(view({
      'outer-box-front': [cover.file.uri.toString()]
    }));
    expect(tester.element(find.byType(UnboxingPreview)), same(owner));
    await tester.pumpWidget(view(const {}, ready: true));
    expect(find.byType(UnboxingPreview), findsNothing,
        reason: 'A completed no-art lookup retains the established fallback.');
    expect(find.byType(CoverReveal), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('selected preview holds its real cover until all media is ready',
      (tester) async {
    final key = GlobalKey<CoverSectionState>();
    final cover = FileImage(File('assets/icon.png').absolute);
    final label =
        FileImage(File('assets/media_fallbacks/systematic/gba.png').absolute);
    await cover.evict();
    await ResizeImage.resizeIfNeeded(640, null, label).evict();
    var readyEvents = 0;
    var revealedEvents = 0;
    Widget view(bool ready) => MaterialApp(
        home: Center(
            child: SizedBox(
                width: 400,
                height: 300,
                child: CoverSection(
                    key: key,
                    game: GameItem(
                        filename: 'Fixture.gba',
                        displayName: 'Fixture',
                        url: ''),
                    system: SystemModel.supportedSystems
                        .firstWhere((s) => s.id == 'gba'),
                    coverUrls: const [],
                    cachedUrl: cover.file.uri.toString(),
                    physicalLabelUrl: label.file.uri.toString(),
                    metadata: GameMetadata.parse('Fixture.gba'),
                    resourcesReady: ready,
                    onReady: () => readyEvents++,
                    onRevealed: () => revealedEvents++,
                    showPresentationControls: false))));
    await tester.runAsync(() async {
      await tester.pumpWidget(view(false));
      final context = tester.element(find.byType(CoverSection));
      await precacheImage(cover, context);
      await precacheImage(
          ResizeImage.resizeIfNeeded(640, null, label), context);
    });
    final owner = key.currentState;
    await tester.pump();
    final box = find.byKey(const ValueKey('cover-reveal-cover'));
    expect(box, findsOneWidget);
    expect(key.currentState!.renderSnapshot['labelDecoded'], isTrue);
    expect(tester.widget<CoverReveal>(find.byType(CoverReveal)).mediaReady,
        isFalse);
    final held = tester.getRect(box);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.getRect(box), held);
    expect(readyEvents, 0);
    expect(revealedEvents, 0);
    await tester.pumpWidget(view(true));
    await tester.pump();
    expect(key.currentState, same(owner));
    expect(readyEvents, 1);
    expect(revealedEvents, 0);
    await tester.pump(const Duration(milliseconds: 750));
    final sliding = tester.getRect(box);
    expect(sliding.left, lessThan(held.left));
    await tester.pumpWidget(view(true));
    expect(key.currentState, same(owner));
    expect(tester.getRect(box), sliding);
    expect(key.currentState!.renderSnapshot['labelDecoded'], isTrue);
    await tester.pump(const Duration(milliseconds: 751));
    expect(box, findsNothing);
    expect(readyEvents, 1);
    expect(revealedEvents, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
