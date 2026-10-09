import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/game_detail/widgets/action_buttons_row.dart';
import 'package:retro_eshop/features/game_detail/widgets/download_action_button.dart';
import '../helpers/pump_helpers.dart';

void main() {
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
