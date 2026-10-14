import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/core/widgets/animated_background.dart';
import 'package:retro_eshop/core/widgets/radial_glow.dart';
import 'package:retro_eshop/core/widgets/screen_layout.dart';
import 'package:retro_eshop/features/game_list/widgets/dynamic_background.dart';
import 'package:retro_eshop/features/settings/settings_screen.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/storage_service.dart';
import '../helpers/pump_helpers.dart';

void main() {
  testWidgets('Settings does not cover the red backdrop with a grey gradient',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await tester.pumpWidget(createTestAppWithProviders(
      const SettingsScreen(),
      overrides: [storageServiceProvider.overrideWithValue(storage)],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedBackground), findsOneWidget);
    for (final finder in [find.byType(Container), find.byType(AnimatedContainer)]) {
      for (final element in finder.evaluate()) {
        final widget = element.widget;
        final decoration = widget is Container
            ? widget.decoration
            : (widget as AnimatedContainer).decoration;
        if (decoration is! BoxDecoration || decoration.gradient == null) continue;
        for (final color in decoration.gradient!.colors.where((c) => c.a > 0)) {
          expect(color.r, greaterThan(color.g));
          expect(color.r, greaterThan(color.b));
        }
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('screen backdrop stays red with a green console accent',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ScreenLayout(accentColor: Colors.green, body: Text('Console')),
    ));
    final glow = tester.widget<AnimatedContainer>(find.descendant(
        of: find.byType(RadialGlow), matching: find.byType(AnimatedContainer)));
    final colors = (glow.decoration! as BoxDecoration).gradient!.colors;
    for (final color in colors.where((c) => c.a > 0)) {
      expect(color.r, greaterThan(color.g));
      expect(color.r, greaterThan(color.b));
    }
  });

  testWidgets('console accents do not replace the red background',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Stack(children: [
        AnimatedBackground(accentColor: Colors.green),
        DynamicBackground(accentColor: Colors.blue),
      ]),
    ));
    final animated = tester.widget<AnimatedContainer>(
      find.descendant(
          of: find.byType(AnimatedBackground),
          matching: find.byType(AnimatedContainer)),
    );
    final dynamic = tester.widget<Container>(
      find.descendant(
          of: find.byType(DynamicBackground), matching: find.byType(Container)),
    );
    for (final decoration in [animated.decoration, dynamic.decoration]) {
      final gradient = (decoration! as BoxDecoration).gradient!;
      for (final color in gradient.colors) {
        expect(color.r, greaterThan(color.g));
        expect(color.r, greaterThan(color.b));
        expect(color.a, 1);
      }
    }
    expect(AppTheme.backgroundColor.r, greaterThan(AppTheme.backgroundColor.g));
    expect(AppTheme.backgroundColor.r, greaterThan(AppTheme.backgroundColor.b));
  });
}
