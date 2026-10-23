// Explicit Windows acquisition. Run with Dart, without Flutter or an APK.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:g_shop/services/metadata/metadata_provider.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/metadata/screenscraper_credentials.dart';
import 'package:g_shop/services/metadata/screenscraper_provider.dart';
import 'metadata_crawl_support.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.isEmpty) {
    stdout.writeln('crawl_metadata.dart --manifest FILE --output DIRECTORY '
        '--archive-classpath CLASSPATH [--java java] [--credentials .env.local] [--max-archive-bytes N]');
    return;
  }
  try {
    await run(args);
  } catch (_) {
    // Provider exceptions may carry authenticated URLs. Never print them.
    stderr.writeln('Crawl stopped. Inspect the credential-free checkpoint; '
        'inputs, credentials or archive validation require attention.');
    exitCode = 1;
  }
}

Future<void> run(List<String> args) async {
  final options = <String, String>{};
  const allowed = {
    '--manifest',
    '--output',
    '--archive-classpath',
    '--java',
    '--credentials',
    '--max-archive-bytes'
  };
  for (var n = 0; n < args.length; n += 2) {
    if (!allowed.contains(args[n]) ||
        n + 1 == args.length ||
        options.containsKey(args[n])) {
      throw const FormatException('Invalid arguments');
    }
    options[args[n]] = args[n + 1];
  }
  final byteBudget = int.parse(options['--max-archive-bytes'] ?? '0');
  if (byteBudget < 0) throw const FormatException('Invalid byte budget');
  final manifestFile = File(options['--manifest']!);
  final manifestBytes = await manifestFile.readAsBytes();
  final items = parseCrawlManifest(jsonDecode(utf8.decode(manifestBytes)));
  final manifestHash = sha256.convert(manifestBytes).toString();
  final output = Directory(options['--output']!).absolute;
  if (Platform.isWindows &&
      !RegExp(r'^E:[/\\]', caseSensitive: false).hasMatch(output.path)) {
    throw const FormatException('Persistent acquisition cache belongs on E:');
  }
  await output.create(recursive: true);
  final lock =
      await File('${output.path}/owner.lock').open(mode: FileMode.append);
  await lock.lock(FileLock.exclusive);
  ScreenScraperProvider? api;
  try {
    final checkpoint = File('${output.path}/checkpoint.json');
    final state = await checkpoint.exists()
        ? (jsonDecode(await checkpoint.readAsString()) as Map)
            .cast<String, dynamic>()
        : <String, dynamic>{
            'version': 2,
            'manifestSha256': manifestHash,
            'items': <String, dynamic>{}
          };
    if (state['version'] != 2 || state['manifestSha256'] != manifestHash) {
      throw const FormatException('Resume requires the same exact manifest');
    }
    if ((state['archiveByteBudget'] ?? byteBudget) != byteBudget) {
      throw const FormatException(
          'Use a new output directory for a different read budget');
    }
    state['archiveByteBudget'] = byteBudget;
    var archiveBytesRead = state['archiveBytesRead'] as int? ?? 0;
    final completed = (state['items'] as Map).cast<String, dynamic>();
    Future<void> save() async {
      await File('${checkpoint.path}.next')
          .writeAsString(jsonEncode(state), flush: true);
      await File('${checkpoint.path}.next').rename(checkpoint.path);
    }

    final secrets = await readCrawlCredentials(
        File(options['--credentials'] ?? '.env.local'));
    final developer = ScreenScraperDeveloperCredentials(
        developerId: secrets['SCREENSCRAPER_DEVID'] ?? '',
        developerPassword: secrets['SCREENSCRAPER_DEVPASSWORD'] ?? '',
        softwareName: secrets['SCREENSCRAPER_SOFTNAME'] ?? '');
    final user = ScreenScraperUserCredentials(
        username: secrets['SCREENSCRAPER_USERNAME'] ?? '',
        password: secrets['SCREENSCRAPER_PASSWORD'] ?? '');
    if (!developer.isConfigured || !user.isConfigured) {
      throw const FormatException('Credentials missing');
    }
    api = ScreenScraperProvider(
        readDeveloperCredentials: () async => developer,
        readUserCredentials: () async => user);
    final accessWait = (state['nextAllowedAt'] as int? ?? 0) -
        DateTime.now().millisecondsSinceEpoch;
    if (accessWait > 0) {
      await Future<void>.delayed(Duration(milliseconds: accessWait));
    }
    final access = await api.checkAccess();
    state['accessStatus'] = access.status.name;
    await save();
    if (access.status != MetadataLookupStatus.matched || access.quota == null) {
      throw StateError('Provider access unavailable');
    }
    var quota = access.quota!;
    var budget = quota.maxRequestsPerDay! - quota.requestsToday!;
    state.remove('blockedStatus');
    Future<bool> slot() async {
      if (budget <= 0 ||
          quota.maxThreads == 0 ||
          quota.maxRequestsPerMinute == 0 ||
          (quota.maxRequestsPerDay != null &&
              quota.requestsToday != null &&
              quota.requestsToday! >= quota.maxRequestsPerDay!) ||
          (quota.maxUnmatchedPerDay != null &&
              quota.unmatchedToday != null &&
              quota.unmatchedToday! >= quota.maxUnmatchedPerDay!)) {
        return false;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final next = state['nextAllowedAt'] as int? ?? 0;
      if (next > now) {
        await Future<void>.delayed(Duration(milliseconds: next - now));
      }
      final rate = quota.maxRequestsPerMinute!;
      state['nextAllowedAt'] =
          DateTime.now().millisecondsSinceEpoch + (60000 / rate).ceil();
      budget--;
      // Reserve before network IO. This delay implements the provider protocol,
      // not a completion timeout or a retry policy.
      await save();
      return true;
    }

    void progress() => stdout.writeln(jsonEncode({
          'total': items.length,
          'processed': completed.length,
          'remaining': items.length - completed.length,
          'outcomes': crawlOutcomeCounts(completed)
        }));
    progress();
    for (final item in items) {
      final request = MetadataLookupRequest.fromJson(item['request']);
      final key = crawlItemKey(item);
      if (completed.containsKey(key)) {
        if (completed[key] != 'archiveValidationFailed') {
          final saved =
              jsonDecode(await File('${output.path}/$key.json').readAsString())
                  as Map;
          await verifyRetainedCrawlResult(saved, manifestHash, key, output);
        }
        continue;
      }
      final resultFile = File('${output.path}/$key.json');
      // Verify retained content before treating a completed item as acquired.
      if (await resultFile.exists()) {
        final result = jsonDecode(await resultFile.readAsString()) as Map;
        await verifyRetainedCrawlResult(result, manifestHash, key, output);
        completed[key] = result['status'];
        state['items'] = completed;
        await save();
        progress();
        continue;
      }
      final archive = item['archive'] as Map<String, dynamic>;
      Map<String, dynamic>? observation;
      var bound = request;
      var localStatus = 'validated';
      final plannedBytes = archive['artifact']['sizeBytes'] as int;
      final archiveReceipt = File('${output.path}/$key.archive.json');
      if (await archiveReceipt.exists()) {
        observation = retainedCrawlObservation(
            jsonDecode(await archiveReceipt.readAsString()) as Map,
            item,
            manifestHash,
            key);
        bound = MetadataLookupRequest.fromJson(
            {...request.toJson(), 'romIdentifier': observation['raw']});
      } else if (item['allowRawBinding'] != true ||
          archiveBytesRead + plannedBytes > byteBudget) {
        localStatus = 'notReadMetadataOnly';
      } else {
        try {
          archiveBytesRead += plannedBytes;
          state['archiveBytesRead'] = archiveBytesRead;
          await save();
          final process = await Process.run(options['--java'] ?? 'java', [
            '-cp',
            options['--archive-classpath']!,
            'com.retro.rshop.DesktopArchiveIdentifier',
            request.platformId,
            archive['path'] as String
          ]);
          if (process.exitCode != 0) {
            throw const FormatException('Unsupported or invalid archive');
          }
          observation = (jsonDecode(process.stdout as String) as Map)
              .cast<String, dynamic>();
          validateCrawlObservation(item, observation);
          // A later provider/artwork interruption must not consume the ROM-read
          // budget again. Retain evidence bound to this immutable artifact.
          await writeCrawlJson(archiveReceipt, {
            'version': 2,
            'manifestSha256': manifestHash,
            'key': key,
            'observation': observation
          });
          if (item['allowRawBinding'] == true) {
            bound = MetadataLookupRequest.fromJson(
                {...request.toJson(), 'romIdentifier': observation['raw']});
          }
        } catch (_) {
          localStatus = 'archiveValidationFailed';
        }
      }
      // Fail closed on missing/changed/unsupported bytes. Do not conceal it with
      // another title search or turn container hashes into raw identifiers.
      if (!{'validated', 'notReadMetadataOnly'}.contains(localStatus)) {
        completed[key] = localStatus;
        state['items'] = completed;
        await save();
        progress();
        continue;
      }
      final lookupFile = File('${output.path}/$key.lookup.json');
      Map<String, dynamic> lookup;
      if (await lookupFile.exists()) {
        lookup = (jsonDecode(await lookupFile.readAsString()) as Map)
            .cast<String, dynamic>();
        if (lookup['manifestSha256'] != manifestHash ||
            lookup['key'] != key ||
            jsonEncode(lookup['request']) != jsonEncode(bound.toJson())) {
          throw const FormatException('Retained lookup binding changed');
        }
      } else {
        if (!await slot()) {
          state['blockedStatus'] = 'quotaExceeded';
          await save();
          break;
        }
        final reply = await api.lookup(bound);
        quota = reply.quota ?? quota;
        lookup = {
          'manifestSha256': manifestHash,
          'key': key,
          'request': bound.toJson(),
          'status': reply.status.name,
          'record': reply.record?.toJson(),
          'officialRomEvidence': reply.officialRomEvidence?.toJson(),
          'candidates': [
            for (final c in reply.candidates)
              {
                'providerGameId': c.providerGameId,
                'platformId': c.platformId,
                'titles': c.titles.map((t) => t.toJson()).toList(),
                'evidence': c.evidence
              }
          ]
        };
        if (crawlStatusBlocks(reply.status.name)) {
          state['blockedStatus'] = reply.status.name;
          await save();
          break;
        }
        await writeCrawlJson(lookupFile, lookup);
      }
      final record = lookup['record'] == null
          ? null
          : MetadataRecord.fromJson(lookup['record']);
      final resourceResults = <Map<String, dynamic>>[];
      var artworkBlocked = false;
      final artworkFile = File('${output.path}/$key.artwork.json');
      if (await artworkFile.exists()) {
        resourceResults.addAll(
            (jsonDecode(await artworkFile.readAsString()) as List)
                .map((r) => (r as Map).cast<String, dynamic>()));
      }
      if (lookup['status'] == 'matched' && record != null) {
        if (record.gameId != bound.gameId ||
            record.editionId != bound.editionId ||
            record.platformId != bound.platformId) {
          throw const FormatException('Binding changed');
        }
        for (final media in crawlArtworkSelection(record, bound.region)) {
          final retained = resourceResults.where(
              (r) => jsonEncode(r['media']) == jsonEncode(media.toJson()));
          if (retained.isNotEmpty) {
            await verifyRetainedCrawlArtwork(retained.single, output);
            continue;
          }
          if (!await slot()) {
            state['blockedStatus'] = 'quotaExceeded';
            artworkBlocked = true;
            break;
          }
          final bytes = <int>[];
          final fetched = await api.fetchArtwork(media,
              write: (chunk) async => bytes.addAll(chunk));
          quota = fetched.quota ?? quota;
          final resource = <String, dynamic>{
            'media': media.toJson(),
            'status': fetched.status.name
          };
          if (fetched.status == MetadataLookupStatus.matched) {
            validateCrawlPng(bytes);
            final digest = sha256.convert(bytes).toString();
            await File('${output.path}/$digest.png')
                .writeAsBytes(bytes, flush: true);
            resource.addAll({
              'sha256': digest,
              'bytes': bytes.length,
              'file': '$digest.png'
            });
          }
          if (crawlStatusBlocks(fetched.status.name)) {
            state['blockedStatus'] = fetched.status.name;
            artworkBlocked = true;
            break;
          }
          resourceResults.add(resource);
          await writeCrawlJson(artworkFile, resourceResults);
        }
      }
      if (artworkBlocked) {
        await save();
        break;
      }
      final result = {
        ...lookup,
        'version': 2,
        'archiveObservation': observation,
        'archiveReadStatus': localStatus,
        'artwork': resourceResults,
        'published': false,
        'nativeAccepted': false
      };
      await writeCrawlJson(resultFile, result);
      completed[key] = lookup['status'];
      state['items'] = completed;
      await save();
      progress();
    }
    if (state['blockedStatus'] != null) exitCode = 2;
  } finally {
    api?.close();
    await lock.unlock();
    await lock.close();
  }
}
