import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/widgets/cover_reveal.dart';

void main() {
  testWidgets(
      'resolved cover exits left as both media modes grow to normal size',
      (tester) async {
    final provider = FileImage(File('assets/icon.png').absolute);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() =>
        precacheImage(provider, tester.element(find.byType(SizedBox).first)));
    for (final mode in ['flat', '3d']) {
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox(
                  width: 400,
                  height: 300,
                  child: CoverReveal(
                      identity: mode, boxArt: provider, media: Text(mode))))));
      await tester
          .pump(); // Establish the animation's first tick before timing phases.
      final initial = tester
          .widget<Transform>(find.byKey(const ValueKey('cover-reveal-media')))
          .transform
          .storage[0];
      expect(initial, lessThan(1));
      final cover =
          tester.getRect(find.byKey(const ValueKey('cover-reveal-cover')));
      expect(cover.height, lessThanOrEqualTo(270));
      expect(400 * initial, lessThanOrEqualTo(cover.width * .8 + .001));
      expect(300 * initial, lessThanOrEqualTo(cover.height * .8 + .001));
      await tester.pump(const Duration(milliseconds: 750));
      final middle = tester
          .widget<Transform>(find.byKey(const ValueKey('cover-reveal-media')))
          .transform
          .storage[0];
      expect(middle, greaterThan(initial));
      expect(middle, lessThan(1));
      await tester.pump(const Duration(milliseconds: 749));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('cover-reveal-cover')))
              .right,
          lessThan(tester.getRect(find.byType(CoverReveal)).left));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cover-reveal-cover')), findsNothing);
      expect(
          tester
              .widget<Transform>(
                  find.byKey(const ValueKey('cover-reveal-media')))
              .transform
              .storage[0],
          1);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'cold cover holds until media is ready, then slides once in 1.5 seconds',
      (tester) async {
    final cold =
        FileImage(File('assets/media_fallbacks/systematic/gba.png').absolute);
    await cold.evict();
    Widget view(
            {String id = 'same',
            bool reduce = false,
            bool ready = false,
            ImageProvider? art}) =>
        MaterialApp(
            home: SizedBox(
                width: 400,
                height: 300,
                child: CoverReveal(
                    identity: id,
                    boxArt: art,
                    reducedMotion: reduce,
                    mediaReady: ready,
                    media: const Text('Media'))));
    await tester.runAsync(() async {
      await tester.pumpWidget(view(art: cold));
      expect(find.byKey(const ValueKey('cover-reveal-cover')), findsNothing);
      await precacheImage(cold, tester.element(find.text('Media')));
    });
    await tester.pumpWidget(view(art: cold));
    final cover = find.byKey(const ValueKey('cover-reveal-cover'));
    expect(cover, findsOneWidget);
    final held = tester.getRect(cover);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.getRect(cover), held,
        reason: 'Readiness, not elapsed time, starts the animation');
    await tester.pumpWidget(view(art: cold, ready: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(tester.getRect(cover).left, lessThan(held.left));
    await tester.pumpWidget(view(art: cold, ready: true));
    expect(tester.getRect(cover).left, lessThan(held.left),
        reason: 'An unchanged ready snapshot preserves the reveal');
    // Flush the end frame past the floating-point ticker boundary.
    await tester.pump(const Duration(milliseconds: 751));
    expect(CoverReveal.duration, const Duration(milliseconds: 1500));
    expect(cover, findsNothing);
    await tester.pumpWidget(view(art: cold, ready: true));
    expect(cover, findsNothing);
    await tester.pumpWidget(view(id: 'new', reduce: true, art: cold));
    expect(find.byKey(const ValueKey('cover-reveal-cover')), findsNothing);
    expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('cover-reveal-media')))
            .transform
            .storage[0],
        1);
    await tester.pumpWidget(view(id: 'none'));
    expect(find.byKey(const ValueKey('cover-reveal-cover')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving a route finishes its reveal without replay on return',
      (tester) async {
    final art = FileImage(File('assets/icon.png').absolute);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(
        () => precacheImage(art, tester.element(find.byType(SizedBox).first)));
    Widget view(bool visible) => MaterialApp(
        home: TickerMode(
            enabled: visible,
            child: CoverReveal(
                identity: 'same', boxArt: art, media: const Text('Media'))));
    await tester.pumpWidget(view(true));
    await tester.pump();
    expect(find.byKey(const ValueKey('cover-reveal-cover')), findsOneWidget);
    await tester.pumpWidget(view(false));
    expect(find.byKey(const ValueKey('cover-reveal-cover')), findsNothing);
    await tester.pumpWidget(view(true));
    expect(find.byKey(const ValueKey('cover-reveal-cover')), findsNothing);
    expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('cover-reveal-media')))
            .transform
            .storage[0],
        1);
    await tester.pumpWidget(const SizedBox());
  });
}
