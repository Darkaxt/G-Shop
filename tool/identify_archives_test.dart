// Windows archive identification (#5). The app identifies a 7z ROM by its inner
// checksums only when the archive is installed locally (OwnedN64SevenZip), so the
// desktop catalogue fell back to title search for archives that were never
// installed. This tool supplies the same evidence from the read-only Drive
// mount: the container must match the catalogue artifact's size and checksums,
// hold exactly one ROM member, and that member is hashed (CRC32/MD5/SHA-1)
// exactly as the device does. The normal ScreenScraper metadata job then runs
// unchanged (same matching rules); accepted records bind the editions.
// Run through `flutter test tool/identify_archives_test.dart`; see scripts/README.md.
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/services/metadata/metadata_artwork_cache.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/services/metadata/metadata_refresh_jobs.dart';
import 'package:g_shop/services/metadata/screenscraper_credentials.dart';
import 'package:g_shop/services/metadata/screenscraper_provider.dart';
import 'package:g_shop/services/metadata/shared_metadata_store.dart';

// Disk System images (.fds) live under the NES folder and are catalogued as
// nes; ScreenScraper matches their CRC there too (FDS probe 2026-11-26).
const _extensions = {'gba': ['.gba'], 'nes': ['.nes', '.fds']};
const _maxBytes = {'gba': 32 * 1024 * 1024, 'nes': 16 * 1024 * 1024};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // real network for ScreenScraper
  final env = Platform.environment;
  final storePath = env['GSHOP_STORE'];
  final projectionPath = env['GSHOP_PROJECTION'];
  final credentialsPath = env['GSHOP_CREDENTIALS'];
  final editionsPath = env['GSHOP_EDITIONS'];
  final romsRoot = env['GSHOP_ROMS'] ?? r'H:\My Drive\Roms';
  final sevenZip = env['GSHOP_7Z'] ?? r'C:\Users\darka\scoop\shims\7z.exe';
  test('identify archives', () async {
    sqfliteFfiInit();
    final editions = (jsonDecode(File(editionsPath!).readAsStringSync())
            as List)
        .cast<String>();
    final batch = int.tryParse(env['GSHOP_BATCH'] ?? '') ?? 100;
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
    final reads = <String, int>{};
    String? stop;
    try {
      print('restored ${await store.restore(await database)} record(s)');
      await MetadataRefreshJobs.recoverInterrupted(await database);
      final cache = MetadataArtworkCache(database, store.artworkRoot,
          sharedStore: store);
      final jobs = MetadataRefreshJobs(database,
          sharedStore: Future.value(store),
          readArchiveIdentifier: (artifact, platformId, cancel) async {
        final outcome = await _identify(romsRoot, sevenZip, artifact, platformId);
        reads[outcome.$2] = (reads[outcome.$2] ?? 0) + 1;
        return outcome.$1;
      });
      for (var i = 0; i < editions.length; i += batch) {
        final slice = editions.skip(i).take(batch).toList();
        final job = await jobs.create(
            providerId: 'screenscraper',
            collectionGeneration: 'desktop-archive-identify',
            editionIds: slice);
        final result = await jobs.run(job.id, provider,
            recheckAccess: i == 0, artworkCache: cache);
        print(jsonEncode({
          'job': job.id,
          'editions': '${i + slice.length}/${editions.length}',
          'state': result.state,
          'counts': result.counts,
          'archiveReads': reads,
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
    print('SUMMARY reads=${jsonEncode(reads)} stopped=${stop ?? 'no'}');
  },
      skip: [storePath, projectionPath, credentialsPath, editionsPath]
              .contains(null)
          ? 'Set GSHOP_STORE, GSHOP_PROJECTION, GSHOP_CREDENTIALS and GSHOP_EDITIONS'
          : false,
      timeout: Timeout.none);
}

/// Same acceptance as the device's local-archive reader: an exact container
/// (size and every catalogue checksum), one safe ROM member, its full CRC32,
/// MD5 and SHA-1. Anything else is an ordinary "no raw evidence" outcome.
Future<(MetadataRomIdentifier?, String)> _identify(String romsRoot,
    String sevenZip, RemoteArtifact artifact, String platformId) async {
  final extensions = _extensions[platformId];
  if (extensions == null || !artifact.displayName.toLowerCase().endsWith('.7z')) {
    return (null, 'unsupported');
  }
  final file = File(p.joinAll([romsRoot, ...artifact.displayPath.split('/')]));
  if (!await file.exists()) return (null, 'absent');
  final container = await file.readAsBytes();
  if (container.length != artifact.sizeBytes) return (null, 'containerChanged');
  final digests = {
    'md5': md5.convert(container).toString(),
    'sha1': sha1.convert(container).toString(),
    'sha256': sha256.convert(container).toString(),
  };
  if (artifact.providerChecksums.isEmpty ||
      artifact.providerChecksums.entries
          .any((e) => digests.containsKey(e.key) && digests[e.key] != e.value)) {
    return (null, 'containerChanged');
  }
  final listing = await Process.run(sevenZip, ['l', '-slt', '-ba', file.path],
      stdoutEncoding: utf8);
  if (listing.exitCode != 0) return (null, 'unreadable');
  final members = <Map<String, String>>[];
  var current = <String, String>{};
  for (final line in '${listing.stdout}\n'.split(RegExp(r'\r?\n'))) {
    if (line.trim().isEmpty) {
      if (current.containsKey('Path')) members.add(current);
      current = {};
      continue;
    }
    final at = line.indexOf(' = ');
    if (at > 0) current[line.substring(0, at)] = line.substring(at + 3);
  }
  if (members.length != 1 || members.single['Folder'] == '+') {
    return (null, 'notSingleRom');
  }
  final name = members.single['Path']!;
  if (!extensions.any(name.toLowerCase().endsWith) ||
      name.startsWith('.') ||
      name.contains(RegExp(r'[/\\:\x00-\x1f\x7f]'))) {
    return (null, 'notSingleRom');
  }
  final extracted = await Process.run(sevenZip, ['e', '-so', file.path, name],
      stdoutEncoding: null);
  final rom = extracted.stdout as List<int>;
  if (extracted.exitCode != 0 ||
      rom.isEmpty ||
      rom.length > _maxBytes[platformId]! ||
      '${rom.length}' != members.single['Size'] ||
      (platformId == 'nes' &&
          name.toLowerCase().endsWith('.nes') &&
          (rom.length < 4 || rom[0] != 0x4e || rom[1] != 0x45 || rom[2] != 0x53 || rom[3] != 0x1a))) {
    return (null, 'invalidRom');
  }
  final crc = getCrc32(rom).toRadixString(16).padLeft(8, '0');
  if (crc.toUpperCase() != members.single['CRC']?.toUpperCase()) {
    return (null, 'invalidRom');
  }
  return (
    MetadataRomIdentifier(
        kind: RomIdentifierKind.rawRom,
        filename: name,
        sizeBytes: rom.length,
        crc32: crc,
        md5: md5.convert(rom).toString(),
        sha1: sha1.convert(rom).toString()),
    'identified'
  );
}

Map<String, String> _readEnv(File file) => {
      for (final line in file.readAsLinesSync())
        if (line.contains('=') && !line.trimLeft().startsWith('#'))
          line.substring(0, line.indexOf('=')).trim():
              line.substring(line.indexOf('=') + 1).trim().replaceAll('"', '')
    };
