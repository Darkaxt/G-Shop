import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/game_detail/widgets/action_buttons_row.dart';
import 'package:retro_eshop/features/game_detail/widgets/download_action_button.dart';
import '../helpers/pump_helpers.dart';

void main() {
  for (final focused in [false, true]) {
    testWidgets('Delete stays readable on red backgrounds (focused=$focused)',
        (tester) async {
      var selections = 0;
      await tester.pumpWidget(createTestApp(ActionButtonsRow.primaryOnly(
          accentColor: Colors.redAccent,
          downloadButtonState: DownloadButtonState.delete,
          onPrimaryAction: () => selections++,
          hintText: 'Press A to manage',
          isSectionFocused: focused)));
      final label = tester.widget<Text>(find.text('DELETE'));
      expect(label.style!.color, Colors.white);
      final button = tester.widget<AnimatedContainer>(find
          .ancestor(
              of: find.text('DELETE'), matching: find.byType(AnimatedContainer))
          .first);
      final background = (button.decoration! as BoxDecoration).color!;
      expect(background.a, 1);
      expect(1.05 / (background.computeLuminance() + 0.05),
          greaterThanOrEqualTo(4.5));
      expect(
          tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded)).color,
          Colors.white);
      await tester.tap(find.text('DELETE'));
      expect(selections, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('verified local primary action is Open, not Delete',
      (tester) async {
    var opens = 0;
    await tester.pumpWidget(createTestApp(ActionButtonsRow.primaryOnly(
        accentColor: Colors.cyan,
        downloadButtonState: DownloadButtonState.open,
        onPrimaryAction: () {
          opens++;
        },
        hintText: 'Press A to open',
        isSectionFocused: true)));
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('DELETE'), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.text('OPEN'));
    expect(opens, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
