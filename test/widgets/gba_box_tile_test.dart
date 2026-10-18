import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/packaging_model.dart';
import 'package:retro_eshop/widgets/gba_box_tile.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';

void main() {
  testWidgets('GBA shelf is a closed static box with face-bound corner badges',
      (tester) async {
    const scoreKey = ValueKey('score-fixture'),
        statusKey = ValueKey('status-fixture');
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: GbaBoxTile(
      identity: 'fixture',
      title: 'Fixture',
      resources: {},
      frontFallback: ColoredBox(color: Colors.red),
      score: SizedBox(key: scoreKey, width: 40, height: 20),
      availability: SizedBox(key: statusKey, width: 24, height: 24),
    ))));
    final renderer =
        tester.widget<SocketMediaRenderer>(find.byType(SocketMediaRenderer));
    expect(renderer.packaging!.kind, PackagingKind.box);
    expect(renderer.unboxingScene, isNull);
    expect(renderer.pose.opening, 0);
    final atlas = renderer.label;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(width: 600, height: 400, child: atlas)))));
    final score = tester.getRect(find.byKey(scoreKey));
    final status = tester.getRect(find.byKey(statusKey));
    // Both belong to the first 200x200 front-face cell, not the outer tile.
    expect(score.right, closeTo(status.right, .01));
    expect(score.top, lessThan(status.top));
    expect(score.width, greaterThan(40));
    await tester.pumpWidget(const SizedBox());
  });
}
