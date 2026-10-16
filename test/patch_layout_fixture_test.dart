import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/patch_catalogue.dart';
import 'package:retro_eshop/services/drive/drive_patch_catalogue.dart';

class _LayoutCatalogue extends DrivePatchCatalogue {
  final Directory root;
  _LayoutCatalogue(this.root)
      : super(const ProviderConfig(type: ProviderType.drive, priority: 1));
  @override
  Future<Map<String, dynamic>> read(
          PatchRelativePath reference, CancelToken cancellation) async =>
      (jsonDecode(await File(p.joinAll([root.path, ...reference.segments]))
              .readAsString()) as Map)
          .cast<String, dynamic>();
}

void main() {
  const privateRoot = String.fromEnvironment('RSHOP_PRIVATE_PATCH_ROOT');
  if (privateRoot.isNotEmpty) {
    test(
        'current original schema two indexes parse without rewriting the collection',
        () async {
      final reader = _LayoutCatalogue(Directory(privateRoot));
      final index = await reader.read(
          PatchRelativePath('Nintendo - Game Boy Advance/Patches/index.json'),
          CancelToken());
      expect(index['schema_version'], 2);
      final rows = (index['games'] as List).cast<Map>();
      final selected = [
        rows.first,
        rows.firstWhere((row) => row['source_game_id'].toString() == '1379')
      ];
      for (final row in selected) {
        final game = IndexedPatchGame(
            row['source_game_id'].toString(),
            row['title'] as String,
            PatchRelativePath(row['rom_root_relative_path'] as String));
        final patches = await reader.patches(game, CancelToken());
        expect(patches, isNotEmpty);
        expect(patches.any((patch) => patch.payloads.isNotEmpty), isTrue);
      }
    });
  }
  test('documented source indexes resolve unchanged beneath independent roots',
      () async {
    final original = Directory('docs/examples/patch-collection');
    final destination = await Directory.systemTemp.createTemp('rshop-layout-');
    final roots = [original, destination];
    for (final entity in await original.list(recursive: true).toList()) {
      if (entity is File) {
        final target = File(p.join(
            destination.path, p.relative(entity.path, from: original.path)));
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
    }
    for (final root in roots) {
      final reader = _LayoutCatalogue(root);
      final index = await reader.read(
          PatchRelativePath('GBA/Patches/index.json'), CancelToken());
      final row = (index['games'] as List).single as Map;
      final game = IndexedPatchGame(
          row['source_game_id'] as String,
          row['title'] as String,
          PatchRelativePath(row['rom_root_relative_path'] as String));
      final patch = (await reader.patches(game, CancelToken())).single;
      expect(patch.bases.single.archiveMember!.value, 'Example Original.gba');
      expect(patch.bases.single.checksums['sha256'], 'a' * 64);
      expect(patch.payloads.single.relativePath,
          'GBA/Patches/Example/Synthetic/Balance/balance.ips');
      expect(patch.payloads.single.format, PatchFormat.ips);
    }
  });
}
