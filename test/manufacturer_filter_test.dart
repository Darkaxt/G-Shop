import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:g_shop/features/home/widgets/manufacturer_filter.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/services/config_bootstrap.dart';

void main() {
  testWidgets(
      'overflow fades only hidden brand edges and focus reveals the logo',
      (tester) async {
    final systems = SystemModel.supportedSystems
        .where((s) => ['Nintendo', 'Sony', 'Sega'].contains(s.manufacturer))
        .toList();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
          width: 440,
          child: ManufacturerFilter(
              systems: systems, selected: null, onSelected: (_) {})),
    ))));
    await tester.pumpAndSettle();
    final mask = find.byKey(const ValueKey('scroll-edge-fade'));
    expect(mask, findsOneWidget);
    var shader = tester.widget<ShaderMask>(mask);
    expect(shader.blendMode, BlendMode.dstIn);
    final sony = find.byKey(const ValueKey('brand-Sony'));
    final button = tester.widget<TextButton>(sony);
    final focus = Focus.of(tester.element(
        find.descendant(of: sony, matching: find.byType(Image)).first));
    focus.requestFocus();
    await tester.pumpAndSettle();
    final viewport = tester.getRect(mask);
    final logo = tester.getRect(sony);
    expect(logo.left, greaterThanOrEqualTo(viewport.left));
    expect(logo.right, lessThanOrEqualTo(viewport.right));
    expect(button.onPressed, isNotNull);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 1200,
      child: ManufacturerFilter(
          systems: systems, selected: null, onSelected: (_) {}),
    ))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scroll-edge-fade')), findsOneWidget);
    final fitted = tester.getRect(find.byKey(const ValueKey('brand-Sony')));
    expect(
        fitted.right,
        lessThanOrEqualTo(tester
            .getRect(find.byKey(const ValueKey('manufacturer-filter')))
            .right));
  });
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
  test('manufacturer chronology leaves sync configuration order untouched', () {
    final systems = SystemModel.supportedSystems
        .where((s) => ['nes', 'psp', 'snes', 'megadrive'].contains(s.id))
        .toList();
    expect(systemsForManufacturer(systems, 'Nintendo').map((s) => s.id),
        ['nes', 'snes']);
    final originalIds = systems.map((s) => s.id).toList();
    expect(systemsForManufacturer(systems, null).map((s) => s.id),
        ['nes', 'megadrive', 'snes', 'psp']);
    expect(systems.map((s) => s.id), originalIds);
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
