import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/features/library/widgets/library_entry.dart';
import 'package:g_shop/models/game_item.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/ra_models.dart';
import 'package:g_shop/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

GameItem game({String account = 'a', String file = 'f', String version = '1',
    String name = 'Same.gg', String digest = 'a', int size = 4,
    Map<String, String>? checksums}) => GameItem(filename: name,
    displayName: name, url: '', remoteArtifact: RemoteArtifact(
      id: RemoteArtifactId(providerId: 'drive', sourceId: 'source',
        accountId: account, providerFileId: file), parentId: 'folder',
      displayPath: name, displayName: name, version: version, sizeBytes: size,
      providerChecksums: checksums ?? {'md5': digest}, canDownload: true));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('achievement matches follow exact content, not names or stable favorites', () {
    final original = game();
    expect(original.raMatchKey, game(name: 'Renamed.gg').raMatchKey);
    for (final other in [game(account: 'b'), game(file: 'other'),
        game(version: '2'), game(digest: 'b'), game(size: 5)]) {
      expect(original.raMatchKey, isNot(other.raMatchKey));
    }
    expect(original.selectionKey, game(version: '2').selectionKey);
    final legacy = const GameItem(filename: 'Same.gg', displayName: 'Same', url: '');
    expect(legacy.raMatchKey, legacy.filename);
    expect(original.raMatchKey, isNot(legacy.raMatchKey));
    // NUL cannot be a filesystem filename; exact keys cannot alias legacy names.
    expect(original.raMatchKey.startsWith('\u0000'), isTrue);
  });
  test('library and detail use one deterministic content key', () {
    final item = game(checksums: {'sha256': 'b', 'md5': 'a'});
    expect(item.raMatchKey,
        game(checksums: {'md5': 'a', 'sha256': 'b'}).raMatchKey);
    final entry = LibraryEntry(filename: item.filename, displayName: item.displayName,
        cardTitle: item.displayName, url: '', systemSlug: 'gamegear',
        remoteArtifact: item.remoteArtifact);
    expect(entry.raMatchKey, item.raMatchKey);
  });
  test('persisted exact match cannot modify legacy or another content version', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE ra_matches (
      game_filename TEXT NOT NULL, system_slug TEXT NOT NULL, ra_game_id INTEGER,
      match_type TEXT NOT NULL, is_mastered INTEGER NOT NULL, last_updated INTEGER,
      PRIMARY KEY(game_filename, system_slug))''');
    await db.execute('''CREATE TABLE ra_games (ra_game_id INTEGER PRIMARY KEY,
      title TEXT, num_achievements INTEGER, points INTEGER, image_icon TEXT)''');
    DatabaseService.testDatabase = db;
    try {
      final service = DatabaseService();
      await service.saveRaMatch('Same.gg', 'gamegear', const RaMatchResult(
        type: RaMatchType.nameMatch, raGameId: 1));
      await service.saveRaMatch(game().raMatchKey, 'gamegear', const RaMatchResult(
        type: RaMatchType.hashVerified, raGameId: 2));
      await service.updateRaMastered(game().raMatchKey, 'gamegear', true);
      final matches = await service.getRaMatchesForSystem('gamegear');
      expect(matches['Same.gg']!.raGameId, 1);
      expect(matches['Same.gg']!.isMastered, isFalse);
      expect(matches[game().raMatchKey]!.raGameId, 2);
      expect(matches[game().raMatchKey]!.isMastered, isTrue);
      expect(matches[game(version: '2').raMatchKey], isNull);
      expect(matches[game(account: 'b').raMatchKey], isNull);
    } finally { DatabaseService.resetForTesting(); await db.close(); }
  });
}
