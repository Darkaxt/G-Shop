import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/services/migration/migration_data.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('migration-db-'));
  tearDown(() async => root.delete(recursive: true));

  test(
      'snapshot is standalone; restore retains facts, not source ownership/work',
      () async {
    final db =
        await databaseFactoryFfi.openDatabase(p.join(root.path, 'source.db'));
    await db.setVersion(41);
    for (final table in [
      'games',
      'transfer_records',
      'installed_artifacts',
      'transfer_target_owners',
      'owned_removals',
      'rom_cache_decisions',
      'drive_catalogue_work',
      'save_backup_game_jobs'
    ]) {
      await db.execute(
          'CREATE TABLE $table(id TEXT PRIMARY KEY, record_json TEXT)');
      await db.insert(table, {
        'id': table,
        'record_json': jsonEncode({
          'path': '/source/roms/game.gba',
          'cloud': 'cloud-id',
          'deviceImportChoices': {'choice': 'ignore'},
        })
      });
    }
    await db.execute('CREATE TABLE automatic_save_backups(mapping_key TEXT, '
        'record_json TEXT, enabled INTEGER, requested INTEGER, handled INTEGER, '
        'outcome TEXT, issue TEXT)');
    await db.insert('automatic_save_backups', {
      'mapping_key': 'source-watch',
      'record_json': '{}',
      'enabled': 1,
      'requested': 9,
      'handled': 2
    });
    await db.execute(
        'CREATE TABLE patch_builds(build_id TEXT PRIMARY KEY,state TEXT,record_json TEXT)');
    for (final state in ['ready', 'publishing']) {
      await db.insert('patch_builds', {
        'build_id': state,
        'state': state,
        'record_json': jsonEncode({
          'inputTransfers': ['old-device-transfer'],
          'transferId': 'old-device-output',
          'outputArtifact': {'id': 'output'},
          'scratchCleanup': '/source/private/scratch'
        })
      });
    }
    final file = File(p.join(root.path, 'snapshot.db'));
    await MigrationData.snapshotDatabase(db, file);
    await db.update('games', {'record_json': '{}'});
    await db.close();
    final restored = await databaseFactoryFfi.openDatabase(file.path);
    await MigrationData.prepareDatabase(restored,
        paths: MigrationPaths({'/source/roms': '/destination/roms'}));
    final game = jsonDecode(
        (await restored.query('games')).single['record_json'] as String);
    expect(game['path'], '/destination/roms/game.gba');
    expect(game['cloud'], 'cloud-id');
    for (final table in [
      'transfer_records',
      'installed_artifacts',
      'transfer_target_owners',
      'owned_removals',
      'rom_cache_decisions',
      'drive_catalogue_work',
      'automatic_save_backups',
      'save_backup_game_jobs'
    ]) {
      expect(await restored.query(table), isEmpty, reason: table);
    }
    final histories = await restored.query('migration_save_history');
    expect(histories.single['source_key'], 'save_backup_game_jobs');
    expect(
        jsonDecode(
            histories.single['record_json'] as String)['deviceImportChoices'],
        {'choice': 'ignore'});
    expect(
        (await restored.query('migration_save_mappings')).single['enabled'], 1);
    final builds = await restored.query('patch_builds', orderBy: 'build_id');
    final interrupted = builds.first;
    expect(interrupted['state'], 'failed');
    final interruptedRecord =
        jsonDecode(interrupted['record_json'] as String) as Map;
    expect(interruptedRecord['inputTransfers'], isEmpty);
    expect(interruptedRecord['issue'], 'migration_requires_rebuild');
    expect(interruptedRecord.containsKey('transferId'), false);
    expect(interruptedRecord.containsKey('outputArtifact'), false);
    expect(builds.last['state'], 'ready');
    await restored.close();
  });

  test('path rebinding respects boundaries, longest roots, JSON and cloud URLs',
      () {
    final paths = MigrationPaths({'/old': '/new', '/old/sd/roms': '/sd/roms'});
    expect(paths.value('/old/sd/roms/a'), '/sd/roms/a');
    expect(paths.value('/older/a'), '/older/a');
    expect(paths.value('https://example.com/old'), 'https://example.com/old');
    expect(jsonDecode(paths.value('{"nested":["/old/a"]}') as String), {
      'nested': ['/new/a']
    });
    expect(
        paths.value({
          'root': '/old',
          'ids': ['cloud-id']
        }),
        {
          'root': '/new',
          'ids': ['cloud-id']
        });
  });
}
