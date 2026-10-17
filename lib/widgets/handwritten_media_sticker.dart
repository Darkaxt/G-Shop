import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared by physical-media labels and missing box-art illustrations.
class HandwrittenMediaSticker extends StatelessWidget {
  final String identity, title;
  final bool disc, umd;
  const HandwrittenMediaSticker(
      {super.key,
      required this.identity,
      required this.title,
      this.disc = false,
      this.umd = false});
  static const palette = <Color>[
    Color(0xfff0dd99),
    Color(0xffbdd9b5),
    Color(0xffd9c4e1),
    Color(0xffb8d5e7),
    Color(0xffedc0a4)
  ];
  static Color colorFor(String identity) {
    var hash = 0;
    for (final unit in identity.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, bounds) {
        if (disc) {
          return ColoredBox(
              color: colorFor(identity),
              child: Semantics(
                  label: title,
                  image: true,
                  child: CustomPaint(
                      size: Size.infinite,
                      painter: DiscTitlePainter(title, umd: umd))));
        }
        // Cartridge labels use their actual aspect, rather than a fixed-width
        // paragraph and footer. Real scanned labels do not use this widget.
        final portrait = bounds.maxHeight > bounds.maxWidth * 1.25;
        final area = portrait
            ? const Rect.fromLTWH(.08, .18, .84, .64)
            : const Rect.fromLTWH(.07, .12, .86, .76);
        return ColoredBox(
            color: colorFor(identity),
            child: Stack(children: [
              Positioned(
                  left: area.left * bounds.maxWidth,
                  top: area.top * bounds.maxHeight,
                  width: area.width * bounds.maxWidth,
                  height: area.height * bounds.maxHeight,
                  child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                          width: 300,
                          child: Text(title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontFamily: 'Kalam',
                                  fontSize: 35,
                                  height: 1.15,
                                  color: Color(0xff25202a))))))
            ]));
      });
}

/// Letter centres follow upper circular arcs. The second arc is used for long
/// titles; both radii stay outside the UMD badge, not just outside a CD hole.
/// This paints live text into the existing label texture, not generated artwork.
class DiscTitlePainter extends CustomPainter {
  final String title;
  final bool umd;
  const DiscTitlePainter(this.title, {this.umd = false});
  static TextPainter _text(String text, double fontSize) => TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontFamily: 'Kalam',
              fontSize: fontSize,
              height: 1.1,
              color: const Color(0xff25202a))),
      textDirection: TextDirection.ltr)
    ..layout();
  static Size _measure(String text, double fontSize) {
    final painter = _text(text, fontSize);
    final size = painter.size;
    painter.dispose();
    return size;
  }

  static double _advance(String text, double fontSize) => text.characters
      .fold(0.0, (width, glyph) => width + _measure(glyph, fontSize).width);

  List<
      ({
        String text,
        int row,
        double fontSize,
        Offset center,
        double angle,
        Size size
      })> glyphs(Size size) {
    final diameter = math.min(size.width, size.height);
    if (diameter <= 0 || title.trim().isEmpty) return [];
    final radii = [diameter * .39, diameter * (umd ? .30 : .27)];
    const span = math.pi * .88;
    final words = title.trim().split(RegExp(r'\s+'));
    var font = diameter * (umd ? .055 : .07);
    List<String>? fit(double fontSize) {
      final lines = <String>[''];
      for (final word in words) {
        final candidate = lines.last.isEmpty ? word : '${lines.last} $word';
        if (_advance(candidate, fontSize) <= radii[lines.length - 1] * span) {
          lines[lines.length - 1] = candidate;
        } else {
          if (lines.last.isEmpty ||
              lines.length == radii.length ||
              _advance(word, fontSize) > radii[lines.length] * span)
            return null;
          lines.add(word);
        }
      }
      return lines;
    }

    var lines = fit(font);
    // Geometry fitting, not a delay or operation deadline. Reduce the type
    // until every word fits in the available annulus; never drop title text.
    while (lines == null) {
      font *= .9;
      lines = fit(font);
    }
    final result = <({
      String text,
      int row,
      double fontSize,
      Offset center,
      double angle,
      Size size
    })>[];
    for (var row = 0; row < lines.length; row++) {
      final radius = radii[row];
      var angle = -math.pi / 2 - _advance(lines[row], font) / (2 * radius);
      for (final glyph in lines[row].characters) {
        final measured = _measure(glyph, font);
        final middle = angle + measured.width / (2 * radius);
        result.add((
          text: glyph,
          row: row,
          fontSize: font,
          center: size.center(Offset.zero) +
              Offset(math.cos(middle), math.sin(middle)) * radius,
          angle: middle + math.pi / 2,
          size: measured
        ));
        angle += measured.width / radius;
      }
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final glyph in glyphs(size)) {
      final painter = _text(glyph.text, glyph.fontSize);
      canvas.save();
      canvas.translate(glyph.center.dx, glyph.center.dy);
      canvas.rotate(glyph.angle);
      painter.paint(
          canvas, Offset(-glyph.size.width / 2, -glyph.size.height / 2));
      canvas.restore();
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(DiscTitlePainter oldDelegate) =>
      title != oldDelegate.title || umd != oldDelegate.umd;
}
