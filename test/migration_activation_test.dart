import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_eshop/services/migration/migration_activation.dart';

class MemorySettings implements MigrationSettings {
  Map<String, Object?> preferences = {
    'favorites': ['destination-game']
  };
  Map<String, String> secrets = {'api': 'destination-secret'};
  @override
  Future<Map<String, Object?>> readPreferences() async => Map.from(preferences);
  @override
  Future<void> writePreferences(Map<String, Object?> values) async =>
      preferences = Map.from(values);
  @override
  Future<Map<String, String>> readSecrets() async => Map.from(secrets);
  @override
  Future<void> writeSecrets(Map<String, String> values) async =>
      secrets = Map.from(values);
}

void main() {
  late Directory root;
  late MemorySettings settings;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('migration-activation-');
    settings = MemorySettings();
  });
  tearDown(() async => root.delete(recursive: true));

  test('complete activation keeps the destination setup recoverable', () async {
    final target = await File(p.join(root.path, 'live', 'config.json'))
        .create(recursive: true);
    await target.writeAsString('destination setup');
    final source =
        await File(p.join(root.path, 'incoming')).writeAsString('source setup');
    final activation = MigrationActivation(
        privateRoot: Directory(p.join(root.path, 'private')),
        settings: settings,
        allowedRoots: [Directory(p.join(root.path, 'live'))]);
    await activation.prepare(files: {
      target.path: source
    }, preferences: {
      'favorites': ['source-game']
    }, secrets: {
      'api': 'source-secret'
    });
    await activation.activate();
    expect(await target.readAsString(), 'source setup');
    expect(settings.preferences, {
      'favorites': ['source-game']
    });
    expect(settings.secrets['api'], 'source-secret');
    final record = jsonDecode(await activation.journal.readAsString()) as Map;
    expect(record['phase'], 'committed');
    expect(await File(record['files'][0]['old'] as String).readAsString(),
        'destination setup');
    expect(settings.secrets[record['rollbackKey']],
        contains('destination-secret'));
    expect(await activation.journal.readAsString(),
        isNot(contains('source-secret')));
    // Restart recovery never reverses a committed migration.
    await activation.recover();
    expect(await target.readAsString(), 'source setup');
  });

  test('startup rolls back interrupted file/settings activation coherently',
      () async {
    final target = await File(p.join(root.path, 'live', 'config.json'))
        .create(recursive: true);
    await target.writeAsString('old bytes');
    final source =
        await File(p.join(root.path, 'incoming')).writeAsString('new bytes');
    final activation = MigrationActivation(
        privateRoot: Directory(p.join(root.path, 'private')),
        settings: settings,
        allowedRoots: [Directory(p.join(root.path, 'live'))]);
    await activation.prepare(
        files: {target.path: source},
        preferences: {'new': true},
        secrets: {'api': 'new-secret'});
    final record = jsonDecode(await activation.journal.readAsString()) as Map;
    final file = record['files'][0] as Map;
    // Exact on-disk state after process death between swaps and secure activation.
    await target.rename(file['old'] as String);
    await File(file['incoming'] as String).rename(target.path);
    settings.preferences = {'new': true};
    settings.secrets['api'] = 'new-secret';
    final restarted = MigrationActivation(
        privateRoot: activation.privateRoot,
        settings: settings,
        allowedRoots: activation.allowedRoots);
    await restarted.recover();
    expect(await target.readAsString(), 'old bytes');
    expect(settings.preferences, {
      'favorites': ['destination-game']
    });
    expect(settings.secrets, {'api': 'destination-secret'});
    expect(await activation.journal.exists(), false);
  });
}
