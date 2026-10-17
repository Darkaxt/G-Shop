import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/library_identity.dart';
import '../../models/scraped_metadata.dart';
import '../../models/transfer_record.dart';
import '../../models/portable_patch_recipe.dart';
import '../installation_index.dart';
import '../migration/migration_data.dart';
import '../drive/drive_bundle.dart';
import '../library_store.dart';
import 'metadata_artwork_cache.dart';
import 'es_de_metadata_projection.dart';
import 'es_de_metadata_publication.dart';
import 'effective_overall_rating.dart';

/// Durable scraped facts, not a backup of the operational application database.
/// The selected directory contains no credentials, job/transfer state or install
/// ownership. Internal projections are restored only against current bindings.
class SharedMetadataStore {
  static const _applicationId =
      0x52534d31; // RSM1, not an arbitrary SQLite file.
  final Directory root;
  final Database _db;
  final Future<void> Function() _verifyAccess;
  // One optional cloud owner; ordinary local metadata behavior is unchanged.
  Database get cloudIndex => _db;
  void Function()? cloudChanged;
  Future<void> Function()? joinCloudOwner;
  Future<File?> Function(String mediaKey, {bool userRequested})?
      fetchCloudMedia;
  bool cloudManaged = false;
  Directory get artworkRoot => Directory(p.join(root.path, 'artwork'));
  EsDeMetadataPublication get esDePublication => EsDeMetadataPublication(_db);
  Future<List<String>> esDeTargets() async {
    await requireAccess();
    return (await _db.rawQuery(
            'SELECT DISTINCT target_path FROM es_de_mappings ORDER BY target_path'))
        .map((row) => row['target_path'] as String)
        .toList(growable: false);
  }

  SharedMetadataStore._(this.root, this._db, this._verifyAccess);

  /// File reachability and an already-open SQLite handle do not establish that
  /// Android still grants broad shared-storage access. Never prompt from IO.
  static Future<void> requireStoragePermission() async {
    if (Platform.isAndroid &&
        !(await Permission.manageExternalStorage.status).isGranted) {
      throw const FileSystemException(
          'Shared metadata permission is unavailable');
    }
  }

  Future<void> requireAccess() => _verifyAccess();

  static Future<SharedMetadataStore> open(Directory directory,
      {DatabaseFactory? factory,
      bool existingOnly = false,
      Future<void> Function()? verifyAccess}) async {
    final access = verifyAccess ?? requireStoragePermission;
    await access();
    final root = directory.absolute;
    if (existingOnly &&
        (!await root.exists() ||
            !await File(p.join(root.path, 'metadata.sqlite')).exists())) {
      throw const FileSystemException(
          'Selected metadata storage is unavailable');
    }
    await root.create(recursive: true);
    final db = await (factory ?? databaseFactory).openDatabase(
        p.join(root.path, 'metadata.sqlite'),
        options: OpenDatabaseOptions(
            version: 7,
            onConfigure: (db) async {
              final applicationId = (await db.rawQuery('PRAGMA application_id'))
                  .single
                  .values
                  .single as int;
              final tables = await db.rawQuery(
                  // Android creates its locale bookkeeping before onConfigure,
                  // even for a brand-new database. It is not application data.
                  "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' LIMIT 1");
              if (tables.isNotEmpty && applicationId != _applicationId) {
                throw const FormatException(
                    'Not an R-Shop shared metadata store');
              }
              // A rollback journal remains beside the shared database for
              // recovery; never use memory/off journaling for external storage.
              await db.rawQuery('PRAGMA journal_mode = DELETE');
              await db.execute('PRAGMA synchronous = FULL');
            },
            onCreate: (db, _) async {
              await db.execute('PRAGMA application_id = $_applicationId');
              await db.execute('''CREATE TABLE records (
                edition_id TEXT NOT NULL, provider_id TEXT NOT NULL,
                identity_key TEXT NOT NULL, generation INTEGER NOT NULL,
                game_json TEXT NOT NULL, edition_json TEXT NOT NULL,
                artifacts_json TEXT NOT NULL, record_json TEXT NOT NULL,
                PRIMARY KEY (edition_id, provider_id))''');
              await MetadataArtworkCache.install(db);
              await _installArtworkResponses(db);
              await _installIdentityBindings(db);
              await _installEsDe(db);
              await _installReviewedArtwork(db);
              await _installPatchRecipes(db);
            },
            onUpgrade: (db, old, _) async {
              if (old < 2) await _installArtworkResponses(db);
              if (old < 3) {
                await _installIdentityBindings(db);
                // v1/v2 contain scraped identities, but no independent base
                // snapshots. Retain those exact bindings without inventing a
                // missing base from a title/provider ID.
                var cursor = 0;
                while (true) {
                  final page = await db.rawQuery('''SELECT rowid AS cursor, *
                    FROM records WHERE rowid > ? ORDER BY rowid LIMIT 128''',
                      [cursor]);
                  for (final row in page) {
                    await _writeIdentityBinding(
                        db,
                        row,
                        row['generation'] as int,
                        row['artifacts_json'] as String);
                  }
                  if (page.length < 128) break;
                  cursor = page.last['cursor'] as int;
                }
              }
              if (old < 4) await _installEsDe(db);
              if (old == 4) {
                await EsDeMetadataPublication.installArtwork(db);
                await db.execute(
                    'ALTER TABLE es_de_mappings ADD COLUMN media_root TEXT');
              }
              if (old < 5) await _installReviewedArtwork(db);
              if (old >= 4 && old < 6) {
                await db.execute(
                    'ALTER TABLE es_de_mappings ADD COLUMN installation_layout TEXT');
              }
              if (old < 7) await _installPatchRecipes(db);
            }));
    return SharedMetadataStore._(root, db, access);
  }

  Future<void> close() async {
    await joinCloudOwner?.call();
    await _db.close();
  }

  /// Bounded, credential-free packets; no ES-DE local paths or operational jobs.
  Stream<Map<String, dynamic>> cloudPackets({String? editionId}) async* {
    await requireAccess();
    var cursor = 0;
    var finished = false;
    while (true) {
      final groups = await _db.transaction((txn) async {
        final page = await txn.rawQuery(
            'SELECT rowid AS cursor, * FROM records WHERE rowid > ? '
            '${editionId == null ? '' : 'AND edition_id = ? '}ORDER BY rowid LIMIT 128',
            [cursor, if (editionId != null) editionId]);
        final groups = <String, Map<String, dynamic>>{};
        for (final row in page) {
          final game =
              GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
          final record =
              MetadataRecord.fromJson(jsonDecode(row['record_json'] as String));
          final platform = game.platformId;
          if (platform == null)
            throw const FormatException('Cloud metadata requires a console');
          final packet = groups.putIfAbsent(
              platform,
              () => {
                    'version': 1,
                    'platform': game.platformId,
                    'records': <Map<String, Object?>>[],
                    'bindings': <Map<String, Object?>>[],
                    'artwork': <Map<String, Object?>>[],
                    'responses': <Map<String, Object?>>[],
                  });
          (packet['records'] as List).add({...row}..remove('cursor'));
          (packet['bindings'] as List).addAll(await txn.query(
              'identity_bindings',
              where: 'game_id = ? OR game_id = ?',
              whereArgs: [game.id, game.baseGameId ?? game.id]));
          final edition = EditionIdentity.fromJson(
              jsonDecode(row['edition_json'] as String));
          final mediaByKey = {
            for (final media in [
              ...record.media,
              ...MetadataArtworkCache.displayMedia(record,
                  regions: edition.regions, includePhysicalLabel: true)
            ])
              MetadataArtworkCache.key(media): media
          };
          for (final media in mediaByKey.values) {
            final key = MetadataArtworkCache.key(media);
            (packet['artwork'] as List).addAll(await txn.query(
                'metadata_artwork_cache',
                where: 'media_key = ?',
                whereArgs: [key]));
            (packet['responses'] as List).addAll(await txn.query(
                'artwork_responses',
                where: 'provider_id = ? AND generation = ? AND media_key = ?',
                whereArgs: [record.providerId, record.refreshGeneration, key]));
          }
        }
        finished = page.length < 128;
        if (page.isNotEmpty) cursor = page.last['cursor'] as int;
        return groups;
      });
      for (final packet in groups.values) {
        yield packet;
      }
      if (finished) break;
    }
  }

  Future<void> importCloudPacket(Map<String, dynamic> packet) async {
    await requireAccess();
    if (packet['version'] != 1 ||
        packet['records'] is! List ||
        (packet['records'] as List).length > 128) {
      throw const FormatException('Invalid cloud metadata packet');
    }
    final platform = packet['platform'] as String;
    final allowedBindings = <String>{};
    await _db.transaction((txn) async {
      for (final raw in packet['records'] as List) {
        final row = (raw as Map).cast<String, Object?>();
        final game =
            GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
        final edition =
            EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String));
        final record =
            MetadataRecord.fromJson(jsonDecode(row['record_json'] as String));
        final artifacts = (jsonDecode(row['artifacts_json'] as String) as List)
            .map((v) =>
                RemoteArtifact.fromJson((v as Map).cast<String, dynamic>()))
            .toList();
        if (!LibraryStore.hasConsistentProvenance(record) ||
            game.platformId != platform ||
            record.platformId != platform ||
            record.gameId != game.id ||
            edition.gameId != game.id ||
            record.editionId != edition.id ||
            row['edition_id'] != edition.id ||
            row['provider_id'] != record.providerId ||
            row['generation'] != record.refreshGeneration ||
            (game.providerIds[record.providerId] != null &&
                game.providerIds[record.providerId] != record.providerGameId) ||
            LibraryStore.metadataIdentity(row, providerId: record.providerId) !=
                row['identity_key'] ||
            edition.members.any((m) =>
                artifacts.where((a) => a.id == m.artifactId).length != 1) ||
            artifacts.length != edition.members.length) {
          throw const FormatException(
              'Cloud metadata identity/provenance mismatch');
        }
        allowedBindings.add(game.id);
        if (game.baseGameId != null) allowedBindings.add(game.baseGameId!);
        final previous = await txn.query('records',
            where: 'edition_id = ? AND provider_id = ?',
            whereArgs: [edition.id, record.providerId],
            limit: 1);
        if (previous.isNotEmpty) {
          final old = MetadataRecord.fromJson(
              jsonDecode(previous.single['record_json'] as String));
          if (!record.retrievedAt.isAfter(old.retrievedAt)) continue;
        }
        await txn.insert(
            'records',
            {
              for (final key in [
                'edition_id',
                'provider_id',
                'identity_key',
                'generation',
                'game_json',
                'edition_json',
                'artifacts_json',
                'record_json'
              ])
                key: row[key]
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        await _writeIdentityBinding(txn, row, record.refreshGeneration,
            row['artifacts_json'] as String);
      }
      for (final raw in packet['bindings'] as List) {
        final row = (raw as Map).cast<String, Object?>();
        final game =
            GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
        final edition =
            EditionIdentity.fromJson(jsonDecode(row['edition_json'] as String));
        final artifacts = (jsonDecode(row['artifacts_json'] as String) as List)
            .map((a) =>
                RemoteArtifact.fromJson((a as Map).cast<String, dynamic>()))
            .toList();
        if (game.platformId != platform ||
            !allowedBindings.contains(game.id) ||
            edition.id != row['edition_id'] ||
            edition.gameId != game.id ||
            row['game_id'] != game.id ||
            LibraryStore.metadataIdentity(row) != row['identity_key'] ||
            artifacts.length != edition.members.length ||
            edition.members.any((m) =>
                artifacts.where((a) => a.id == m.artifactId).length != 1))
          throw const FormatException('Cloud base platform mismatch');
        await _writeIdentityBinding(txn, row, row['generation'] as int,
            row['artifacts_json'] as String);
      }
      for (final raw in packet['artwork'] as List) {
        final row = (raw as Map).cast<String, Object?>();
        if (!RegExp(r'^[a-f0-9]{64}\.png$')
                .hasMatch(row['filename'] as String) ||
            (row['byte_length'] as int) < 57 ||
            (row['byte_length'] as int) > MetadataArtworkCache.maxBytes) {
          throw const FormatException('Invalid cloud artwork receipt');
        }
        await MetadataArtworkCache.publish(
            txn,
            MetadataArtworkBlob(row['media_key'] as String,
                row['filename'] as String, row['byte_length'] as int),
            DateTime.parse(row['retrieved_at'] as String));
      }
      for (final raw in packet['responses'] as List) {
        final row = (raw as Map).cast<String, Object?>();
        final receipts = (packet['artwork'] as List).where((r) =>
            r['media_key'] == row['media_key'] &&
            r['filename'] == row['filename'] &&
            r['byte_length'] == row['byte_length']);
        if (receipts.isEmpty ||
            !(packet['records'] as List).any((r) =>
                r['provider_id'] == row['provider_id'] &&
                r['generation'] == row['generation'])) {
          throw const FormatException('Invalid cloud artwork response binding');
        }
        await txn.insert(
            'artwork_responses',
            {
              for (final key in [
                'provider_id',
                'generation',
                'media_key',
                'filename',
                'byte_length',
                'retrieved_at'
              ])
                key: row[key]
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> snapshotForMigration(File target) async {
    await requireAccess();
    await MigrationData.snapshotDatabase(_db, target);
  }

  static Future<void> _installPatchRecipes(DatabaseExecutor db) =>
      db.execute('''CREATE TABLE IF NOT EXISTS patch_recipes (
        recipe_id TEXT PRIMARY KEY, platform_id TEXT NOT NULL,
        source_game_id TEXT NOT NULL, record_json TEXT NOT NULL)''');

  /// Idempotent content publication; a conflicting verified output is never
  /// silently replaced by an import or another device's local residency.
  Future<PortablePatchRecipe> putPatchRecipe(PortablePatchRecipe value) async {
    await requireAccess();
    final normalized = PortablePatchRecipe.decode(value.encode());
    return _db.transaction((txn) async {
      final rows = await txn.query('patch_recipes',
          where: 'recipe_id=?', whereArgs: [normalized.recipe.id], limit: 1);
      var result = normalized;
      if (rows.isNotEmpty) {
        final previous =
            PortablePatchRecipe.decode(rows.single['record_json'] as String);
        if (previous.outputSha256 != null &&
            normalized.outputSha256 != null &&
            (previous.outputSha256 != normalized.outputSha256 ||
                previous.outputSize != normalized.outputSize)) {
          throw const FormatException('patch_recipe_output_conflict');
        }
        if (previous.outputSha256 != null || normalized.outputSha256 == null) {
          return previous;
        }
        result = PortablePatchRecipe(
            recipe: previous.recipe,
            sourceGameId: previous.sourceGameId,
            gameTitle: previous.gameTitle,
            gameIndexPath: previous.gameIndexPath,
            title: previous.title,
            outputSize: normalized.outputSize,
            outputSha256: normalized.outputSha256);
      }
      await txn.insert(
          'patch_recipes',
          {
            'recipe_id': result.recipe.id,
            'platform_id': result.recipe.platformId,
            'source_game_id': result.sourceGameId,
            'record_json': result.encode()
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      return result;
    });
  }

  Future<List<PortablePatchRecipe>> patchRecipes(String platform,
      {String? sourceGameId}) async {
    await requireAccess();
    final rows = await _db.query('patch_recipes',
        where: sourceGameId == null
            ? 'platform_id=?'
            : 'platform_id=? AND source_game_id=?',
        whereArgs: [platform, if (sourceGameId != null) sourceGameId],
        orderBy: 'recipe_id');
    return rows
        .map((row) => PortablePatchRecipe.decode(row['record_json'] as String))
        .toList();
  }

  static Future<void> _installEsDe(DatabaseExecutor db) async {
    await EsDeMetadataPublication.install(db);
    await db.execute('''CREATE TABLE es_de_mappings (
      edition_id TEXT NOT NULL, provider_id TEXT NOT NULL,
      identity_key TEXT NOT NULL, target_path TEXT NOT NULL,
      system_id TEXT NOT NULL, install_root TEXT NOT NULL, rom_root TEXT NOT NULL,
      rom_path TEXT NOT NULL, media_root TEXT, installation_layout TEXT,
      PRIMARY KEY(edition_id, provider_id))''');
  }

  static Future<void> _installReviewedArtwork(DatabaseExecutor db) =>
      db.execute('''CREATE TABLE es_de_media_reuse (
        edition_id TEXT NOT NULL, provider_id TEXT NOT NULL,
        identity_key TEXT NOT NULL, media_key TEXT NOT NULL,
        source_path TEXT NOT NULL, source_hash TEXT NOT NULL,
        source_length INTEGER NOT NULL, filename TEXT NOT NULL,
        byte_length INTEGER NOT NULL, imported_at TEXT NOT NULL,
        origin TEXT NOT NULL CHECK(origin = 'esde-reviewed'),
        PRIMARY KEY(edition_id, provider_id, media_key))''');

  static File _esDeImage(Map<String, Object?> mapping, MetadataMedia media,
      {String extension = '.png'}) {
    final stem =
        p.posix.withoutExtension((mapping['rom_path'] as String).substring(2));
    return File(p.joinAll([
      mapping['media_root'] as String,
      {'ss', 'screenshot'}.contains(media.type) ? 'screenshots' : 'covers',
      ...stem.split('/').take(stem.split('/').length - 1),
      '${stem.split('/').last}$extension'
    ]));
  }

  Future<bool> _currentEsDeMapping(
      DatabaseExecutor snapshot,
      Map<String, Object?> mapping,
      Future<String?> Function(String) configuredTarget) async {
    final target = await configuredTarget(mapping['system_id'] as String);
    if (target == null ||
        p.normalize(p.absolute(target)) != mapping['install_root']) {
      return false;
    }
    final identity = await _identity(snapshot, mapping['edition_id'] as String);
    if (identity == null) return false;
    final edition = EditionIdentity.fromJson(
        jsonDecode(identity['edition_json'] as String));
    final savedLayout = mapping['installation_layout'] as String?;
    if (savedLayout != null) {
      final layout = (jsonDecode(savedLayout) as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList(growable: false);
      if (!await _layoutIsCurrent(
          snapshot, layout, edition, mapping['system_id'] as String)) {
        return false;
      }
      final entry = RemoteArtifact.fromJson(layout.first['artifact']);
      try {
        final planned = await _recordedLayout(snapshot, entry, target);
        if (planned != null && !_sameLayout(layout, planned)) return false;
      } on StateError {
        return false;
      }
      final expected = _esDeRomPath(target, mapping['rom_root'] as String,
          layout.first['relativePath'] as String);
      return expected == mapping['rom_path'] &&
          LibraryStore.metadataIdentity(identity,
                  providerId: mapping['provider_id'] as String) ==
              mapping['identity_key'] &&
          await LibraryStore.isCurrentCatalogueIdentity(snapshot, identity);
    }
    // v4/v5 only mapped an ordinary single filename. Preserve that mapping,
    // but reject it if the normal queue now records a different expected path.
    if (edition.members.length != 1) return false;
    final items = await snapshot.query('games',
        columns: ['filename', 'remote_artifact'],
        where: 'artifact_key = ? AND systemSlug = ? AND is_folder = 0',
        whereArgs: [
          edition.members.single.artifactId.key,
          mapping['system_id']
        ]);
    if (items.length != 1) return false;
    if (items.single['remote_artifact'] case final String encoded) {
      try {
        final planned = await _recordedLayout(
            snapshot, RemoteArtifact.fromJson(jsonDecode(encoded)), target);
        if (planned != null &&
            (planned.length != 1 ||
                planned.first['relativePath'] != items.single['filename'])) {
          return false;
        }
      } on StateError {
        return false;
      }
    }
    final expected = p
        .relative(p.join(target, items.single['filename'] as String),
            from: mapping['rom_root'] as String)
        .split(p.separator)
        .join('/');
    return './$expected' == mapping['rom_path'] &&
        LibraryStore.metadataIdentity(identity,
                providerId: mapping['provider_id'] as String) ==
            mapping['identity_key'] &&
        await LibraryStore.isCurrentCatalogueIdentity(snapshot, identity);
  }

  static String _esDeRomPath(String destination, String romRoot, String path) =>
      './${p.relative(p.joinAll([
                destination,
                ...path.split('/')
              ]), from: romRoot).split(p.separator).join('/')}';

  static bool _sameLayout(
          List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((index) =>
          a[index]['relativePath'] == b[index]['relativePath'] &&
          InstallationSnapshot.sameContent(
              RemoteArtifact.fromJson(a[index]['artifact']),
              RemoteArtifact.fromJson(b[index]['artifact'])));

  /// Read the normal queue's durable plan under the caller's catalogue snapshot.
  /// Only the expected entry/member paths and source identities leave this read:
  /// no transfer IDs, stage paths, progress or installation ownership are shared.
  static Future<List<Map<String, dynamic>>?> _recordedLayout(
      DatabaseExecutor source, RemoteArtifact entry, String destination) async {
    final tables = await source.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'transfer_target_owners'");
    if (tables.isEmpty) return null;
    String? cursor;
    List<Map<String, dynamic>>? selected;
    var found = false;
    while (true) {
      final rows = await source.rawQuery(
          '''SELECT t.record_json, o.relative_path
        FROM transfer_records t INDEXED BY idx_transfer_artifact
        JOIN transfer_target_owners o ON o.transfer_id = t.transfer_id
        WHERE t.artifact_key = ? AND t.destination_root = ?
          AND o.destination_root = ? ${cursor == null ? '' : 'AND o.relative_path > ?'}
        ORDER BY o.relative_path LIMIT 128''',
          [entry.id.key, destination, destination, if (cursor != null) cursor]);
      for (final row in rows) {
        final transfer =
            TransferRecord.fromJson(jsonDecode(row['record_json'] as String));
        if (transfer.bundleOwner != null) continue;
        found = true;
        if (!InstallationSnapshot.sameContent(entry, transfer.artifact)) {
          continue;
        }
        if (selected != null) throw StateError('Ambiguous installation layout');
        selected = [
          {
            'artifact': transfer.artifact.toJson(),
            'relativePath': transfer.relativePath
          },
          for (final member in transfer.bundleMembers)
            {
              'artifact': member.artifact.toJson(),
              'relativePath': member.relativePath
            }
        ];
      }
      if (rows.length < 128) break;
      cursor = rows.last['relative_path'] as String;
    }
    if (found && selected == null) {
      throw StateError('A current explicit installation plan is required');
    }
    return selected;
  }

  static Future<bool> _layoutIsCurrent(
      DatabaseExecutor source,
      List<Map<String, dynamic>> layout,
      EditionIdentity edition,
      String system) async {
    if (layout.isEmpty || layout.length > 257) return false;
    final paths = <String>{};
    final artifacts = <String>[];
    final root = RemoteArtifact.fromJson(layout.first['artifact']);
    if (BundleReferences.isManifest(root.displayName) != (layout.length > 1)) {
      return false;
    }
    for (final item in layout) {
      final relative = item['relativePath'] as String;
      if (relative.isEmpty ||
          relative.contains(RegExp(r'[\\\x00-\x1f<>:"|?*]')) ||
          relative
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..') ||
          !paths.add(relative.toLowerCase()) ||
          {'.zip', '.7z', '.rar'}
              .contains(p.posix.extension(relative).toLowerCase())) {
        return false;
      }
      final artifact = RemoteArtifact.fromJson(item['artifact']);
      if (artifact.id.sourceId != root.id.sourceId ||
          artifact.id.accountId != root.id.accountId ||
          artifact.id.providerId != root.id.providerId ||
          artifacts.contains(artifact.id.key)) {
        return false;
      }
      artifacts.add(artifact.id.key);
      final current = await source.query('games',
          columns: ['filename', 'remote_artifact'],
          where: 'artifact_key = ? AND systemSlug = ? AND is_folder = 0',
          whereArgs: [artifact.id.key, system],
          limit: 2);
      if (current.length != 1 || current.single['remote_artifact'] == null) {
        return false;
      }
      final published = RemoteArtifact.fromJson(
          jsonDecode(current.single['remote_artifact'] as String));
      if (current.single['filename'] != published.displayName ||
          !InstallationSnapshot.sameContent(artifact, published)) {
        return false;
      }
    }
    final members = edition.members.map((m) => m.artifactId.key).toList();
    // A normal catalogue playlist owns its one entry artifact; the explicit
    // plan supplies its dependencies. A reviewed multi-member edition must
    // agree with the complete ordered graph, not just one similarly named disc.
    return members.length == 1
        ? members.single == artifacts.first
        : members.length == artifacts.length &&
            Iterable<int>.generate(members.length)
                .every((i) => members[i] == artifacts[i]);
  }

  /// The caller explicitly reviews this image for the exact open edition. A
  /// filename alone never creates a binding and old descriptions/scores are not
  /// imported. The receipt records local origin, not a provider body response.
  Future<void> reviewEsDeArtwork(Database source, MetadataArtworkCache cache,
      {required String editionId,
      required String providerId,
      required File image,
      required Future<String?> Function(String) configuredTarget}) async {
    await requireAccess();
    final mappings = await _db.query('es_de_mappings',
        where: 'edition_id = ? AND provider_id = ? AND media_root IS NOT NULL',
        whereArgs: [editionId, providerId]);
    if (mappings.length != 1 ||
        !await _currentEsDeMapping(source, mappings.single, configuredTarget)) {
      throw StateError(
          'An exact current ES-DE installation mapping is required');
    }
    final record = await LibraryStore(Future.value(source))
        .metadata(editionId, providerId);
    if (record == null) {
      throw StateError('Current provider metadata is required');
    }
    final selected = MetadataArtworkCache.displayMedia(record);
    MetadataMedia? candidate;
    for (final media in selected) {
      if (_esDeImage(mappings.single, media, extension: p.extension(image.path))
              .absolute
              .path ==
          image.absolute.path) {
        if (candidate != null) throw StateError('Ambiguous media selector');
        candidate = media;
      }
    }
    if (candidate == null || cache.root.path != artworkRoot.absolute.path) {
      throw StateError(
          'Artwork does not match the selected edition/path/cache');
    }
    final imported = await cache.importReviewedImage(image, candidate);
    final importedAt = DateTime.now().toUtc();
    await source.transaction((snapshot) async {
      if (!await _currentEsDeMapping(
          snapshot, mappings.single, configuredTarget)) {
        throw StateError('Edition changed during artwork review');
      }
      await preserveBlob(imported.blob, importedAt);
      await _db.insert(
          'es_de_media_reuse',
          {
            'edition_id': editionId,
            'provider_id': providerId,
            'identity_key': mappings.single['identity_key'],
            'media_key': imported.blob.key,
            'source_path': image.absolute.path,
            'source_hash': imported.sourceHash,
            'source_length': imported.sourceLength,
            'filename': imported.blob.filename,
            'byte_length': imported.blob.length,
            'imported_at': importedAt.toIso8601String(),
            'origin': 'esde-reviewed',
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await MetadataArtworkCache.publish(snapshot, imported.blob, importedAt);
    });
  }

  Future<({MetadataArtworkBlob blob, DateTime retrievedAt})?> reviewedArtwork(
      String editionId,
      String providerId,
      String identityKey,
      String mediaKey) async {
    await requireAccess();
    final rows = await _db.query('es_de_media_reuse',
        where:
            'edition_id = ? AND provider_id = ? AND identity_key = ? AND media_key = ?',
        whereArgs: [editionId, providerId, identityKey, mediaKey],
        limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final mappings = await _db.query('es_de_mappings',
        where:
            'edition_id = ? AND provider_id = ? AND identity_key = ? AND media_root IS NOT NULL',
        whereArgs: [editionId, providerId, identityKey],
        limit: 1);
    if (mappings.isEmpty) return null;
    final records = await _db.query('records',
        columns: ['record_json'],
        where: 'edition_id = ? AND provider_id = ? AND identity_key = ?',
        whereArgs: [editionId, providerId, identityKey],
        limit: 1);
    if (records.isEmpty) return null;
    final media = MetadataArtworkCache.displayMedia(MetadataRecord.fromJson(
            jsonDecode(records.single['record_json'] as String)))
        .where((m) => MetadataArtworkCache.key(m) == mediaKey);
    if (media.length != 1 ||
        _esDeImage(mappings.single, media.single,
                    extension: p.extension(row['source_path'] as String))
                .absolute
                .path !=
            row['source_path']) {
      return null;
    }
    final original = File(row['source_path'] as String);
    if (!await original.exists() ||
        await original.length() != row['source_length'] ||
        (row['source_length'] as int) > MetadataArtworkCache.maxBytes) {
      return null;
    }
    var cursor = original.absolute.path;
    while (true) {
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        return null;
      }
      final parent = p.dirname(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }
    if (await _boundedHash(original) != row['source_hash']) return null;
    final blob = MetadataArtworkBlob(
        mediaKey, row['filename'] as String, row['byte_length'] as int);
    if (!await _validBlob(
        File(p.join(artworkRoot.path, blob.filename)), blob)) {
      return null;
    }
    return (
      blob: blob,
      retrievedAt: DateTime.parse(row['imported_at'] as String)
    );
  }

  /// Reuse the normal queue's recorded layout for bundles/replacements. An
  /// unplanned ordinary file uses its configured single-file path. Mapping
  /// never reserves a transfer, parses ROM manifests or creates ROM files.
  Future<void> mapEsDeEdition(Database source,
          {required int cacheRowId,
          required String editionId,
          required String providerId,
          required Directory installRoot,
          required Directory romRoot,
          Directory? mediaRoot,
          required File gamelist}) =>
      source.transaction((snapshot) async {
        await requireAccess();
        final identity = await _identity(snapshot, editionId);
        if (identity == null ||
            !await LibraryStore.isCurrentCatalogueIdentity(
                snapshot, identity)) {
          throw StateError('Current verified metadata is required');
        }
        final records = await snapshot.query('library_metadata',
            columns: ['record_json'],
            where: 'edition_id = ? AND provider_id = ? AND identity_key = ?',
            whereArgs: [
              editionId,
              providerId,
              LibraryStore.metadataIdentity(identity, providerId: providerId)
            ],
            limit: 1);
        if (records.isEmpty) {
          throw StateError('Current verified metadata is required');
        }
        final record = MetadataRecord.fromJson(
            jsonDecode(records.single['record_json'] as String));
        if (!LibraryStore.hasConsistentProvenance(record)) {
          throw StateError('Current verified metadata is required');
        }
        final edition = EditionIdentity.fromJson(
            jsonDecode(identity['edition_json'] as String));
        final rows = await snapshot.query('games',
            where: 'id = ? AND is_folder = 0', whereArgs: [cacheRowId]);
        if (rows.length != 1) {
          throw StateError('Edition does not belong to this catalogue item');
        }
        final encoded = rows.single['remote_artifact'] as String?;
        if (encoded == null) {
          throw StateError('An exact remote artifact mapping is required');
        }
        final entry = RemoteArtifact.fromJson(jsonDecode(encoded));
        if (!edition.members.any((member) => member.artifactId == entry.id)) {
          throw StateError('Edition does not belong to this catalogue item');
        }
        final filename = rows.single['filename'] as String;
        if (filename.isEmpty ||
            filename.contains(RegExp(r'[/:\\\x00-\x1f<>"|?*]')) ||
            filename == '.' ||
            filename == '..' ||
            {'.7z', '.zip', '.rar'}
                .contains(p.extension(filename).toLowerCase())) {
          throw StateError(
              'An explicit emulator-ready installation mapping is required');
        }
        final destination = p.normalize(installRoot.absolute.path);
        final esDeRoot = p.normalize(romRoot.absolute.path);
        if (destination != esDeRoot && !p.isWithin(esDeRoot, destination)) {
          throw StateError(
              'Configured installation is outside the selected ES-DE ROM root');
        }
        var layout = await _recordedLayout(snapshot, entry, destination);
        if (layout == null) {
          if (edition.members.length != 1 ||
              BundleReferences.isManifest(filename)) {
            throw StateError(
                'An explicit bundle installation mapping is required');
          }
          layout = [
            {'artifact': entry.toJson(), 'relativePath': filename}
          ];
        }
        if (!await _layoutIsCurrent(
            snapshot, layout, edition, rows.single['systemSlug'] as String)) {
          throw StateError(
              'Installation layout does not match the current catalogue');
        }
        final update = _esDeUpdate(
            record,
            _esDeRomPath(
                destination, esDeRoot, layout.first['relativePath'] as String),
            edition: edition);
        final key =
            LibraryStore.metadataIdentity(identity, providerId: providerId);
        await _db.transaction((txn) async {
          await txn.insert(
              'es_de_mappings',
              {
                'edition_id': editionId,
                'provider_id': providerId,
                'identity_key': key,
                'target_path': p.normalize(gamelist.absolute.path),
                'system_id': rows.single['systemSlug'],
                'install_root': destination,
                'rom_root': esDeRoot,
                'rom_path': update.relativeRomPath,
                'media_root': mediaRoot == null
                    ? null
                    : p.normalize(mediaRoot.absolute.path),
                'installation_layout': jsonEncode(layout),
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
          await esDePublication.queue(
              target: gamelist,
              identityKey: key,
              generation: record.refreshGeneration,
              update: update,
              transaction: txn);
        });
      });

  static EsDeMetadataUpdate _esDeUpdate(MetadataRecord record, String romPath,
      {required EditionIdentity edition, EffectiveOverallRating? overall}) {
    String? english(List<MetadataText> values) {
      if (values.isEmpty) return null;
      final candidates =
          values.where((value) => value.language == 'en').toList();
      // No unrecorded regional preference. Ambiguous localized fields remain
      // absent instead of borrowing a neighbouring edition's display metadata.
      if (candidates.length == 1) return candidates.single.text;
      return values.length == 1 ? values.single.text : null;
    }

    final name = english(record.titles);
    final description = english(record.descriptions);
    final genres =
        record.genres.map((g) => english(g.names)).whereType<String>().toList();
    final selectedDate =
        selectEditionReleaseDate(record.releaseDates, regions: edition.regions);
    final date = selectedDate == null
        ? null
        : EsDeMetadataProjection.releaseDate(selectedDate);
    final rating = EsDeMetadataProjection.rating(overall);
    return EsDeMetadataUpdate(
        editionId: record.editionId,
        relativeRomPath: romPath,
        fields: {
          if (name != null) 'name': name,
          if (description != null) 'desc': description,
          if (record.developer != null) 'developer': record.developer!,
          if (record.publisher != null) 'publisher': record.publisher!,
          if (genres.isNotEmpty) 'genre': genres.join(' / '),
          if (date != null) 'releasedate': date,
          if (rating != null) 'rating': rating,
        });
  }

  Future<EsDePublicationResult> publishEsDe(Database source, File gamelist,
          {required bool esDeClosed,
          bool rebasePrepared = false,
          required Future<String?> Function(String systemId)
              configuredTarget}) =>
      source.transaction((snapshot) async {
        await requireAccess();
        Future<bool> isCurrent(String editionId, String key) async {
          await requireAccess();
          final mappings = await _db.query('es_de_mappings',
              where: 'edition_id = ? AND identity_key = ? AND target_path = ?',
              whereArgs: [editionId, key, p.normalize(gamelist.absolute.path)]);
          if (mappings.length != 1) return false;
          final mapping = mappings.single;
          return _currentEsDeMapping(snapshot, mapping, configuredTarget);
        }

        // Reconcile against the same current score selector used by cards/Top,
        // including independent provider refreshes. Never export raw/highest/
        // critic/base-project scores merely because the mapped provider has one.
        var fieldCursor = 0;
        while (true) {
          final mappings = await _db.rawQuery('''SELECT rowid AS cursor, *
            FROM es_de_mappings WHERE target_path = ? AND rowid > ?
            ORDER BY rowid LIMIT 128''',
              [p.normalize(gamelist.absolute.path), fieldCursor]);
          final scores = await LibraryStore.readEffectiveRatings(snapshot,
              mappings.map((m) => m['edition_id'] as String).toList());
          for (final mapping in mappings) {
            if (!await isCurrent(mapping['edition_id'] as String,
                mapping['identity_key'] as String)) {
              return const EsDePublicationResult('identityChanged');
            }
            final records = await snapshot.query('library_metadata',
                columns: ['record_json'],
                where:
                    'edition_id = ? AND provider_id = ? AND identity_key = ?',
                whereArgs: [
                  mapping['edition_id'],
                  mapping['provider_id'],
                  mapping['identity_key']
                ],
                limit: 1);
            if (records.isEmpty) continue;
            final record = MetadataRecord.fromJson(
                jsonDecode(records.single['record_json'] as String));
            final identity = (await _identity(snapshot, record.editionId))!;
            final edition = EditionIdentity.fromJson(
                jsonDecode(identity['edition_json'] as String));
            await esDePublication.queue(
                target: gamelist,
                identityKey: mapping['identity_key'] as String,
                generation: record.refreshGeneration,
                update: _esDeUpdate(record, mapping['rom_path'] as String,
                    edition: edition, overall: scores[record.editionId]));
          }
          if (mappings.length < 128) break;
          fieldCursor = mappings.last['cursor'] as int;
        }

        final text = await esDePublication.publish(gamelist,
            esDeClosed: esDeClosed,
            rebasePrepared: rebasePrepared,
            isCurrent: isCurrent);
        if (!{'published', 'upToDate'}.contains(text.status)) return text;
        var cursor = 0;
        var changed = text.status == 'published';
        while (true) {
          final page = await _db.rawQuery('''SELECT rowid AS cursor, *
            FROM es_de_mappings WHERE target_path = ? AND media_root IS NOT NULL
            AND rowid > ? ORDER BY rowid LIMIT 128''',
              [p.normalize(gamelist.absolute.path), cursor]);
          for (final mapping in page) {
            final editionId = mapping['edition_id'] as String;
            final key = mapping['identity_key'] as String;
            if (!await isCurrent(editionId, key)) {
              return const EsDePublicationResult('identityChanged');
            }
            final records = await snapshot.query('library_metadata',
                columns: ['record_json'],
                where:
                    'edition_id = ? AND provider_id = ? AND identity_key = ?',
                whereArgs: [editionId, mapping['provider_id'], key],
                limit: 1);
            if (records.isEmpty) continue;
            final record = MetadataRecord.fromJson(
                jsonDecode(records.single['record_json'] as String));
            var screenshotPublished = false;
            for (final media in MetadataArtworkCache.displayMedia(record)) {
              final screenshot = {'ss', 'screenshot'}.contains(media.type);
              if (screenshot && screenshotPublished) continue;
              // A reviewed launcher image remains launcher/manual-owned. Reuse
              // it in R-Shop, without taking ownership or duplicating a JPG/WebP
              // with a competing PNG beside it.
              if (await reviewedArtwork(
                      editionId,
                      mapping['provider_id'] as String,
                      key,
                      MetadataArtworkCache.key(media)) !=
                  null) {
                screenshotPublished |= screenshot;
                continue;
              }
              final cached = await _db.query('metadata_artwork_cache',
                  where: 'media_key = ?',
                  whereArgs: [MetadataArtworkCache.key(media)],
                  limit: 1);
              if (cached.isEmpty) {
                return const EsDePublicationResult('artworkUnavailable');
              }
              final blob = MetadataArtworkBlob(
                  MetadataArtworkCache.key(media),
                  cached.single['filename'] as String,
                  cached.single['byte_length'] as int);
              final image = File(p.join(artworkRoot.path, blob.filename));
              if (!await _validBlob(image, blob)) {
                return const EsDePublicationResult('sourceChanged');
              }
              final root = Directory(mapping['media_root'] as String);
              final output = _esDeImage(mapping, media);
              final result = await esDePublication.publishArtwork(
                  target: output,
                  mediaRoot: root,
                  source: image,
                  contentHash: p.basenameWithoutExtension(blob.filename),
                  editionId: editionId,
                  identityKey: key,
                  relativeRomPath: mapping['rom_path'] as String,
                  esDeClosed: esDeClosed,
                  isCurrent: isCurrent);
              if (!{'published', 'upToDate'}.contains(result.status)) {
                return result;
              }
              changed |= result.status == 'published';
              screenshotPublished |= screenshot;
            }
          }
          if (page.length < 128) break;
          cursor = page.last['cursor'] as int;
        }
        return EsDePublicationResult(changed ? 'published' : 'upToDate');
      });

  static Future<void> _installArtworkResponses(DatabaseExecutor db) =>
      db.execute('''CREATE TABLE artwork_responses (
        provider_id TEXT NOT NULL, generation INTEGER NOT NULL,
        media_key TEXT NOT NULL, filename TEXT NOT NULL,
        byte_length INTEGER NOT NULL, retrieved_at TEXT NOT NULL,
        PRIMARY KEY(provider_id, generation, media_key))''');

  static Future<void> _installIdentityBindings(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE identity_bindings (
      edition_id TEXT PRIMARY KEY, game_id TEXT NOT NULL,
      generation INTEGER NOT NULL, identity_key TEXT NOT NULL,
      game_json TEXT NOT NULL, edition_json TEXT NOT NULL,
      artifacts_json TEXT NOT NULL)''');
    await db.execute('''CREATE INDEX shared_identity_game ON
      identity_bindings(game_id, generation DESC, edition_id)''');
  }

  static Future<void> _writeIdentityBinding(DatabaseExecutor db,
      Map<String, Object?> identity, int generation, String artifacts) async {
    final game =
        GameIdentity.fromJson(jsonDecode(identity['game_json'] as String));
    final edition = EditionIdentity.fromJson(
        jsonDecode(identity['edition_json'] as String));
    if (edition.gameId != game.id) {
      throw const FormatException('Invalid shared identity binding');
    }
    final previous = await db.query('identity_bindings',
        columns: ['generation'],
        where: 'edition_id = ?',
        whereArgs: [edition.id],
        limit: 1);
    if (previous.isNotEmpty &&
        (previous.single['generation'] as int) > generation) {
      return;
    }
    await db.insert(
        'identity_bindings',
        {
          'edition_id': edition.id,
          'game_id': game.id,
          'generation': generation,
          'identity_key': LibraryStore.metadataIdentity(identity),
          'game_json': identity['game_json'],
          'edition_json': identity['edition_json'],
          'artifacts_json': artifacts
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String> _boundArtifacts(
      DatabaseExecutor source, EditionIdentity edition) async {
    final artifacts = <Map<String, dynamic>>[];
    for (final member in edition.members) {
      final rows = await source.query('library_artifacts',
          columns: ['record_json'],
          where: 'artifact_id = ?',
          whereArgs: [member.artifactId.key],
          limit: 1);
      if (rows.isEmpty) throw StateError('Missing exact source artifact');
      final artifact = RemoteArtifact.fromJson(
          jsonDecode(rows.single['record_json'] as String));
      if (artifact.id != member.artifactId) {
        throw StateError('Shared metadata artifact binding changed');
      }
      artifacts.add(artifact.toJson());
    }
    return jsonEncode(artifacts);
  }

  Future<int> maximumGeneration() async {
    await requireAccess();
    return ((await _db.rawQuery('''SELECT MAX(generation) AS maximum FROM (
        SELECT generation FROM records UNION ALL
        SELECT generation FROM artwork_responses)''')).single['maximum']
            as int?) ??
        0;
  }

  /// Commit the validated response before acknowledging its private job item.
  /// A crash between databases leaves recoverable facts, never a completed item
  /// whose only copy lived in uninstall-scoped storage.
  Future<void> preserve(MetadataRecord record, Map<String, Object?> identity,
      DatabaseExecutor source) async {
    await requireAccess();
    final game =
        GameIdentity.fromJson(jsonDecode(identity['game_json'] as String));
    final edition = EditionIdentity.fromJson(
        jsonDecode(identity['edition_json'] as String));
    if (!LibraryStore.hasConsistentProvenance(record) ||
        game.id != record.gameId ||
        edition.id != record.editionId ||
        edition.gameId != game.id ||
        game.platformId != record.platformId ||
        (game.providerIds[record.providerId] != null &&
            game.providerIds[record.providerId] != record.providerGameId)) {
      throw StateError('Shared metadata requires exact verified bindings');
    }
    final artifacts = await _boundArtifacts(source, edition);
    await _db.transaction((txn) async {
      final previous = await txn.query('records',
          columns: ['generation'],
          where: 'edition_id = ? AND provider_id = ?',
          whereArgs: [record.editionId, record.providerId],
          limit: 1);
      if (previous.isNotEmpty &&
          (previous.single['generation'] as int) > record.refreshGeneration) {
        return; // Migration of an older private projection is not replacement.
      }
      await txn.insert(
          'records',
          {
            'edition_id': record.editionId,
            'provider_id': record.providerId,
            'identity_key': LibraryStore.metadataIdentity(identity,
                providerId: record.providerId),
            'generation': record.refreshGeneration,
            'game_json': jsonEncode(game.toJson()),
            'edition_json': jsonEncode(edition.toJson()),
            'artifacts_json': artifacts,
            'record_json': jsonEncode(record.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _writeIdentityBinding(
          txn, identity, record.refreshGeneration, artifacts);
      final mappings = await txn.query('es_de_mappings',
          where: 'edition_id = ? AND provider_id = ? AND identity_key = ?',
          whereArgs: [
            edition.id,
            record.providerId,
            LibraryStore.metadataIdentity(identity,
                providerId: record.providerId)
          ]);
      for (final mapping in mappings) {
        await esDePublication.queue(
            target: File(mapping['target_path'] as String),
            identityKey: mapping['identity_key'] as String,
            generation: record.refreshGeneration,
            update: _esDeUpdate(record, mapping['rom_path'] as String,
                edition: edition),
            transaction: txn);
      }
      if (game.baseGameId != null) {
        var cursor = '';
        while (true) {
          final bases = await source.rawQuery('''SELECT e.edition_id,
            g.record_json AS game_json, e.record_json AS edition_json
            FROM library_editions e
            JOIN library_game_identities g ON g.game_id = e.game_id
            WHERE e.game_id = ? AND e.edition_id > ?
            ORDER BY e.edition_id LIMIT 128''', [game.baseGameId, cursor]);
          for (final base in bases) {
            final baseGame =
                GameIdentity.fromJson(jsonDecode(base['game_json'] as String));
            if (baseGame.platformId != game.platformId) {
              throw StateError(
                  'Shared base binding requires the same platform');
            }
            final baseEdition = EditionIdentity.fromJson(
                jsonDecode(base['edition_json'] as String));
            await _writeIdentityBinding(txn, base, record.refreshGeneration,
                await _boundArtifacts(source, baseEdition));
          }
          if (bases.length < 128) break;
          cursor = bases.last['edition_id'] as String;
        }
      }
    });
    cloudChanged?.call();
  }

  /// Recover only the exact response already committed for this generation.
  /// A fresh re-scrape cannot reuse an earlier generation or disputed identity.
  Future<MetadataRecord?> committedResponse(String editionId, String providerId,
      String identityKey, int generation) async {
    await requireAccess();
    final rows = await _db.query('records',
        where:
            'edition_id = ? AND provider_id = ? AND identity_key = ? AND generation = ?',
        whereArgs: [editionId, providerId, identityKey, generation],
        limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final record =
        MetadataRecord.fromJson(jsonDecode(row['record_json'] as String));
    if (!LibraryStore.hasConsistentProvenance(record) ||
        record.editionId != editionId ||
        record.providerId != providerId ||
        record.refreshGeneration != generation ||
        LibraryStore.metadataIdentity(row, providerId: providerId) !=
            identityKey) {
      throw const FormatException('Invalid shared response binding');
    }
    return record;
  }

  Future<void> preserveBlob(MetadataArtworkBlob blob, DateTime retrievedAt,
      {String? providerId, int? generation}) async {
    await requireAccess();
    if (!await _validBlob(
        File(p.join(artworkRoot.path, blob.filename)), blob)) {
      throw StateError('Shared artwork is not a validated immutable blob');
    }
    if ((providerId == null) != (generation == null) ||
        providerId?.trim().isEmpty == true ||
        (generation != null && generation < 1)) {
      throw ArgumentError('Artwork response requires provider and generation');
    }
    await _db.transaction((txn) async {
      await MetadataArtworkCache.publish(txn, blob, retrievedAt);
      if (providerId != null) {
        // This is evidence of a validated provider response, not exported job,
        // transfer or installation state. Ownership is rechecked by the worker.
        await txn.insert(
            'artwork_responses',
            {
              'provider_id': providerId,
              'generation': generation,
              'media_key': blob.key,
              'filename': blob.filename,
              'byte_length': blob.length,
              'retrieved_at': retrievedAt.toUtc().toIso8601String()
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    cloudChanged?.call();
  }

  Future<({MetadataArtworkBlob blob, DateTime retrievedAt})?> committedArtwork(
      String providerId, int generation, String mediaKey) async {
    await requireAccess();
    final rows = await _db.query('artwork_responses',
        where: 'provider_id = ? AND generation = ? AND media_key = ?',
        whereArgs: [providerId, generation, mediaKey],
        limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final blob = MetadataArtworkBlob(
        mediaKey, row['filename'] as String, row['byte_length'] as int);
    if (!await _validBlob(
        File(p.join(artworkRoot.path, blob.filename)), blob)) {
      return null;
    }
    return (
      blob: blob,
      retrievedAt: DateTime.parse(row['retrieved_at'] as String)
    );
  }

  static Future<bool> _validBlob(File file, MetadataArtworkBlob blob) async {
    if (!RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(blob.filename) ||
        blob.length < 57 ||
        blob.length > MetadataArtworkCache.maxBytes ||
        !await file.exists() ||
        await file.length() != blob.length) {
      return false;
    }
    return await _boundedHash(file) == blob.filename.substring(0, 64);
  }

  static Future<String?> _boundedHash(File file) async {
    var received = 0;
    try {
      final digest = await sha256
          .bind(file.openRead().map((chunk) {
            received += chunk.length;
            if (received > MetadataArtworkCache.maxBytes) {
              throw const FormatException(
                  'Artwork exceeds the bounded body budget');
            }
            return chunk;
          }))
          .first;
      return digest.toString();
    } on FormatException {
      return null;
    }
  }

  static Future<Map<String, Object?>?> _identity(
      DatabaseExecutor db, String editionId) async {
    final rows = await db.rawQuery('''SELECT g.record_json AS game_json,
      e.record_json AS edition_json FROM library_editions e
      JOIN library_game_identities g ON g.game_id = e.game_id
      WHERE e.edition_id = ?''', [editionId]);
    return rows.isEmpty ? null : rows.single;
  }

  /// Recover catalogue bindings, not source configuration. A recreated Drive
  /// source has a new local source ID, but the same account/file ID remains an
  /// exact object. Other providers retain their source-scoped identity.
  Future<Map<String, Object?>?> _recoverCatalogueBinding(
      Transaction txn, Map<String, Object?> saved, String providerId,
      {bool allowBase = true}) async {
    final game =
        GameIdentity.fromJson(jsonDecode(saved['game_json'] as String));
    final edition =
        EditionIdentity.fromJson(jsonDecode(saved['edition_json'] as String));
    if (!allowBase && game.baseGameId != null) return null;
    final keys = game.evidence
        .where((e) => e.source == 'catalogue' && e.kind == 'artifactIdentity');
    if (keys.length != 1 || edition.members.isEmpty) return null;
    final artifacts = (jsonDecode(saved['artifacts_json'] as String) as List)
        .map((value) => RemoteArtifact.fromJson(value as Map<String, dynamic>))
        .toList();
    if (artifacts.length != edition.members.length ||
        artifacts.map((a) => a.id.key).toSet().length != artifacts.length) {
      throw const FormatException('Invalid shared edition members');
    }
    final current = <String, RemoteArtifact>{};
    int? cacheId;
    for (final member in edition.members) {
      final matching = artifacts.where((a) => a.id == member.artifactId);
      if (matching.length != 1) {
        throw const FormatException('Invalid shared artifact binding');
      }
      final old = matching.single;
      final drive = old.id.providerId == 'drive' && old.id.accountId != null;
      final candidates = await txn.rawQuery('''SELECT c.cache_id,
        g.remote_artifact FROM shared_metadata_catalogue c
        JOIN games g ON g.id = c.cache_id WHERE c.platform = ? AND
        ${drive ? 'c.provider = ? AND c.account = ? AND c.file_id = ?' : 'c.artifact_key = ?'}
        LIMIT 2''', [
        game.platformId,
        if (drive) ...['drive', old.id.accountId, old.id.providerFileId] else
          old.id.key
      ]);
      // Multiple source selections of the same object require review; do not
      // choose one by row order, title or a filename match.
      if (candidates.length != 1) return null;
      final object = RemoteArtifact.fromJson(
          jsonDecode(candidates.single['remote_artifact'] as String));
      if (!_sameContent(old, object)) return null;
      current[old.id.key] = object;
      if (keys.single.value == old.id.key) {
        cacheId = candidates.single['cache_id'] as int;
      }
    }
    if (cacheId == null) return null;
    final targetId = await LibraryStore.cachedCatalogueEditionId(txn, cacheId);
    if (targetId == null) return null;
    var target = await _identity(txn, targetId);
    if (target == null) {
      await for (final _
          in LibraryStore.catalogueEditions(txn, cacheRowId: cacheId)) {}
      target = await _identity(txn, targetId);
    }
    if (target == null) return null;
    final targetGame =
        GameIdentity.fromJson(jsonDecode(target['game_json'] as String));
    final targetEdition =
        EditionIdentity.fromJson(jsonDecode(target['edition_json'] as String));
    String? baseId;
    if (game.baseGameId != null) {
      baseId = await _recoverBaseGame(
          txn, game.baseGameId!, game.platformId, providerId);
      if (baseId == null) return null;
    }
    final reboundGame = GameIdentity.fromJson({
      ...game.toJson(),
      'id': targetGame.id,
      if (baseId != null) 'baseGameId': baseId,
      'title': targetGame.title,
      'evidence': game.evidence
          .map((e) => e.source == 'catalogue' && e.kind == 'artifactIdentity'
              ? {...e.toJson(), 'value': current[e.value]!.id.key}
              : e.toJson())
          .toList()
    });
    final reboundEdition = EditionIdentity.fromJson({
      ...edition.toJson(),
      'id': targetId,
      'gameId': targetGame.id,
      'members': edition.members
          .map((member) => {
                ...member.toJson(),
                'artifactId': current[member.artifactId.key]!.id.toJson()
              })
          .toList()
    });
    final rebound = {
      'game_json': jsonEncode(reboundGame.toJson()),
      'edition_json': jsonEncode(reboundEdition.toJson())
    };
    if (!await LibraryStore.isCurrentCatalogueIdentity(txn, rebound)) {
      return null;
    }
    if (LibraryStore.metadataIdentity(target, providerId: providerId) !=
        LibraryStore.metadataIdentity(rebound, providerId: providerId)) {
      // Only untouched automatic catalogue bindings may acquire saved manual
      // corrections. Never overwrite a current region/revision/tag/provider edit.
      if (targetGame.providerIds.isNotEmpty ||
          targetGame.baseGameId != null ||
          targetGame.matchStatus != IdentityMatchStatus.unmatched ||
          targetGame.evidence.any((e) => e.source != 'catalogue') ||
          targetEdition.providerIds.isNotEmpty ||
          targetEdition.releaseId != null ||
          targetEdition.regions.isNotEmpty ||
          targetEdition.languages.isNotEmpty ||
          targetEdition.revision != null ||
          targetEdition.patchId != null ||
          targetEdition.tags.isNotEmpty ||
          targetEdition.isTranslation != null ||
          targetEdition.translatedLanguages.isNotEmpty ||
          targetEdition.evidence.any((e) => e.source != 'catalogue')) {
        return null;
      }
      await txn.update(
          'library_game_identities',
          {
            'record_json': rebound['game_json'],
            'match_status': reboundGame.matchStatus.name
          },
          where: 'game_id = ?',
          whereArgs: [targetGame.id]);
      await txn.update(
          'library_editions', {'record_json': rebound['edition_json']},
          where: 'edition_id = ?', whereArgs: [targetId]);
      await LibraryStore.indexCanonicalGroups(txn, editionId: targetId);
    }
    return rebound;
  }

  Future<String?> _recoverBaseGame(Transaction txn, String oldGameId,
      String? platform, String providerId) async {
    final rows = await _db.query('identity_bindings',
        where: 'game_id = ?',
        whereArgs: [oldGameId],
        orderBy: 'generation DESC, edition_id',
        limit: 1);
    if (rows.isEmpty) return null;
    final saved = rows.single;
    final game =
        GameIdentity.fromJson(jsonDecode(saved['game_json'] as String));
    final edition =
        EditionIdentity.fromJson(jsonDecode(saved['edition_json'] as String));
    if (game.id != oldGameId ||
        game.platformId != platform ||
        game.baseGameId != null ||
        edition.id != saved['edition_id'] ||
        edition.gameId != game.id ||
        LibraryStore.metadataIdentity(saved) != saved['identity_key']) {
      return null;
    }
    final current = await _identity(txn, edition.id);
    if (game.evidence.every((e) =>
            !(e.source == 'catalogue' && e.kind == 'artifactIdentity')) &&
        current != null &&
        LibraryStore.metadataIdentity(current) == saved['identity_key'] &&
        await LibraryStore.isCurrentCatalogueIdentity(txn, current)) {
      return game.id;
    }
    final rebound = await _recoverCatalogueBinding(txn, saved, providerId,
        allowBase: false);
    return rebound == null
        ? null
        : GameIdentity.fromJson(jsonDecode(rebound['game_json'] as String)).id;
  }

  static bool _sameContent(RemoteArtifact old, RemoteArtifact current) {
    if (old.sizeBytes == null || old.sizeBytes != current.sizeBytes) {
      return false;
    }
    if (old.providerChecksums.isNotEmpty) {
      return old.providerChecksums.length == current.providerChecksums.length &&
          old.providerChecksums.entries.every(
              (entry) => current.providerChecksums[entry.key] == entry.value);
    }
    // A name/size alone cannot prove an unchanged object. Without checksums,
    // require the exact recorded provider version (or modification timestamp).
    final version = old.version ?? old.modifiedAt?.toUtc().toIso8601String();
    return version != null &&
        version ==
            (current.version ?? current.modifiedAt?.toUtc().toIso8601String());
  }

  /// Rebuild projections against the already published catalogue. No catalogue
  /// membership, provider match or installation is invented from cached names.
  Future<int> restore(Database destination) async {
    await requireAccess();
    final watch = Stopwatch()..start();
    assert(() {
      debugPrint('Shared metadata recovery started');
      return true;
    }());
    String? editionCursor, providerCursor;
    int? generationCursor;
    var restored = 0;
    var catalogueRows = 0, recordRows = 0;
    await destination.transaction((txn) async {
      // Android's system SQLite need not include JSON1. Decode bounded pages
      // with the existing artifact model, then index the same pinned catalogue
      // once per restore rather than rescanning it for each cached edition.
      await txn.execute('''CREATE TEMP TABLE shared_metadata_catalogue (
        cache_id INTEGER PRIMARY KEY, platform TEXT, artifact_key TEXT,
        provider TEXT, account TEXT, file_id TEXT)''');
      try {
        var cacheCursor = 0;
        while (true) {
          final rows = await txn.rawQuery(
              '''SELECT id, systemSlug, artifact_key,
            remote_artifact FROM games WHERE id > ? AND is_folder = 0
            AND remote_artifact IS NOT NULL ORDER BY id LIMIT 128''',
              [cacheCursor]);
          final batch = txn.batch();
          catalogueRows += rows.length;
          for (final row in rows) {
            final artifact = RemoteArtifact.fromJson(
                jsonDecode(row['remote_artifact'] as String));
            batch.insert('shared_metadata_catalogue', {
              'cache_id': row['id'],
              'platform': row['systemSlug'],
              'artifact_key': row['artifact_key'],
              'provider': artifact.id.providerId,
              'account': artifact.id.accountId,
              'file_id': artifact.id.providerFileId,
            });
          }
          if (rows.isNotEmpty) await batch.commit(noResult: true);
          if (rows.length < 128) break;
          cacheCursor = rows.last['id'] as int;
        }
        await txn.execute('''CREATE INDEX shared_metadata_exact ON
          shared_metadata_catalogue(platform, artifact_key)''');
        await txn.execute('''CREATE INDEX shared_metadata_object ON
          shared_metadata_catalogue(platform, provider, account, file_id)''');
        assert(() {
          debugPrint('Shared metadata catalogue indexed: '
              'rows=$catalogueRows elapsedMs=${watch.elapsedMilliseconds}');
          return true;
        }());
        while (true) {
          await requireAccess();
          final page = await _db.rawQuery(
              '''SELECT * FROM records
                ${editionCursor == null ? '' : '''WHERE edition_id > ? OR
                  (edition_id = ? AND (generation < ? OR
                    (generation = ? AND provider_id > ?)))'''}
                ORDER BY edition_id, generation DESC, provider_id LIMIT 128''',
              [
                if (editionCursor != null) ...[
                  editionCursor,
                  editionCursor,
                  generationCursor,
                  generationCursor,
                  providerCursor
                ]
              ]);
          // Restore the newest coherent binding before older provider records
          // of that edition, not whichever provider happened to be inserted first.
          for (final row in page) {
            recordRows++;
            var record = MetadataRecord.fromJson(
                jsonDecode(row['record_json'] as String));
            if (!LibraryStore.hasConsistentProvenance(record) ||
                record.editionId != row['edition_id'] ||
                record.providerId != row['provider_id'] ||
                record.refreshGeneration != row['generation'] ||
                LibraryStore.metadataIdentity(row,
                        providerId: record.providerId) !=
                    row['identity_key']) {
              throw const FormatException('Invalid shared metadata binding');
            }
            var identity = await _identity(txn, record.editionId);
            var recoveredBinding = false;
            final savedGame =
                GameIdentity.fromJson(jsonDecode(row['game_json'] as String));
            final savedEdition = EditionIdentity.fromJson(
                jsonDecode(row['edition_json'] as String));
            final catalogueMembers = savedEdition.members.isNotEmpty &&
                savedGame.evidence.any((e) =>
                    e.source == 'catalogue' && e.kind == 'artifactIdentity');
            // Even an unchanged primary binding must revalidate every bundle
            // member and its base. The catalogue anchor alone cannot detect a
            // changed second disc or a vanished original release.
            if (catalogueMembers ||
                identity == null ||
                LibraryStore.metadataIdentity(identity,
                        providerId: record.providerId) !=
                    row['identity_key']) {
              final recovered =
                  await _recoverCatalogueBinding(txn, row, record.providerId);
              if (recovered == null) continue;
              recoveredBinding = true;
              final reboundGame = GameIdentity.fromJson(
                  jsonDecode(recovered['game_json'] as String));
              final reboundEdition = EditionIdentity.fromJson(
                  jsonDecode(recovered['edition_json'] as String));
              record = MetadataRecord.fromJson({
                ...record.toJson(),
                'gameId': reboundGame.id,
                'editionId': reboundEdition.id
              });
              identity = await _identity(txn, record.editionId);
            }
            if (identity == null ||
                // Rebound edition or base IDs change the original hash; recovery
                // already checked full edition/content and current manual state.
                (!recoveredBinding &&
                    LibraryStore.metadataIdentity(identity,
                            providerId: record.providerId) !=
                        row['identity_key']) ||
                !await LibraryStore.isCurrentCatalogueIdentity(txn, identity)) {
              continue;
            }
            final existing = await txn.query('library_metadata',
                columns: ['generation_id'],
                where: 'edition_id = ? AND provider_id = ?',
                whereArgs: [record.editionId, record.providerId],
                limit: 1);
            if (existing.isNotEmpty &&
                (existing.single['generation_id'] as int) >=
                    record.refreshGeneration) {
              continue;
            }
            await LibraryStore(Future.value(destination))
                .putMetadata(record, transaction: txn);
            restored++;
          }
          if (page.length < 128) break;
          editionCursor = page.last['edition_id'] as String;
          generationCursor = page.last['generation'] as int;
          providerCursor = page.last['provider_id'] as String;
        }
        assert(() {
          debugPrint('Shared metadata bindings checked: '
              'rows=$recordRows elapsedMs=${watch.elapsedMilliseconds}');
          return true;
        }());
      } finally {
        await txn.execute('DROP TABLE shared_metadata_catalogue');
      }
    });
    // Restore immutable receipts, not an assertion of present image bytes.
    // Cache consumers validate the exact bounded hash before exposing a path;
    // opening settings must not reread the entire shared artwork collection.
    var keyCursor = '';
    var artworkRows = 0;
    while (true) {
      await requireAccess();
      final page = await _db.query('metadata_artwork_cache',
          where: 'media_key > ?',
          whereArgs: [keyCursor],
          orderBy: 'media_key',
          limit: 128);
      await destination.transaction((txn) async {
        final batch = txn.batch();
        for (final row in page) {
          artworkRows++;
          final filename = row['filename'] as String;
          final length = row['byte_length'] as int;
          if (!RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(filename) ||
              length < 57 ||
              length > MetadataArtworkCache.maxBytes) {
            continue;
          }
          batch.insert(
              'metadata_artwork_cache',
              {
                'media_key': row['media_key'],
                'filename': filename,
                'byte_length': length,
                'retrieved_at': DateTime.parse(row['retrieved_at'] as String)
                    .toUtc()
                    .toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      });
      if (page.length < 128) break;
      keyCursor = page.last['media_key'] as String;
    }
    assert(() {
      debugPrint('Shared metadata recovery completed: '
          'restored=$restored elapsedMs=${watch.elapsedMilliseconds} '
          'artworkRows=$artworkRows');
      return true;
    }());
    return restored;
  }

  /// Copy, validate and commit before changing the selected root. The original
  /// app-private files remain intact; interrupted migration can be repeated.
  Future<int> migrate(Database source, MetadataArtworkCache cache) async {
    await requireAccess();
    var cursor = 0, migrated = 0;
    while (true) {
      final page = await source.rawQuery('''SELECT rowid AS cursor, edition_id,
        provider_id FROM library_metadata WHERE rowid > ? ORDER BY rowid LIMIT 128''',
          [cursor]);
      for (final row in page) {
        final record = await LibraryStore(Future.value(source)).metadata(
            row['edition_id'] as String, row['provider_id'] as String);
        if (record == null) continue;
        final identity = await _identity(source, record.editionId);
        if (identity == null) continue;
        await preserve(record, identity, source);
        migrated++;
      }
      if (page.length < 128) break;
      cursor = page.last['cursor'] as int;
    }
    var keyCursor = '';
    while (true) {
      final page = await source.query('metadata_artwork_cache',
          where: 'media_key > ?',
          whereArgs: [keyCursor],
          orderBy: 'media_key',
          limit: 128);
      for (final row in page) {
        final blob = MetadataArtworkBlob(row['media_key'] as String,
            row['filename'] as String, row['byte_length'] as int);
        final original = File(p.join(cache.root.path, blob.filename));
        if (!await _validBlob(original, blob)) continue;
        await artworkRoot.create(recursive: true);
        final target = File(p.join(artworkRoot.path, blob.filename));
        if (!await target.exists()) {
          final staging = await artworkRoot.createTemp('migration-');
          try {
            final staged =
                await original.copy(p.join(staging.path, blob.filename));
            if (!await _validBlob(staged, blob)) {
              throw StateError('Artwork copy changed');
            }
            await staged.rename(target.path);
          } finally {
            await staging.delete(recursive: true);
          }
        }
        await preserveBlob(blob, DateTime.parse(row['retrieved_at'] as String));
      }
      if (page.length < 128) break;
      keyCursor = page.last['media_key'] as String;
    }
    return migrated;
  }
}
