import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/console_model.dart';
import 'package:g_shop/models/nes_cartridge_model.dart';
import 'package:g_shop/models/nes_media_catalogue.dart';
import 'package:g_shop/models/socket_media_model.dart';

// An opt-in acceptance check against the actual private conversion. No artwork,
// collection inventory or authored third-party mesh enters the public test tree.
void main() {
  final path = Platform.environment['GSHOP_NES_IMPORTS'];
  test('all deployed NES imports pass production loaders and texture receipts',
      () async {
    final root = Directory(path!);
    final catalogue = (await NesMediaCatalogue.load(modelsDirectory: root))!;
    expect(catalogue.editions.length, 623);
    for (final edition in catalogue.editions.values) {
      final box = (await edition.load(modelsDirectory: root))!;
      expect(box.canOpen, isTrue);
      expect(box.retailEditionId, edition.id);
      final model = await box.load();
      expect(model.data['animationVerifiedMaxError'], lessThan(.0001));
      for (final name in (model.data['textureFiles'] as Map).keys) {
        expect(
            (await model.textureBundle!
                    .load('${SocketMediaModel.assetRoot}$name'))
                .lengthInBytes,
            greaterThan(0));
      }
    }
    for (final style in NesCartridgeModel.labels.keys) {
      final model =
          (await NesCartridgeModel.load(style, modelsDirectory: root))!;
      expect(model.data['cartridgeStyle'], style);
      if (style == 'active-clear') {
        expect(
            model.surfaces.any(
                (s) => s['material']['sourceProperties']['transmission'] == 1),
            isTrue);
        expect(
            model.surfaces.any((s) => '${s['name']}'.contains('PCB')), isTrue);
      }
    }
    final scene = (await ConsoleModel.find('nes', modelsDirectory: root))!;
    expect(scene.isCollectionOverview, isTrue);
    final geometry = await scene.load();
    expect(geometry.data['sourceReference']['overview']['objects'],
        hasLength(290));
    for (final name in (geometry.data['textureFiles'] as Map).keys) {
      await geometry.textureBundle!.load('${SocketMediaModel.assetRoot}$name');
    }
    for (final variant in ['front-loader', 'top-loader']) {
      await (await ConsoleModel.findNesConsoleVariant(variant,
              modelsDirectory: root))!
          .load();
    }
    final census = File('${root.parent.path}/reports/nes-rom-census.json');
    if (await census.exists()) {
      final entries =
          jsonDecode(await census.readAsString())['entries'] as List;
      final families = <String, int>{};
      var referenced = 0;
      for (final entry in entries) {
        final choices = NesCartridgeModel.referencesFor(entry['filename']);
        if (choices.isNotEmpty) referenced++;
        for (final style in choices) {
          families.update(style, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      await File('${root.parent.path}/reports/nes-shell-coverage.json')
          .writeAsString(jsonEncode({
        'archives': entries.length,
        'archivesWithShellReferences': referenced,
        'styleReferences': families,
        'meaning': 'Reference families; not an exact owned physical SKU census'
      }));
    }
  }, skip: path == null ? 'Private NES imports were not supplied' : false);
}
