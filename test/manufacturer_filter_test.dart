import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:retro_eshop/features/home/widgets/manufacturer_filter.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/services/config_bootstrap.dart';

void main() {
  test('every existing manufacturer has a nonblank transparent PNG', () {
    final brands =
        SystemModel.supportedSystems.map((s) => s.manufacturer).toSet();
    for (final brand in brands) {
      expect(manufacturerLogos, contains(brand), reason: brand);
      final png = image.decodePng(
          File('assets/brand_logos/${manufacturerLogos[brand]}.png')
              .readAsBytesSync());
      expect(png, isNotNull, reason: brand);
      expect(png!.width, greaterThan(0));
      expect(png.any((p) => p.a == 0), isTrue, reason: '$brand transparency');
      expect(png.any((p) => p.a > 0), isTrue, reason: '$brand visible content');
    }
  });
  test('manufacturer membership and sync scope preserve order/configuration',
      () {
    final systems = SystemModel.supportedSystems
        .where((s) => ['nes', 'psp', 'snes', 'megadrive'].contains(s.id))
        .toList();
    expect(systemsForManufacturer(systems, 'Nintendo').map((s) => s.id),
        ['nes', 'snes']);
    expect(systemsForManufacturer(systems, null), systems);
    final config = AppConfig(systems: [
      for (final s in systems)
        SystemConfig(
            id: s.id,
            name: s.name,
            targetFolder: '/${s.id}',
            providers: const []),
    ]);
    final subset = ConfigBootstrap.forManufacturer(config, 'Nintendo');
    expect(subset.systems.map((s) => s.id), ['nes', 'snes']);
    expect(subset.sources, same(config.sources));
    expect(config.systems, hasLength(4));
    expect(ConfigBootstrap.forManufacturer(config, 'Atari').systems, isEmpty);
  });
}
