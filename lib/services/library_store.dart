import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../models/library_identity.dart';
import '../models/scraped_metadata.dart';

/// Additive v14 schema. Legacy file-keyed cache and anonymous ratings remain
/// untouched; they are not promoted into the fresh identity/metadata namespace.
class LibrarySchema {
  LibrarySchema._();

  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS library_game_identities (
      game_id TEXT PRIMARY KEY, platform_id TEXT, title TEXT NOT NULL,
      match_status TEXT NOT NULL, record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_library_platform
      ON library_game_identities(platform_id, game_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_editions (
      edition_id TEXT PRIMARY KEY, game_id TEXT NOT NULL, record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_library_edition_game
      ON library_editions(game_id, edition_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_artifacts (
      artifact_id TEXT PRIMARY KEY, provider_id TEXT NOT NULL,
      source_id TEXT NOT NULL, account_id TEXT, provider_file_id TEXT NOT NULL,
      record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_library_artifact_source
      ON library_artifacts(source_id, account_id, artifact_id)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS library_metadata (
      edition_id TEXT NOT NULL, provider_id TEXT NOT NULL,
      provider_game_id TEXT NOT NULL, generation_id INTEGER NOT NULL,
      retrieved_at TEXT NOT NULL, identity_key TEXT NOT NULL, record_json TEXT NOT NULL,
      PRIMARY KEY (edition_id, provider_id)
    )''');
  }
}

/// Identity persistence independent of file cache eviction and local residency.
/// The normal DatabaseService opens/migrates this database; injecting its future
/// also permits real SQLite tests without a second production database singleton.
class LibraryStore {
  final Future<Database> _database;
  LibraryStore(this._database);

  Future<void> putGame(GameIdentity game) async {
    final db = await _database;
    await db.insert(
        'library_game_identities',
        {
          'game_id': game.id,
          'platform_id': game.platformId,
          'title': game.title,
          'match_status': game.matchStatus.name,
          'record_json': jsonEncode(game.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> putEdition(EditionIdentity edition) async {
    final db = await _database;
    await db.transaction((txn) async {
      final game = await txn.query('library_game_identities',
          columns: ['game_id'],
          where: 'game_id = ?',
          whereArgs: [edition.gameId],
          limit: 1);
      if (game.isEmpty) {
        throw StateError('Edition requires a known game identity');
      }
      final existing = await txn.query('library_editions',
          columns: ['game_id'],
          where: 'edition_id = ?',
          whereArgs: [edition.id],
          limit: 1);
      if (existing.isNotEmpty && existing.single['game_id'] != edition.gameId) {
        throw StateError(
            'Edition reassignment requires explicit reconciliation');
      }
      await txn.insert(
          'library_editions',
          {
            'edition_id': edition.id,
            'game_id': edition.gameId,
            'record_json': jsonEncode(edition.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> putArtifact(RemoteArtifact artifact) async {
    final db = await _database;
    await db.insert(
        'library_artifacts',
        {
          'artifact_id': artifact.id.key,
          'provider_id': artifact.id.providerId,
          'source_id': artifact.id.sourceId,
          'account_id': artifact.id.accountId,
          'provider_file_id': artifact.id.providerFileId,
          'record_json': jsonEncode(artifact.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> _record(
      String table, String column, String id) async {
    final db = await _database;
    final rows = await db.query(table,
        columns: ['record_json'],
        where: '$column = ?',
        whereArgs: [id],
        limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.single['record_json'] as String)
        as Map<String, dynamic>;
  }

  Future<GameIdentity?> game(String id) async {
    final record = await _record('library_game_identities', 'game_id', id);
    return record == null ? null : GameIdentity.fromJson(record);
  }

  Future<EditionIdentity?> edition(String id) async {
    final record = await _record('library_editions', 'edition_id', id);
    return record == null ? null : EditionIdentity.fromJson(record);
  }

  Future<RemoteArtifact?> artifact(RemoteArtifactId id) async {
    final record = await _record('library_artifacts', 'artifact_id', id.key);
    return record == null ? null : RemoteArtifact.fromJson(record);
  }

  Future<void> putMetadata(MetadataRecord record,
      {Transaction? transaction}) async {
    if (!hasConsistentProvenance(record)) {
      throw StateError('Metadata provenance is inconsistent');
    }
    Future<void> write(Transaction txn) async {
      final identities = await txn.rawQuery('''
        SELECT g.platform_id, g.record_json AS game_json, e.record_json AS edition_json
        FROM library_editions e
        JOIN library_game_identities g ON g.game_id = e.game_id
        WHERE e.edition_id = ? AND e.game_id = ?
      ''', [record.editionId, record.gameId]);
      if (identities.isEmpty ||
          identities.single['platform_id'] != record.platformId) {
        throw StateError(
            'Metadata requires matching game, edition and platform');
      }
      final game = GameIdentity.fromJson(
          jsonDecode(identities.single['game_json'] as String)
              as Map<String, dynamic>);
      final assignedProviderId = game.providerIds[record.providerId];
      if (assignedProviderId != null &&
          assignedProviderId != record.providerGameId) {
        throw StateError(
            'Metadata cannot replace an assigned provider identity');
      }
      final previous = await txn.query('library_metadata',
          columns: ['generation_id'],
          where: 'edition_id = ? AND provider_id = ?',
          whereArgs: [record.editionId, record.providerId],
          limit: 1);
      if (previous.isNotEmpty &&
          (previous.single['generation_id'] as int) >
              record.refreshGeneration) {
        throw StateError(
            'A stale metadata generation cannot replace a newer one');
      }
      await txn.insert(
          'library_metadata',
          {
            'edition_id': record.editionId,
            'provider_id': record.providerId,
            'provider_game_id': record.providerGameId,
            'generation_id': record.refreshGeneration,
            'retrieved_at': record.retrievedAt.toUtc().toIso8601String(),
            'identity_key': metadataIdentity(identities.single),
            'record_json': jsonEncode(record.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    if (transaction != null) {
      await write(transaction);
    } else {
      final db = await _database;
      await db.transaction(write);
    }
  }

  static bool hasConsistentProvenance(MetadataRecord record) =>
      record.providerId.trim().isNotEmpty &&
      record.providerGameId.trim().isNotEmpty &&
      record.refreshGeneration >= 0 &&
      record.ratings.every((rating) =>
          rating.sourceId == record.providerId &&
          rating.providerGameId == record.providerGameId) &&
      record.fieldProvenance.entries.every((entry) =>
          entry.value.providerId == record.providerId &&
          entry.value.providerGameId == record.providerGameId &&
          entry.key == entry.value.field &&
          entry.key.trim().isNotEmpty);

  Future<MetadataRecord?> metadata(String editionId, String providerId) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT m.record_json, m.identity_key, g.record_json AS game_json,
        e.record_json AS edition_json
      FROM library_metadata m
      JOIN library_editions e ON e.edition_id = m.edition_id
      JOIN library_game_identities g ON g.game_id = e.game_id
      WHERE m.edition_id = ? AND m.provider_id = ? LIMIT 1
    ''', [editionId, providerId]);
    if (rows.isEmpty) return null;
    if (rows.single['identity_key'] != metadataIdentity(rows.single)) {
      return null;
    }
    return MetadataRecord.fromJson(
        jsonDecode(rows.single['record_json'] as String)
            as Map<String, dynamic>);
  }

  /// Metadata stays stored as evidence, but cannot be consumed under a changed
  /// game/edition/patch identity. Display-name-only renames are not identity edits.
  static String metadataIdentity(Map<String, Object?> row) {
    final game = jsonDecode(row['game_json'] as String) as Map<String, dynamic>;
    game.remove('title');
    final edition = jsonDecode(row['edition_json'] as String);
    return sha256.convert(utf8.encode(jsonEncode([game, edition]))).toString();
  }
}
