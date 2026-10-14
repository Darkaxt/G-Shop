import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/settings/rom_cache_settings_screen.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/system_config.dart';
import 'package:retro_eshop/models/rom_cache_policy.dart';
import 'package:retro_eshop/services/rom_cache_runtime.dart';
import 'package:retro_eshop/services/rom_cache_store.dart';
import 'package:sqflite/sqflite.dart';
import '../helpers/pump_helpers.dart';

// UI boundary only: real policy/configuration models, no network or disk IO in
// the widget clock. Durable policy/removal workflows have separate integration tests.
class _Runtime extends RomCacheRuntime {
  RomCachePolicy policy = RomCachePolicy();
  _Runtime()
      : super(
            store: RomCacheStore(Completer<Database>().future),
            configuration: () async => AppConfig(systems: [
                  for (final id in ['gba', 'psx'])
                    SystemConfig(
                        id: id,
                        name: id.toUpperCase(),
                        targetFolder: '/roms/$id',
                        providers: [])
                ], sources: []));
  @override
  Future<RomCacheSnapshot> snapshot(
      {bool preview = false, bool recovering = false}) async {
    final time = DateTime.utc(2026, 10, 14);
    latest = RomCacheSnapshot(policy, [], policy.plan([], now: time),
        time: time, clockTrusted: true);
    return latest!;
  }

  @override
  Future<void> updatePolicy(RomCachePolicy value) async {
    policy = value;
    await snapshot();
    notifyListeners();
  }
}

void main() {
  Future<_Runtime> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _Runtime();
    addTearDown(runtime.dispose);
    await tester.pumpWidget(
        createTestAppWithProviders(RomCacheSettingsScreen(runtime: runtime)));
    await tester.pumpAndSettle();
    return runtime;
  }

  testWidgets(
      'cache settings mount one section and keep cleanup disabled until applied',
      (tester) async {
    final runtime = await open(tester);
    expect(find.byKey(const ValueKey('cache-section-policy')), findsOneWidget);
    expect(find.byKey(const ValueKey('cache-section-status')), findsNothing);
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('cache-enabled')))
            .value,
        isFalse);
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cache-enabled')), findsNothing);
    expect(find.byKey(const ValueKey('cache-check')), findsOneWidget);
    await tester.tap(find.text('Policy'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cache-enabled')));
    await tester.pumpAndSettle();
    expect(runtime.policy.enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('cache-apply')));
    await tester.pumpAndSettle();
    expect(runtime.policy.enabled, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('controller can enter the controls from initial screen focus',
      (tester) async {
    await open(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'Screen_rom-cache-settings');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        isNot('Screen_rom-cache-settings'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<NavigationRail>(
                find.byKey(const ValueKey('cache-sections')))
            .selectedIndex,
        1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
      'custom retention and explicit Never override retain per-console inheritance',
      (tester) async {
    final runtime = await open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('cache-retention')));
    await tester.tap(find.byKey(const ValueKey('cache-retention')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('cache-value-keepMilliseconds')), '0.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consoles'));
    await tester.pumpAndSettle();
    expect(find.text('Inherited · 0.50 days'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cache-retention')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('cache-value-keepMilliseconds')), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Never'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cache-apply')));
    await tester.pumpAndSettle();
    expect(runtime.policy.defaults.keepFor, const Duration(hours: 12));
    expect(runtime.policy.consoles['gba'], {'keepMilliseconds': null});
    expect(
        runtime.policy
            .copyWith(scope: RomCacheScope.perConsole)
            .limitsFor('psx')
            .keepFor,
        const Duration(hours: 12));
    await tester.tap(find.byKey(const ValueKey('cache-retention')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inherit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cache-apply')));
    await tester.pumpAndSettle();
    expect(runtime.policy.consoles, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
