import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/core/theme/app_theme.dart';
import 'package:retro_eshop/core/widgets/animated_background.dart';
import 'package:retro_eshop/features/game_list/widgets/dynamic_background.dart';

void main() {
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
