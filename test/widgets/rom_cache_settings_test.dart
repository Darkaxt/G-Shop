import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g_shop/core/input/global_input_wrapper.dart';
import 'package:g_shop/features/settings/rom_cache_settings_screen.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/models/rom_cache_policy.dart';
import 'package:g_shop/services/rom_cache_runtime.dart';
import 'package:g_shop/services/rom_cache_store.dart';
import 'package:sqflite/sqflite.dart';
import '../helpers/pump_helpers.dart';

// UI boundary only: real policy/configuration models, no network or disk IO in
// the widget clock. Durable policy/removal workflows have separate integration tests.
class _Runtime extends RomCacheRuntime {
  RomCachePolicy policy = RomCachePolicy();
  bool includeGames = false, pinned = false;
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
    final games = <RomCacheGame>[
      if (includeGames)
        RomCacheGame(
            RomCacheEntry(
                id: 'fixture',
                platform: 'gba',
                bytes: 1024,
                installedAt: time,
                pinned: pinned),
            'Fixture game',
            [],
            null),
    ];
    latest = RomCacheSnapshot(
        policy, games, policy.plan(games.map((g) => g.entry), now: time),
        time: time, clockTrusted: true);
    return latest!;
  }

  @override
  Future<void> updatePolicy(RomCachePolicy value) async {
    policy = value;
    await snapshot();
    notifyListeners();
  }

  @override
  Future<void> setPinned(String id, bool value) async {
    expect(id, 'fixture');
    pinned = value;
    await snapshot();
    notifyListeners();
  }
}

void main() {
  Future<_Runtime> open(WidgetTester tester,
      {bool includeGames = false}) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _Runtime()..includeGames = includeGames;
    addTearDown(runtime.dispose);
    await tester.pumpWidget(ProviderScope(
        child: GlobalInputWrapper(
            child: createTestApp(RomCacheSettingsScreen(runtime: runtime)))));
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
      'cache bumpers switch sections and controller saves numeric dialog',
      (tester) async {
    final runtime = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('cache-section-consoles')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cache-section-policy')), findsOneWidget);
    // Open the real field; the dialog must retain the app's controller actions,
    // rather than falling back to the global logical game-list confirm event.
    await tester.ensureVisible(find.byKey(const ValueKey('cache-retention')));
    await tester.tap(find.byKey(const ValueKey('cache-retention')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('cache-value-keepMilliseconds')), '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    // Reach Save within the actual dialog focus tree, using only direction keys.
    for (var i = 0;
        i < 3 && !Focus.of(tester.element(find.text('Save'))).hasFocus;
        i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(Focus.of(tester.element(find.text('Save'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(runtime.policy.defaults.keepFor, isNull,
        reason: 'Editing the draft must not apply or evict anything');
    expect(find.text('2.00 days'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cache-apply')));
    await tester.pumpAndSettle();
    expect(runtime.policy.defaults.keepFor, const Duration(days: 2));
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
  testWidgets('controller traverses cache policy dropdowns Apply and game pins',
      (tester) async {
    final runtime = await open(tester, includeGames: true);
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      // Synthetic input spacing for the existing global 150 ms debounce.
      await tester.pump(const Duration(milliseconds: 151));
      await tester.pumpAndSettle();
    }

    bool inside(Key key) {
      final target = tester.element(find.byKey(key));
      var found = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        found = found || e == target;
        return !found;
      });
      return found;
    }

    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.arrowRight);
    expect(inside(const ValueKey('cache-enabled')), isTrue);
    await press(LogicalKeyboardKey.gameButtonA);
    expect(runtime.policy.enabled, isFalse);
    await press(LogicalKeyboardKey.arrowDown);
    expect(inside(const ValueKey('cache-scope')), isTrue);
    await press(LogicalKeyboardKey.gameButtonA);
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.gameButtonA);
    await press(LogicalKeyboardKey.arrowDown);
    expect(inside(const ValueKey('cache-order')), isTrue);
    await press(LogicalKeyboardKey.gameButtonA);
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.gameButtonA);
    // Walk the retention/game/storage limits to the real footer, including
    // automatic scrolling of offscreen focused Material controls.
    for (var i = 0; i < 8 && !inside(const ValueKey('cache-apply')); i++) {
      await press(LogicalKeyboardKey.arrowDown);
    }
    expect(inside(const ValueKey('cache-apply')), isTrue);
    await press(LogicalKeyboardKey.gameButtonA);
    expect(runtime.policy.enabled, isTrue);
    expect(runtime.policy.scope, RomCacheScope.perConsole);
    expect(runtime.policy.order, RomCacheOrder.fifo);
    await press(LogicalKeyboardKey.gameButtonRight1);
    expect(
        find.byKey(const ValueKey('cache-section-consoles')), findsOneWidget);
    await press(LogicalKeyboardKey.gameButtonRight1);
    expect(find.byKey(const ValueKey('cache-section-games')), findsOneWidget);
    // Enter the games content from its section destination.
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowRight);
    if (!inside(const ValueKey('cache-pin-fixture'))) {
      await press(LogicalKeyboardKey.arrowDown);
    }
    expect(inside(const ValueKey('cache-pin-fixture')), isTrue);
    await press(LogicalKeyboardKey.gameButtonA);
    expect(runtime.pinned, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
