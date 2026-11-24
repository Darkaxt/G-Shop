// Windows artwork hydration (CATALOGUE-READONLY-01). Downloads ScreenScraper
// image bodies that the master store records but never fetched (the publisher's
// "missing local body" list), so the next publish can ship them. Rerunnable:
// the missing set is recomputed from the store each run, and a quota block
// ends the run cleanly. Run through `flutter test tool/hydrate_artwork_test.dart`;
// see scripts/README.md.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/metadata_cloud_library.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:g_shop/services/metadata/screenscraper_credentials.dart';
import 'package:g_shop/services/metadata/screenscraper_provider.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test answers every HttpClient request with HTTP 400; this tool
  // needs the real network for ScreenScraper.
  HttpOverrides.global = null;
  final env = Platform.environment;
  final storePath = env['GSHOP_STORE'];
  final projectionPath = env['GSHOP_PROJECTION'];
  final credentialsPath = env['GSHOP_CREDENTIALS'];
  test('hydrate missing artwork', () async {
    sqfliteFfiInit();
    final platforms = (env['GSHOP_PLATFORMS'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final batch = int.tryParse(env['GSHOP_BATCH'] ?? '') ?? 100;
    final maxJobs = int.tryParse(env['GSHOP_MAX_JOBS'] ?? '');
    final secrets = _readEnv(File(credentialsPath!));
    final provider = ScreenScraperProvider(
        readDeveloperCredentials: () async => ScreenScraperDeveloperCredentials(
            developerId: secrets['SCREENSCRAPER_DEVID'] ?? '',
            developerPassword: secrets['SCREENSCRAPER_DEVPASSWORD'] ?? '',
            softwareName: secrets['SCREENSCRAPER_SOFTNAME'] ?? ''),
        readUserCredentials: () async => ScreenScraperUserCredentials(
            username: secrets['SCREENSCRAPER_USERNAME'] ?? '',
            password: secrets['SCREENSCRAPER_PASSWORD'] ?? ''));
    final database = databaseFactoryFfiNoIsolate.openDatabase(projectionPath!);
    final store = await SharedMetadataStore.open(Directory(storePath!),
        factory: databaseFactoryFfiNoIsolate,
        existingOnly: true,
        verifyAccess: () async {});
    var fetched = 0, failed = 0, jobsRun = 0;
    String? stop;
    try {
      print('restored ${await store.restore(await database)} record(s)');
      final missing = await _missing(store, platforms);
      final total = missing.values.fold<int>(0, (n, keys) => n + keys.length);
      print('MISSING editions=${missing.length} bodies=$total');
      final cache = MetadataArtworkCache(database, store.artworkRoot,
          sharedStore: store);
      final jobs = MetadataRefreshJobs(database, sharedStore: Future.value(store));
      final editions = missing.keys.toList();
      for (var i = 0; i < editions.length; i += batch) {
        if (maxJobs != null && jobsRun >= maxJobs) {
          stop = 'max-jobs';
          break;
        }
        final slice = editions.skip(i).take(batch).toList();
        final job = await jobs.createArtwork(
            providerId: 'screenscraper',
            collectionGeneration: 'desktop-artwork-hydrate',
            editionIds: slice,
            mediaKeys: {for (final e in slice) ...missing[e]!});
        final result = await jobs.run(job.id, provider,
            recheckAccess: jobsRun == 0, artworkCache: cache);
        jobsRun++;
        final counts = result.counts;
        fetched += counts['matched'] ?? 0;
        failed += counts.entries
            .where((e) => e.key != 'matched')
            .fold<int>(0, (n, e) => n + e.value);
        print(jsonEncode({
          'job': job.id,
          'editions': '${i + slice.length}/${editions.length}',
          'state': result.state,
          'counts': counts,
        }));
        if (result.state != 'completed') {
          stop = 'job ${result.state}';
          break;
        }
      }
    } finally {
      provider.close();
      await store.close();
      await (await database).close();
    }
    print('SUMMARY jobs=$jobsRun fetched=$fetched notFetched=$failed '
        'stopped=${stop ?? 'no'}');
  },
      skip: storePath == null || projectionPath == null || credentialsPath == null
          ? 'Set GSHOP_STORE, GSHOP_PROJECTION and GSHOP_CREDENTIALS'
          : false,
      timeout: Timeout.none);
}

/// Edition -> ScreenScraper media keys the publisher would ship but that have
/// no local body (same selection as CataloguePublisher.publishGame). Videos are
/// out of scope.
Future<Map<String, Set<String>>> _missing(
    SharedMetadataStore store, Set<String> platforms) async {
  final editions = <String>{};
  await for (final packet in store.cloudPackets()) {
    if (platforms.isNotEmpty && !platforms.contains(packet['platform'])) {
      continue;
    }
    for (final row in packet['records'] as List) {
      editions.add(row['edition_id'] as String);
    }
  }
  final result = <String, Set<String>>{};
  for (final edition in editions) {
    final packet = await store.cloudPackets(editionId: edition).single;
    final screenscraper = <String>{};
    for (final row in packet['records'] as List) {
      if (row['provider_id'] != 'screenscraper') continue;
      final record =
          MetadataRecord.fromJson(jsonDecode(row['record_json'] as String));
      screenscraper.addAll(record.media.map(MetadataArtworkCache.key));
    }
    if (screenscraper.isEmpty) continue;
    final bodies = {
      for (final a in packet['artwork'] as List)
        a['media_key'] as String: a['filename'] as String
    };
    for (final entry in MetadataCloudLibrary.resources(packet).entries) {
      if (entry.key.endsWith('.mp4')) continue;
      final key = MetadataArtworkCache.key(entry.value);
      if (!screenscraper.contains(key)) continue;
      final name = bodies[key];
      if (name != null &&
          await File(p.join(store.root.path, 'artwork', name)).exists()) {
        continue;
      }
      result.putIfAbsent(edition, () => {}).add(key);
    }
  }
  return result;
}

Map<String, String> _readEnv(File file) => {
      for (final line in file.readAsLinesSync())
        if (line.contains('=') && !line.trimLeft().startsWith('#'))
          line.substring(0, line.indexOf('=')).trim():
              line.substring(line.indexOf('=') + 1).trim().replaceAll('"', '')
    };
