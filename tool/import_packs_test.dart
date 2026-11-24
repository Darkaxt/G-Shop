// Windows prepared-pack import (CATALOGUE-READONLY-01). Imports packaging ZIPs
// into the Windows master store, which the catalogue publisher then publishes.
// Run through `flutter test tool/import_packs_test.dart`; see scripts/README.md.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/services/metadata/desktop_archive_evidence.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:g_shop/services/metadata/screenscraper_credentials.dart';
import 'package:g_shop/services/metadata/screenscraper_provider.dart';
import 'package:g_shop/services/metadata/packaging_resource_import.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final storePath = env['GSHOP_STORE'];
  final projectionPath = env['GSHOP_PROJECTION'];
  final packsPath = env['GSHOP_PACKS'];
  test('import prepared packs', () async {
    sqfliteFfiInit();
    final packs = Directory(packsPath!)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.zip'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final database =
        databaseFactoryFfiNoIsolate.openDatabase(projectionPath!);
    final store = await SharedMetadataStore.open(Directory(storePath!),
        factory: databaseFactoryFfiNoIsolate,
        existingOnly: true,
        verifyAccess: () async {});
    var games = 0;
    final failed = <String>[];
    try {
      // The importer merges with the edition's current packaging record read
      // from the library database. Project the master store into it first so a
      // stale projection cannot drop already published roles (e.g. manuals).
      print('restored ${await store.restore(await database)} record(s)');
      final cache = MetadataArtworkCache(database, store.artworkRoot,
          sharedStore: store);
      for (final pack in packs) {
        final importer = PackagingResourceImport(database, cache, store);
        try {
          final count = await importer.import(pack);
          if (importer.archiveEditionIds.isNotEmpty) {
            // Desktop-evidence packs: run the app's provider job, as
            // importPackagingResources does. Only reuse-lookup packs, whose
            // retained exact response needs no ScreenScraper request.
            if (!importer.reuseProviderResponse) {
              failed.add('${pack.path}: needs a live ScreenScraper lookup');
              continue;
            }
            final done = await _runDesktopProviderJob(
                database, store, cache, importer.archiveEditionIds);
            print('imported ${pack.path}: $done');
            if (done['metadata'] != 'completed' ||
                done['artwork'] != 'completed') {
              failed.add('${pack.path}: provider job $done');
              break; // like the app: a stopped job blocks the next pack
            }
            games += done['matched'] as int;
            continue;
          }
          games += count;
          print('imported ${pack.path}: $count game(s)');
        } on Object catch (e) {
          failed.add('${pack.path}: $e');
          print('FAILED ${pack.path}: $e');
        }
      }
    } finally {
      await store.close();
      await (await database).close();
    }
    print('SUMMARY packs=${packs.length} games=$games failed=${failed.length}');
    expect(failed, isEmpty);
  },
      skip: storePath == null || projectionPath == null || packsPath == null
          ? 'Set GSHOP_STORE, GSHOP_PROJECTION and GSHOP_PACKS'
          : false,
      timeout: Timeout.none);
}

/// The metadata + artwork jobs of MetadataControlsController._run for a
/// 'desktop-provider-import' pack. The provider has no credentials, so any
/// unexpected network request fails instead of spending quota.
Future<Map<String, Object>> _runDesktopProviderJob(Future<Database> database,
    SharedMetadataStore store, MetadataArtworkCache cache,
    List<String> editionIds) async {
  final jobs = MetadataRefreshJobs(database,
      sharedStore: Future.value(store),
      readArchiveIdentifier: (artifact, platform, _) =>
          DesktopArchiveEvidence.read(store.root, artifact, platform));
  final provider = ScreenScraperProvider(
      readDeveloperCredentials: () async => const ScreenScraperDeveloperCredentials(
          developerId: '', developerPassword: '', softwareName: ''),
      readUserCredentials: () async =>
          const ScreenScraperUserCredentials(username: '', password: ''));
  try {
    final job = await jobs.create(
        providerId: 'screenscraper',
        collectionGeneration: 'desktop-provider-import',
        editionIds: editionIds);
    final metadata = await jobs.run(job.id, provider, artworkCache: cache);
    var artworkState = 'notRun';
    if (metadata.state == 'completed') {
      final artwork = await jobs.ensureArtworkForMetadata(job.id);
      artworkState = artwork.state == 'completed'
          ? 'completed'
          : (await jobs.run(artwork.id, provider, artworkCache: cache)).state;
    }
    final finalReport = await jobs.report(job.id);
    return {
      'metadata': metadata.state,
      'artwork': artworkState,
      'matched': finalReport.counts['matched'] ?? 0,
      'counts': finalReport.counts.toString()
    };
  } finally {
    provider.close();
  }
}
