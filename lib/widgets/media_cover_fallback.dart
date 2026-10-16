import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'handwritten_media_sticker.dart';

/// Original platform media, not a downloaded file's archive/container format.
/// Mixed-media computers intentionally use a neutral illustration, not a claim
/// that this particular release shipped on a cassette or floppy.
const platformMediaFamilies = <String, String>{
  'nes': 'nes',
  'snes': 'snes',
  'n64': 'n64',
  'gb': 'gb',
  'gbc': 'gbc',
  'gba': 'gba',
  'virtualboy': 'virtualboy',
  'mastersystem': 'mastersystem',
  'megadrive': 'megadrive',
  'gamegear': 'gamegear',
  'sega32x': 'sega32x',
  'sg1000': 'sg1000',
  'ngp': 'ngp',
  'wonderswan': 'wonderswan',
  'colecovision': 'colecovision',
  'intellivision': 'intellivision',
  'vectrex': 'vectrex',
  'channelf': 'channelf',
  'odyssey2': 'odyssey2',
  'jaguar': 'jaguar',
  'atari2600': 'atari2600',
  'atari5200': 'atari5200',
  'atari7800': 'atari7800',
  'lynx': 'lynx',
  'arcadia2001': 'arcadia2001',
  'switch': 'switch',
  'nds': 'nds',
  'dsi': 'dsi',
  'n3ds': 'n3ds',
  'psvita': 'psvita',
  'tg16': 'tg16',
  'ngage': 'ngage',
  'gc': 'gc',
  'wii': 'wii',
  'wiiu': 'wiiu',
  'psx': 'psx',
  'ps2': 'ps2',
  'ps3': 'ps3',
  'segacd': 'segacd',
  'dreamcast': 'dreamcast',
  'saturn': 'saturn',
  'tgcd': 'tgcd',
  'neogeocd': 'neogeocd',
  'jaguarcd': 'jaguarcd',
  'pcfx': 'pcfx',
  'cdi': 'cdi',
  '3do': '3do',
  'psp': 'psp',
  'fds': 'fds',
  'msx': 'neutral',
  'amstradcpc': 'neutral',
  'atarist': 'neutral',
  'c64': 'neutral',
  'vic20': 'neutral',
  'amiga': 'neutral',
  'zxspectrum': 'neutral',
  'oric': 'neutral',
  'x68000': 'neutral',
  'x1': 'neutral',
  'fmtowns': 'neutral',
  'appleii': 'neutral',
  'dos': 'neutral',
  'arcade': 'neutral',
  'gameandwatch': 'neutral',
  'tic80': 'neutral',
  'pico8': 'neutral',
};

String mediaFallbackAsset(String? systemId) =>
    'assets/media_fallbacks/systematic/${platformMediaFamilies[systemId] ?? 'neutral'}.png';

/// Registered once at application startup; the bundled notice works offline.
Stream<LicenseEntry> mediaArtworkLicenses() async* {
  yield LicenseEntryWithLineBreaks(['Manufacturer brand logos'],
      await rootBundle.loadString('assets/brand_logos/NOTICE.md'));
  final notice =
      await rootBundle.loadString('assets/media_fallbacks/NOTICE.md');
  final license = await rootBundle.loadString('assets/media_fallbacks/COPYING');
  yield LicenseEntryWithLineBreaks(
      ['Systematic media icons'], '$notice\n\n$license');
  final labelFontLicense =
      await rootBundle.loadString('assets/fonts/Kalam-OFL.txt');
  yield LicenseEntryWithLineBreaks(
      ['Kalam handwritten labels'], labelFontLicense);
  for (final file in [
    'NOTICE.txt',
    'Texture2DDecoder-LICENSE.txt',
    'FastNoiseLite-LICENSE.txt',
    'Zstd-JNI-LICENSE.txt',
    'Zstandard-LICENSE.txt'
  ]) {
    yield LicenseEntryWithLineBreaks(['Local media import codecs'],
        await rootBundle.loadString('assets/media_import_licenses/$file'));
  }
}

Stream<LicenseEntry> patchEngineLicenses() async* {
  for (final file in [
    'NOTICE.txt',
    'GPL-3.0.txt',
    'XDelta-GPL-2.0.txt',
    'GLib-LGPL-2.0.txt',
    'PCRE.txt',
    'XZ.txt'
  ]) {
    yield LicenseEntryWithLineBreaks(
        ['UniPatcher and native patch dependencies'],
        await rootBundle.loadString('assets/patch_engine_licenses/$file'));
  }
}

/// Bundled art never starts a provider/image/ROM request or an animation.
class MediaCoverFallback extends StatelessWidget {
  final String? systemId;
  final String? title, identity;

  /// An already-cached physical label, never box-cover artwork.
  final Widget? physicalLabel;
  final double? width;
  final double? height;
  final Color backgroundColor;

  const MediaCoverFallback(
      {super.key,
      this.systemId,
      this.title,
      this.identity,
      this.physicalLabel,
      this.width,
      this.height,
      this.backgroundColor = const Color(0xFF182326)});

  @override
  Widget build(BuildContext context) {
    // Slots follow the bundled Systematic PNGs, in their square asset space.
    final disc = {
      'gc',
      'wii',
      'wiiu',
      'psx',
      'ps2',
      'ps3',
      'segacd',
      'dreamcast',
      'saturn',
      'tgcd',
      'neogeocd',
      'jaguarcd',
      'pcfx',
      'cdi',
      '3do'
    }.contains(systemId);
    final slot = switch (systemId) {
      'gba' => const Rect.fromLTWH(.172, .375, .68, .33),
      'n64' => const Rect.fromLTWH(.289, .262, .422, .492),
      'psp' => const Rect.fromLTWH(.148, .117, .703, .703),
      _ when disc => const Rect.fromLTWH(.043, .043, .914, .914),
      _ => const Rect.fromLTWH(.175, .355, .65, .34),
    };
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: backgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                Image.asset(
                  mediaFallbackAsset(systemId),
                  fit: BoxFit.contain,
                  cacheWidth: 256,
                  excludeFromSemantics: true,
                ),
                if (physicalLabel != null)
                  Positioned.fill(child: LayoutBuilder(builder: (_, bounds) {
                    final label = disc || systemId == 'psp'
                        ? ClipPath(
                            clipper:
                                _DiscLabelClipper(systemId == 'psp' ? .4 : .1),
                            child: physicalLabel!)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: physicalLabel!);
                    return Stack(children: [
                      Positioned(
                        left: slot.left * bounds.maxWidth,
                        top: slot.top * bounds.maxHeight,
                        width: slot.width * bounds.maxWidth,
                        height: slot.height * bounds.maxHeight,
                        child: label,
                      )
                    ]);
                  }))
                else if (title != null && title!.trim().isNotEmpty)
                  Align(
                    alignment: const Alignment(0, 0.05),
                    child: FractionallySizedBox(
                      widthFactor: 0.65,
                      heightFactor: 0.34,
                      child: Transform.rotate(
                        angle: -0.055,
                        child: FittedBox(
                          child: SizedBox(
                            width: 310,
                            height: 180,
                            child: HandwrittenMediaSticker(
                              identity: identity ?? '$systemId:$title',
                              title: title!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscLabelClipper extends CustomClipper<Path> {
  final double hole;
  const _DiscLabelClipper(this.hole);
  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Offset.zero & size)
    ..addOval(Rect.fromCenter(
        center: size.center(Offset.zero),
        width: size.width * hole,
        height: size.height * hole));
  @override
  bool shouldReclip(_DiscLabelClipper old) => old.hole != hole;
}
