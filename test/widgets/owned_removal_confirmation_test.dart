import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/widgets/confirm_dialog.dart';
import '../helpers/pump_helpers.dart';

void main() {
  testWidgets('long removal paths keep both actions reachable in landscape', (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var cancelled = false;
    await tester.pumpWidget(createTestApp(ConfirmDialog(type: ConfirmDialogType.delete,
        selection: 1, gameTitle: 'An unusually long game name with a specific revision',
        details: '${List.filled(12, '/storage/75D7-DC5F/Roms/Long folder/exact-owned-ROM.chd').join('\n')}\n1.2 GB',
        onPrimary: () {}, onSecondary: () => cancelled = true)));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('CANCEL'));
    expect(cancelled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('removal confirmation shows exact local path and reclaimed size',
      (tester) async {
    var removed = false;
    await tester.pumpWidget(createTestApp(ConfirmDialog(
        type: ConfirmDialogType.delete,
        selection: 1,
        gameTitle: 'Fixture',
        details: '/storage/fixture/Game.chd\n42 B',
        onPrimary: () => removed = true,
        onSecondary: () {})));
    expect(find.text('/storage/fixture/Game.chd\n42 B'), findsOneWidget);
    expect(removed, isFalse);
    await tester.tap(find.text('DELETE'));
    expect(removed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
