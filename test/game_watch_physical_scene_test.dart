import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'game_watch_unboxing_test.dart' show vertices;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:g_shop/features/preview/game_watch_variants_preview.dart';
import 'package:g_shop/models/console_model.dart';
import 'package:g_shop/models/game_watch_unboxing_scene.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final privateRoot = Platform.environment['RSHOP_GAMEWATCH_MODEL_DIR'];
  test('shared physical camera preserves size ratios and rear-centre support',
      () {
    final layout =
        GameWatchVariantsViewState.physicalLayout(const Size(1240, 1080), [
      const Rect.fromLTWH(0, 0, 1.6, 1),
      const Rect.fromLTWH(0, 0, 1.9, 2),
      const Rect.fromLTWH(0, 0, 2.9, 2.4)
    ]);
    expect(layout.hitBounds[0].width / layout.hitBounds[1].width,
        closeTo(1.6 / 1.9, .0001));
    expect(layout.hitBounds[0].bottom, lessThan(layout.hitBounds[1].bottom));
    expect(layout.hitBounds[0].bottom, lessThan(layout.hitBounds[2].bottom));
    final envelope = layout.hitBounds.reduce((a, b) => a.expandToInclude(b));
    expect(envelope.left, greaterThanOrEqualTo(155 - .001));
    expect(envelope.right, lessThanOrEqualTo(1085 + .001));
    expect(envelope.top, greaterThanOrEqualTo(135 - .001));
    expect(envelope.bottom, lessThanOrEqualTo(945 + .001));
    expect(layout.hitBounds[1].right, lessThan(layout.hitBounds[0].left));
    expect(layout.hitBounds[0].right, lessThan(layout.hitBounds[2].left));
  });
  test(
      'real editions preserve physical widths, fit their boxes and share animation framing',
      () async {
    final root = privateRoot!;
    final variants = await ConsoleModel.findGameWatchVariants('gnw_dkjr.zip',
        modelsDirectory: Directory(root));
    final pairs = <SocketMediaModel>[];
    final scenes = <GameWatchUnboxingScene>[];
    for (final variant in variants) {
      final scene = GameWatchUnboxingScene(variant.model, variant.box!);
      scenes.add(scene);
      final pair = await scene.load();
      pairs.add(pair);
      final box = (pair.data['boxClosedBounds'] as List).cast<List>();
      final console = (pair.data['consoleClosedBounds'] as List).cast<List>();
      final boxWidth = (box[1][0] as num) - (box[0][0] as num);
      final consoleWidth = (console[1][0] as num) - (console[0][0] as num);
      final ratio = boxWidth *
          (pair.data['boxScale'] as num) /
          (consoleWidth * (pair.data['consoleRestScale'] as num));
      debugPrint('GameWatchScaleDiagnostic ${jsonEncode({
            'hardware': variant.model.hardwareId,
            'boxClosedBounds': box,
            'consoleClosedBounds': console,
            'seatScale': pair.data['seatScale'],
            'consoleRestScale': pair.data['consoleRestScale'],
            'finalBoxToHandheldWidthRatio': ratio,
            'restingPitch': pair.data['consoleRestPitch'],
            'physicalCalibration': pair.data['physicalCalibration'],
            'rawFitRatios': [
              for (var a = 0; a < 3; a++)
                ((box[1][a] as num) - (box[0][a] as num)) *
                    .88 /
                    ((console[1][a] as num) - (console[0][a] as num))
            ],
          })}');
      expect(ratio, lessThan(2.3),
          reason: 'No tiny contents caused by a shallow carton axis');
      if (variant.model.hardwareId == 'gnw_dkjr') {
        expect(ratio, closeTo(.16 / .111, .0001));
      }
      final seated = vertices(pair, 'console', const SocketMediaPose());
      final cavity = (pair.data['seatingBounds'] as List).cast<List>();
      for (var a = 0; a < 3; a++) {
        expect(seated.map((v) => v[a]).reduce(math.min),
            greaterThan(cavity[0][a]));
        expect(
            seated.map((v) => v[a]).reduce(math.max), lessThan(cavity[1][a]));
      }
    }
    expect(pairs.length, 3);
    final duration = scenes.fold(0, (sum, s) => sum + s.durationMs);
    SocketMediaPose pose(int i, double progress, {double yawOffset = 0}) =>
        SocketMediaPose(
            unboxing: progress,
            opening: scenes[i].handheldOpening(progress),
            rx: .18,
            ry: (i == 0
                        ? 0
                        : i == 1
                            ? .95
                            : -.95) *
                    .35 +
                yawOffset,
            scaleX: .9,
            scaleY: .9,
            scaleZ: .9);
    final settled = [
      for (var i = 0; i < 3; i++)
        SocketMediaGpu.compositionBounds(
                pairs[i], pose(i, 1, yawOffset: -.16), const Size(1, 1), 1)
            .expandToInclude(SocketMediaGpu.compositionBounds(
                pairs[i], pose(i, 1, yawOffset: .16), const Size(1, 1), 1))
    ];
    for (var step = 0; step <= 30; step++) {
      var prior = 0;
      final poses = [
        for (var i = 0; i < 3; i++)
          () {
            final local = (step / 30 * duration - prior) / scenes[i].durationMs;
            prior += scenes[i].durationMs;
            return pose(i, local.clamp(0.0, 1.0));
          }()
      ];
      final current = [
        for (var i = 0; i < 3; i++)
          SocketMediaGpu.compositionBounds(
              pairs[i], poses[i], const Size(1, 1), 1)
      ];
      final layout = GameWatchVariantsViewState.physicalLayout(
          const Size(1240, 1080), settled,
          current: current);
      for (var i = 0; i < 3; i++) {
        final transform = SocketMediaGpu.cameraProjection(
                1240, 1080, layout.units,
                center: layout.origins[i]) *
            SocketMediaGpu.modelTransform(pairs[i], poses[i]);
        for (final part in ['box', 'console', 'insert']) {
          for (final point in vertices(pairs[i], part, poses[i])) {
            final v =
                transform.transform(vm.Vector4(point.x, point.y, point.z, 1));
            expect(v.x / v.w, inInclusiveRange(-.751, .751),
                reason: 'edition $i $part x phase $step');
            expect(v.y / v.w, inInclusiveRange(-.751, .751),
                reason: 'edition $i $part y phase $step');
          }
        }
      }
    }
  },
      skip: privateRoot == null
          ? 'Private owner resources are not bundled'
          : false,
      timeout: Timeout.none);
}
