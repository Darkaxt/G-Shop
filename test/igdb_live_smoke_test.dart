@Tags(['live'])
library;

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:retro_eshop/services/library_store.dart';
import 'package:retro_eshop/services/metadata/igdb_provider.dart';
import 'package:retro_eshop/services/metadata/metadata_refresh_jobs.dart';

/// Retain only fixed public boundary/status diagnostics, never auth payloads.
class _BoundaryTransport implements HttpClientAdapter {
  final _delegate = IOHttpClientAdapter();
  final boundaries = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    final response = await _delegate.fetch(options, body, cancel);
    boundaries.add('${options.uri.host}:HTTP${response.statusCode}');
    if (response.statusCode != 200) {
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 8192) break;
        bytes.addAll(chunk);
      }
      final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
      boundaries.add(text.contains('cloudfront')
          ? 'cloudfront-rejection'
          : text.contains('invalid client secret')
              ? 'invalid-client-secret'
              : text.contains('invalid client id')
                  ? 'invalid-client-id'
                  : text.contains('invalid client') ||
                          text.contains('invalid_client')
                      ? 'invalid-client'
                      : text.contains('blocked')
                          ? 'request-blocked'
                          : 'unclassified-rejection');
      return ResponseBody.fromBytes(bytes, response.statusCode,
          headers: response.headers);
    }
    return response;
  }

  @override
  void close({bool force = false}) => _delegate.close(force: force);
}

Map<String, String> _configuration() {
  final values = <String, String>{};
  final file = File('.env.local');
  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final match =
          RegExp(r'^\s*(IGDB_CLIENT_ID|IGDB_CLIENT_SECRET)\s*=\s*(.*)$')
              .firstMatch(line);
      if (match == null) continue;
      var value = match.group(2)!;
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[match.group(1)!] = value;
    }
  }
  return {...values, ...Platform.environment};
}

void main() {
  final configuration = _configuration();
  final credentials = IgdbCredentials(configuration['IGDB_CLIENT_ID'] ?? '',
      configuration['IGDB_CLIENT_SECRET'] ?? '');
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
      'real IGDB catalogue review, sourced scores and offline SQLite consumption',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LibrarySchema.install(db);
    await MetadataRefreshJobs.install(db);
    await db.execute('''CREATE TABLE games (
      id INTEGER PRIMARY KEY AUTOINCREMENT, systemSlug TEXT NOT NULL,
      displayName TEXT NOT NULL, is_folder INTEGER NOT NULL DEFAULT 0,
      artifact_key TEXT, remote_artifact TEXT)''');
    await db.insert(
        'games', {'systemSlug': 'snes', 'displayName': 'Super Mario World'});
    final jobs = MetadataRefreshJobs(Future.value(db));
    final transport = _BoundaryTransport();
    final provider = IgdbMetadataProvider(
        httpClientAdapter: transport, readCredentials: () async => credentials);
    addTearDown(provider.close);
    final job = await jobs.createFromCatalogue(providerId: provider.providerId);
    final first = await jobs.run(job.id, provider);
    expect(first.state, 'completed',
        reason:
            'Provider boundary: ${first.blockedStatus}; ${transport.boundaries}');
    expect(first.rated, 0);
    final review = (await jobs.reviewItems(job.id)).single;
    final exact = review.candidates.where((c) => c.titleMatched);
    expect(exact.length, 1,
        reason:
            'A platform/title candidate needs an explicit review identity.');
    final retry = await jobs.acceptCandidate(job.id,
        editionId: review.editionId,
        providerGameId: exact.single.providerGameId,
        contentTags: {'official'});
    final accepted = await jobs.run(retry.id, provider);
    expect(accepted.counts, {'matched': 1});
    expect(accepted.rated, 1);
    provider.close();
    final cached =
        await LibraryStore(Future.value(db)).metadata(review.editionId, 'igdb');
    expect(cached, isNotNull);
    final overall =
        cached!.ratings.firstWhere((r) => r.sourceLabel == 'IGDB overall');
    final critics =
        cached.ratings.firstWhere((r) => r.sourceLabel == 'IGDB critics');
    final users =
        cached.ratings.firstWhere((r) => r.sourceLabel == 'IGDB users');
    expect(overall.voteCount, greaterThan(0));
    expect(critics.voteCount, greaterThan(0));
    expect(users.voteCount, greaterThan(0));
    expect(cached.ratings.every((r) => !r.consensusValidated), isTrue);
    expect(
        (await db.query('metadata_provider_limits'))
            .single['requests_per_minute'],
        240);
  },
      skip: credentials.isConfigured
          ? false
          : 'Live IGDB credentials are not configured.',
      timeout: Timeout.none);
}
