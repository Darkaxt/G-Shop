import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/game_detail/widgets/cover_section.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/utils/game_metadata.dart';
import 'package:retro_eshop/widgets/cover_reveal.dart';

void main() {
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
