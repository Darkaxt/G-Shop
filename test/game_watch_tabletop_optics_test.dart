import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/console_model.dart';
import 'package:g_shop/models/game_watch_unboxing_scene.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'game_watch_unboxing_test.dart' show vertices;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['RSHOP_TABLETOP_REPAIR_DIR'];
  test(
      'four supplied Table Top repairs retain one upright display and grounded exact pairs',
      () async {
    const identities = {
      'gnw_dkjr': ('dkjr-tabletop', 'CJ-71'),
      'gnw_mariocm': ('gnw_mariocmt', 'CM-72'),
      'gnw_snoopyp': ('snoopy-tabletop', 'SM-73'),
      'gnw_popeye': ('popeye-tabletop', 'PG-74'),
    };
    for (final entry in identities.entries) {
      final variants = await ConsoleModel.findGameWatchVariants(
          '${entry.key}.zip',
          modelsDirectory: Directory(root!));
      final variant =
          variants.singleWhere((v) => v.model.hardwareId == entry.value.$1);
      final source = await variant.model.load();
      expect(source.data['restingPitchRadians'], 0,
          reason: 'Table Top cabinets retain their upright authored rest');
      expect(source.data['sourceReference']['deviceCode'], entry.value.$2);
      final screen =
          source.surfaces.singleWhere((s) => s['node'] == 'Reflected_Display');
      final lcd = source.surfaces
          .singleWhere((s) => s['node'] == 'Physical_LCD_Underside');
      expect(screen['singleSided'], true);
      expect(screen['material']['textures']['albedo'],
          screen['material']['textures']['emission']);
      expect(lcd['material']['textures'], isEmpty);
      expect(lcd['material']['sourceProperties']['emission'], [0, 0, 0]);
      final offset = screen['vertexOffset'] as int;
      final positions = [
        for (var i = 0; i < screen['vertexCount']; i++)
          [
            for (var j = 0; j < 8; j++)
              source.mesh.getFloat32(offset + i * 32 + j * 4, Endian.little)
          ]
      ];
      final top = positions.reduce((a, b) => a[1] > b[1] ? a : b);
      final bottom = positions.reduce((a, b) => a[1] < b[1] ? a : b);
      expect(top[7], 0,
          reason:
              'Upper-left-origin game image stays upright after conversion');
      expect(bottom[7], 1);
      final pair =
          await GameWatchUnboxingScene(variant.model, variant.box!).load();
      expect(pair.data['consoleRestPitch'], 0);
      expect(variant.box!.hardwareId, variant.model.hardwareId);
      expect(
          vertices(pair, 'console', const SocketMediaPose(unboxing: 1))
              .map((v) => v.y)
              .reduce(math.min),
          closeTo(-.65, .003));
      expect(source.data['physicalScale']['estimated'], true);
    }
  },
      skip: root == null
          ? 'Private optical-repair delivery is not bundled'
          : false);
}
