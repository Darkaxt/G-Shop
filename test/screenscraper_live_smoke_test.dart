@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/screenscraper_provider.dart';

/// Explicit opt-in only; secrets remain in the ignored local file or environment.
/// No provider body, credentials, media URL or private account data is printed.
Map<String, String> _credentials() {
  final values = <String, String>{};
  final file = File('.env.local');
  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final match =
          RegExp(r'^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*)$').firstMatch(line);
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
  values.addAll(Platform.environment);
  return values;
}

void main() {
  final values = _credentials();
  final developer = ScreenScraperDeveloperCredentials(
    developerId: values['SCREENSCRAPER_DEVID'] ?? '',
    developerPassword: values['SCREENSCRAPER_DEVPASSWORD'] ?? '',
    softwareName: values['SCREENSCRAPER_SOFTNAME'] ?? '',
  );
  final user = ScreenScraperUserCredentials(
    username: values['SCREENSCRAPER_USERNAME'] ?? '',
    password: values['SCREENSCRAPER_PASSWORD'] ?? '',
  );

  test('real standalone adapter authenticates, reviews and retrieves metadata',
      () async {
    final provider = ScreenScraperProvider(
      readDeveloperCredentials: () async => developer,
      readUserCredentials: () async => user,
    );
    addTearDown(provider.close);
    final search = await provider.lookup(MetadataLookupRequest(
      gameId: 'live-proof-snes-smw',
      editionId: 'live-proof-snes-smw-official',
      platformId: 'snes',
      title: 'Super Mario World',
      contentTags: const {'official'},
      refreshGeneration: 1,
    ));
    expect(
        search.status,
        anyOf(
            MetadataLookupStatus.ambiguous, MetadataLookupStatus.needsReview));
    expect(search.record, isNull,
        reason: 'Title search cannot silently publish a rating.');
    final exact =
        search.candidates.where((candidate) => candidate.titleMatched);
    expect(exact.length, 1,
        reason:
            'This public title must have one exact SNES identity for review.');
    final result = await provider.lookup(MetadataLookupRequest(
      gameId: 'live-proof-snes-smw',
      editionId: 'live-proof-snes-smw-official',
      platformId: 'snes',
      title: 'Super Mario World',
      verifiedProviderGameId: exact.single.providerGameId,
      contentTags: const {'official'},
      refreshGeneration: 1,
    ));
    expect(result.status, MetadataLookupStatus.matched);
    final record = result.record!;
    expect(record.providerId, 'screenscraper');
    expect(record.platformId, 'snes');
    expect(record.descriptions, isNotEmpty);
    expect(record.genres, isNotEmpty);
    expect(record.releaseDates, isNotEmpty);
    expect(record.developer?.isNotEmpty, isTrue);
    expect(record.publisher?.isNotEmpty, isTrue);
    expect(record.media, isNotEmpty);
    expect(record.ratings, isNotEmpty);
    expect(record.ratings.single.scaleMaximum, 20);
    expect(record.ratings.single.consensusValidated, isFalse);
    expect(result.quota?.maxThreads, greaterThan(0));
  },
      skip: developer.isConfigured && user.isConfigured
          ? false
          : 'Live ScreenScraper credentials are not configured.',
      timeout: Timeout.none);
}
