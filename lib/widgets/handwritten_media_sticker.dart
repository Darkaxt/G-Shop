import 'package:flutter/material.dart';

/// Shared by physical-media labels and missing box-art illustrations.
class HandwrittenMediaSticker extends StatelessWidget {
  final String identity, title;
  final bool disc;
  const HandwrittenMediaSticker(
      {super.key,
      required this.identity,
      required this.title,
      this.disc = false});
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
  Widget build(BuildContext context) => ColoredBox(
      color: colorFor(identity),
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Expanded(
                child: Align(
                    alignment:
                        disc ? const Alignment(0, -0.6) : Alignment.center,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                            width: 270,
                            child: Text(title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontFamily: 'Kalam',
                                    fontSize: 35,
                                    height: 1.15,
                                    color: Color(0xff25202a))))))),
            const Divider(color: Color(0x5525202a)),
            const Text('MY COLLECTION',
                style: TextStyle(
                    fontSize: 11, letterSpacing: 2, color: Color(0xff49404b))),
          ])));
}
