import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  final notice =
      await rootBundle.loadString('assets/media_fallbacks/NOTICE.md');
  final license = await rootBundle.loadString('assets/media_fallbacks/COPYING');
  yield LicenseEntryWithLineBreaks(
      ['Systematic media icons'], '$notice\n\n$license');
}

/// Bundled art never starts a provider/image/ROM request or an animation.
class MediaCoverFallback extends StatelessWidget {
  final String? systemId;
  final double? width;
  final double? height;

  const MediaCoverFallback({super.key, this.systemId, this.width, this.height});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: const Color(0xFF182326),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Image.asset(
              mediaFallbackAsset(systemId),
              fit: BoxFit.contain,
              cacheWidth: 256,
              excludeFromSemantics: true,
            ),
          ),
        ),
      );
}
