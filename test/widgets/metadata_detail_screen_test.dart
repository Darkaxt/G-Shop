import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/features/game_detail/game_detail_screen.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/game_metadata_info.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/providers/library_providers.dart';
import 'package:retro_eshop/services/database_service.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';
import 'package:retro_eshop/services/storage_service.dart';
import '../helpers/pump_helpers.dart';

class _Database extends DatabaseService {
  final Database db;
  final ready = Completer<void>();
  bool fail = false;
  _Database(this.db);

  @override
  Future<Database> get database async => db;

  @override
  Future<GameMetadataInfo?> getGameMetadata(String filename, String systemSlug,
      {String language = 'en'}) async {
    await ready.future;
    if (fail) throw StateError('Synthetic cache read failure');
    return super.getGameMetadata(filename, systemSlug, language: language);
  }
}

void main() {
  for (final size in [
    const Size(1920, 1080),
    const Size(1280, 720),
    const Size(720, 1280)
  ]) {
    testWidgets(
        'normal details show exact cached score and retry a failed read ($size)',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      sqfliteFfiInit();
      final db =
          await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await LibrarySchema.install(db);
      await MetadataRefreshJobs.install(db);
      await db.execute('''CREATE TABLE games(id INTEGER PRIMARY KEY,
      systemSlug TEXT, displayName TEXT, filename TEXT, url TEXT,
      artifact_key TEXT, remote_artifact TEXT, is_folder INTEGER DEFAULT 0)''');
      await LibraryQuery.install(db);
      await db.insert('games', {
        'id': 1,
        'systemSlug': 'psx',
        'displayName': 'Game',
        'filename': 'Game.7z',
        'url': 'https://example.invalid/game'
      });
      final store = LibraryStore(Future.value(db));
      final editionId = (await db.transaction((txn) =>
              LibraryStore.catalogueEditions(txn, cacheRowId: 1).toList()))
          .single;
      final edition = (await store.edition(editionId))!;
      final gameIdentity = (await store.game(edition.gameId))!;
      await store.putGame(GameIdentity.fromJson({
        ...gameIdentity.toJson(),
        'matchStatus': 'manuallyMatched',
        'providerIds': {'igdb': '1'}
      }));
      await store.putEdition(EditionIdentity.fromJson({
        ...edition.toJson(),
        'tags': ['official']
      }));
      final at = DateTime.utc(2026, 10, 3);
      await store.putMetadata(MetadataRecord(
          gameId: gameIdentity.id,
          editionId: editionId,
          platformId: 'psx',
          providerId: 'igdb',
          providerGameId: '1',
          retrievedAt: at,
          refreshGeneration: 1,
          matchMethod: 'verifiedProviderIdGlobalGame',
          titles: const [
            MetadataText(text: 'Game')
          ],
          descriptions: const [
            MetadataText(text: 'Cached description')
          ],
          fieldProvenance: {
            'description': MetadataFieldProvenance(
                providerId: 'igdb',
                providerGameId: '1',
                field: 'description',
                retrievedAt: at)
          },
          ratings: [
            SourcedRating.parse(
                sourceId: 'igdb',
                sourceLabel: 'IGDB users',
                providerGameId: '1',
                rawValue: 89,
                scaleMinimum: 0,
                scaleMaximum: 100,
                voteCount: 100,
                kind: RatingKind.communityAggregate,
                retrievedAt: at)!
          ]));
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final database = _Database(db);
      final container = ProviderContainer(overrides: [
        libraryDbProvider.overrideWithValue(database),
        storageServiceProvider.overrideWithValue(storage),
        bootstrappedConfigProvider.overrideWith((ref) async => AppConfig.empty),
      ]);
      addTearDown(container.dispose);
      final game = GameItem(
          filename: 'Game.7z',
          displayName: 'Game',
          url: 'https://example.invalid/game');
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: createTestApp(GameDetailScreen(
              game: game,
              variants: [game],
              system:
                  SystemModel.supportedSystems.firstWhere((s) => s.id == 'psx'),
              targetFolder: 'D:/Temp/rshop-no-installed-ROM'))));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      database.ready.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('IGDB users 89/100'), findsOneWidget);
      expect(find.textContaining('Avg Rating'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Game Info'));
      await tester.pumpAndSettle();
      expect(find.textContaining('IGDB users: 89/100'), findsOneWidget);
      expect(find.textContaining('100'), findsWidgets);
      expect(find.textContaining('igdb #1'), findsOneWidget);
      expect(find.text('Official releases'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      database.fail = true;
      container.read(gameDbChangedProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Cached metadata is unavailable. ROM actions remain available.'),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      database.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('IGDB users 89/100'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
