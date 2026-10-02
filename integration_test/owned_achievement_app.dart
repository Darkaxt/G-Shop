// Debug-only Android proof: exclusive synthetic root/SQLite, no cloud/accounts,
// normal app database or existing ROMs. Restore the normal APK after verification.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/ra_models.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/drive/drive_transfer_engine.dart';
import 'package:retro_eshop/services/installation_index.dart';
import 'package:retro_eshop/services/owned_installation_removal.dart';
import 'package:retro_eshop/services/owned_storage.dart';
import 'package:retro_eshop/services/ra_hash_service.dart';
import 'package:retro_eshop/services/transfer_journal.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('Isolated achievement proof'))));
  unawaited(probe().catchError((Object error) {
    debugPrint('ACHIEVEMENT_PROOF FAILED ${error is OwnedStorageException ? error.code : error is StateError ? error.message : error.runtimeType}');
  }));
}
Future<void> probe() async {
  require(kDebugMode && Platform.isAndroid &&
      (await PackageInfo.fromPlatform()).packageName == 'com.darkaxt.rshop.debug',
      'debug_android_only');
  const root = String.fromEnvironment('RSHOP_ACHIEVEMENT_TEST_ROOT');
  require(RegExp(r'^/storage/[A-Za-z0-9-]+/RShopAchievementProof-[A-Za-z0-9_-]+$')
      .hasMatch(root), 'isolated_root_required');
  final dbPath = '${(await getApplicationSupportDirectory()).path}/${root.split('/').last}.sqlite';
  const resume = bool.fromEnvironment('RSHOP_ACHIEVEMENT_RESUME');
  require(await File(dbPath).exists() == resume &&
      await Directory(root).exists() == resume, 'unexpected_fixture_state');
  if (!resume) await Directory(root).create();
  final db = await openDatabase(dbPath, version: 1,
      onCreate: (db, _) => TransferJournalSchema.install(db));
  await db.execute('''CREATE TABLE IF NOT EXISTS ra_matches (game_filename TEXT NOT NULL,
    system_slug TEXT NOT NULL, ra_game_id INTEGER, match_type TEXT NOT NULL,
    is_mastered INTEGER NOT NULL, last_updated INTEGER,
    PRIMARY KEY(game_filename, system_slug))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS ra_games (ra_game_id INTEGER PRIMARY KEY,
    title TEXT, num_achievements INTEGER, points INTEGER, image_icon TEXT)''');
  DatabaseService.testDatabase = db;
  final journal = TransferJournal(Future.value(db));
  const storage = OwnedStorage();
  final plan = await storage.prepare(root);
  final payload = Uint8List.fromList(List.generate(131085, (i) => i % 251));
  final artifact = RemoteArtifact(id: RemoteArtifactId(providerId: 'drive',
      sourceId: 'synthetic', accountId: 'none', providerFileId: 'achievement'),
      parentId: 'fixture', displayName: 'synthetic.gg', displayPath: 'synthetic.gg',
      sizeBytes: payload.length, version: '1', canDownload: true,
      providerChecksums: {'md5': md5.convert(payload).toString()});
  final game = GameItem(filename: 'synthetic.gg', displayName: 'Synthetic',
      url: '', remoteArtifact: artifact);
  if (resume) {
    final previous = await journal.transfer('achievement');
    require(previous != null && previous.destinationRoot == root &&
        previous.relativePath == game.filename &&
        previous.stagePath == plan.stagePath('achievement') &&
        previous.lifecycle == TransferLifecycle.completed &&
        jsonEncode(previous.artifact.toJson()) == jsonEncode(artifact.toJson()),
        'changed_fixture_preserved');
  } else {
    await journal.create(TransferRecord(id: 'achievement', artifact: artifact,
        destinationRoot: root, relativePath: game.filename,
        stagePath: plan.stagePath('achievement')));
  }
  final engine = DriveTransferEngine(journal: journal, storage: storage,
      revalidate: (_, __) async {}, openMedia: (_, offset, __) async {
    Stream<Uint8List> chunks() async* {
      for (var at = offset; at < payload.length; at += OwnedStorage.maxChunkBytes) {
        final end = at + OwnedStorage.maxChunkBytes < payload.length
            ? at + OwnedStorage.maxChunkBytes : payload.length;
        yield Uint8List.sublistView(payload, at, end);
      }
    }
    return DriveMediaResponse(bytes: chunks(), offset: offset,
        length: payload.length - offset, total: payload.length);
  });
  require((await engine.start('achievement').result).lifecycle == TransferLifecycle.completed,
      'fixture_transfer_failed');
  final system = SystemModel.supportedSystems.singleWhere((s) => s.id == 'gamegear');
  require(await RaHashService.computeInstalledHash(game, system, root,
      installations: InstallationIndex(journal, storage: storage)) ==
      md5.convert(payload).toString(), 'native_exact_hash_failed');
  final service = DatabaseService();
  await service.saveRaMatch(game.filename, system.id,
      const RaMatchResult(type: RaMatchType.nameMatch, raGameId: 1));
  await service.saveRaMatch(game.raMatchKey, system.id,
      const RaMatchResult(type: RaMatchType.hashVerified, raGameId: 2));
  await service.updateRaMastered(game.raMatchKey, system.id, true);
  final matches = await service.getRaMatchesForSystem(system.id);
  require(matches[game.filename]?.raGameId == 1 &&
      matches[game.filename]?.isMastered == false &&
      matches[game.raMatchKey]?.raGameId == 2 &&
      matches[game.raMatchKey]?.isMastered == true, 'android_cache_isolation_failed');
  final changed = RemoteArtifact.fromJson({...artifact.toJson(), 'version': '2'});
  require(matches[GameItem.achievementKey(game.filename, changed)] == null,
      'changed_version_inherited_match');
  final installation = (await journal.installationForTarget(
      destinationRoot: root, relativePath: game.filename))!;
  await OwnedInstallationRemoval(journal, storage: storage).remove(installation);
  require(!await File('$root/${game.filename}').exists(), 'owned_cleanup_failed');
  DatabaseService.resetForTesting();
  await db.close();
  await Directory(root).delete();
  for (final path in [dbPath, '$dbPath-journal', '$dbPath-wal', '$dbPath-shm']) {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
  debugPrint('ACHIEVEMENT_PROOF PASSED native pinned hash and Android cache isolation');
}
