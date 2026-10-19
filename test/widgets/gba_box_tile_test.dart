import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:retro_eshop/models/packaging_model.dart';
import 'package:retro_eshop/services/metadata/effective_overall_rating.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/providers/metadata_cloud_providers.dart';
import 'package:retro_eshop/widgets/base_game_card.dart';
import 'package:retro_eshop/widgets/gba_box_tile.dart';
import 'package:retro_eshop/widgets/socket_media_renderer.dart';
import '../helpers/pump_helpers.dart';
import 'cover_rating_test.dart' show score;

void main() {
  testWidgets('mounted GBA box paints its arriving exact score into the atlas',
      (tester) async {
    final rating = Completer<EffectiveOverallRating?>();
    final selections = <({String platform, String selection})>[];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          boxCardMediaProvider.overrideWith((ref, selection) async => {}),
          cloudSelectionMediaProvider
              .overrideWith((ref, selection) async => null),
          cachedSelectionRatingProvider.overrideWith((ref, selection) {
            selections.add(selection);
            return rating.future;
          }),
        ],
        child: createTestApp(Center(
            child: SizedBox(
                width: 300,
                height: 300,
                child: BaseGameCard(
                    displayName: 'Fixture',
                    systemId: 'gba',
                    gameIdentity: 'Fixture.gba',
                    coverUrls: const [],
                    cachedUrl: null,
                    isInstalled: false,
                    isSelected: false,
                    accentColor: Colors.red,
                    onTap: () {}))))));
    expect(tester.widget<GbaBoxTile>(find.byType(GbaBoxTile)).score, isNull);
    rating.complete(score(value: 84));
    await tester.pump();
    await tester.pump();
    expect(selections, [(platform: 'gba', selection: 'Fixture.gba')]);
    final tile = tester.widget<GbaBoxTile>(find.byType(GbaBoxTile));
    expect(tile.score, isNotNull);
    final renderer =
        tester.widget<SocketMediaRenderer>(find.byType(SocketMediaRenderer));
    final atlas = renderer.label;
    await tester.pumpWidget(createTestApp(
        Center(child: SizedBox(width: 600, height: 400, child: atlas))));
    await tester.pump();
    expect(find.text('8.4'), findsOneWidget);
    final badge = tester.getRect(find.byKey(const ValueKey('cover-rating')));
    expect(badge.right, lessThanOrEqualTo(400));
    await tester.pumpWidget(const SizedBox());
  });

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
    // A real mesh almost head-on still reads as a flat cover. Require visible
    // physical depth at the shelf camera, rather than testing its type alone.
    final model = renderer.packaging!.build();
    final projection = SocketMediaGpu.cameraProjection(400, 300, 100)
      ..multiply(SocketMediaGpu.modelTransform(model, renderer.pose));
    Offset projected(double x, double y, double z) {
      final p = projection.transform(vm.Vector4(x, y, z, 1));
      return Offset(p.x / p.w * 200, p.y / p.w * 150);
    }

    final halfDepth = renderer.packaging!.depth / 2;
    final frontRight = projected(1, 0, halfDepth);
    final frontLeft = projected(-1, 0, halfDepth);
    final backRight = projected(1, 0, -halfDepth);
    expect(
        (frontRight - backRight).distance / (frontRight - frontLeft).distance,
        greaterThan(.09),
        reason: 'The closed box side must be clearly visible, not a sliver');
    expect(renderer.pose.rx.abs(), greaterThanOrEqualTo(.1),
        reason: 'The shelf camera must also reveal a top edge');
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
