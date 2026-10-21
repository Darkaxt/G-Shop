import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/widgets/handwritten_media_sticker.dart';

void main() {
  test('curved glyphs fit the disc annulus and preserve every title word', () {
    const title =
        'A Long Game Title with Extra Words and a Special Edition Subtitle';
    const size = Size(384, 384);
    for (final umd in [false, true]) {
      final glyphs = DiscTitlePainter(title, umd: umd).glyphs(size);
      final rows = glyphs.map((g) => g.row).toSet().toList()..sort();
      expect(rows.length, 2);
      expect(
          rows
              .map((row) =>
                  glyphs.where((g) => g.row == row).map((g) => g.text).join())
              .join(' '),
          title);
      expect(
          glyphs.map((g) => g.angle).reduce(math.max) -
              glyphs.map((g) => g.angle).reduce(math.min),
          greaterThan(.5));
      for (final glyph in glyphs) {
        for (final dx in [-glyph.size.width / 2, glyph.size.width / 2]) {
          for (final dy in [-glyph.size.height / 2, glyph.size.height / 2]) {
            final corner = glyph.center +
                Offset(dx * math.cos(glyph.angle) - dy * math.sin(glyph.angle),
                    dx * math.sin(glyph.angle) + dy * math.cos(glyph.angle));
            final radius = (corner - size.center(Offset.zero)).distance;
            expect(radius, greaterThan(384 * (umd ? .24 : .12)));
            expect(radius, lessThan(384 * .48));
          }
        }
      }
    }
  });
  testWidgets('UMD title avoids the larger central badge', (tester) async {
    const title = 'PlayStation Portable inspection';
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox(
                width: 384,
                height: 384,
                child: HandwrittenMediaSticker(
                    identity: 'umd', title: title, disc: true, umd: true)))));
    expect(
        find.descendant(
            of: find.byType(HandwrittenMediaSticker),
            matching: find.byType(CustomPaint)),
        findsOneWidget,
        reason:
            'Disc lettering must follow an arc, not a rectangular paragraph');
  });
  testWidgets('disc fallback keeps long titles above the central hub',
      (tester) async {
    const title = 'The Legend of Zelda: The Minish Cap';
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox(
                width: 384,
                height: 384,
                child: HandwrittenMediaSticker(
                    identity: 'disc', title: title, disc: true)))));
    expect(
        find.descendant(
            of: find.byType(HandwrittenMediaSticker),
            matching: find.byType(CustomPaint)),
        findsOneWidget);
  });
  testWidgets(
      'portrait cartridge uses its label instead of shrinking around a footer',
      (tester) async {
    const title = 'Nintendo Entertainment System inspection';
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox(
                width: 180,
                height: 384,
                child:
                    HandwrittenMediaSticker(identity: 'nes', title: title)))));
    final label = tester.getRect(find.byType(HandwrittenMediaSticker));
    final text = tester.getRect(find.text(title));
    expect(text.height, greaterThan(label.height * .3));
    expect(text.left, greaterThanOrEqualTo(label.left));
    expect(text.right, lessThanOrEqualTo(label.right));
    expect(tester.takeException(), isNull);
  });
}
