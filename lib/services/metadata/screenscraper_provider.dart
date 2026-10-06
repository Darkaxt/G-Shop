import 'dart:convert';
import '../../models/library_identity.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/scraped_metadata.dart';
import 'metadata_credentials.dart';
import 'metadata_provider.dart';

/// Standalone ScreenScraper API v2 access. API contract and system IDs were
/// checked against https://www.screenscraper.fr/webapi2.php on 2026-09-08.
/// Live acceptance still requires this fork's legitimate developer authorization.
class ScreenScraperProvider
    implements MetadataAccessProvider, MetadataArtworkProvider {
  final Dio _dio;
  final Future<ScreenScraperDeveloperCredentials?> Function() _readDeveloper;
  final Future<ScreenScraperUserCredentials?> Function() _readUser;
  final DateTime Function() _clock;
  static const maxResponseBytes = 4 * 1024 * 1024;
  static const imageTypes = {
    'box-2D',
    'box-3D',
    'box-texture',
    'wheel',
    'wheel-hd',
    'ss',
    'sstitle',
    'fanart',
    'marquee',
    'screenmarquee',
    'support-2D',
    'support-3D'
  };

  /// Explicit app-system mappings. DSi has no distinct verified mapping here;
  /// narrower variants (e.g. WonderSwan Color) need a specific assignment in S4.
  /// Unsupported systems are never inferred from filenames or provider parents.
  static const platformIds = <String, int>{
    'nes': 3,
    'snes': 4,
    'n64': 14,
    'gc': 13,
    'wii': 16,
    'wiiu': 18,
    'switch': 225,
    'gb': 9,
    'gbc': 10,
    'gba': 12,
    'nds': 15,
    'virtualboy': 11,
    'fds': 106,
    'n3ds': 17,
    'psx': 57,
    'ps2': 58,
    'ps3': 59,
    'psp': 61,
    'psvita': 62,
    'mastersystem': 2,
    'megadrive': 1,
    'gamegear': 21,
    'segacd': 20,
    'sega32x': 19,
    'dreamcast': 23,
    'saturn': 22,
    'sg1000': 109,
    'tg16': 31,
    'tgcd': 114,
    'ngp': 25,
    'neogeocd': 70,
    'wonderswan': 45,
    'colecovision': 48,
    'intellivision': 115,
    'vectrex': 102,
    'msx': 113,
    'amstradcpc': 65,
    'channelf': 80,
    'odyssey2': 104,
    'jaguar': 27,
    'atari2600': 26,
    'atari5200': 40,
    'atari7800': 41,
    'lynx': 28,
    'jaguarcd': 171,
    'atarist': 42,
    'pcfx': 72,
    'c64': 66,
    'vic20': 73,
    'amiga': 64,
    'zxspectrum': 76,
    'oric': 131,
    'x68000': 79,
    'x1': 220,
    'fmtowns': 253,
    'cdi': 133,
    '3do': 29,
    'appleii': 86,
    'ngage': 30,
    'arcadia2001': 94,
    'arcade': 75,
    'dos': 135,
    'gameandwatch': 52,
    'tic80': 222,
    'pico8': 234,
  };

  /// Inject only the transport, not a shared Dio with credential-logging
  /// interceptors. Requests use a fixed HTTPS origin and never follow redirects.
  ScreenScraperProvider({
    HttpClientAdapter? httpClientAdapter,
    required Future<ScreenScraperDeveloperCredentials?> Function()
        readDeveloperCredentials,
    required Future<ScreenScraperUserCredentials?> Function()
        readUserCredentials,
    DateTime Function()? clock,
  })  : _readDeveloper = readDeveloperCredentials,
        _readUser = readUserCredentials,
        _clock = clock ?? DateTime.now,
        _dio = Dio(BaseOptions(
            baseUrl: 'https://api.screenscraper.fr/api2/',
            followRedirects: false,
            responseType: ResponseType.stream,
            validateStatus: (_) => true)) {
    if (httpClientAdapter != null) {
      _dio.httpClientAdapter = httpClientAdapter;
    }
  }

  @override
  String get providerId => 'screenscraper';

  @override
  Future<MetadataLookupResult> fetchArtwork(MetadataMedia media,
      {required Future<void> Function(List<int>) write,
      CancelToken? cancelToken}) async {
    final reference = media.providerReference;
    if (reference == null ||
        !imageTypes.contains(reference.mediaType) ||
        !platformIds.values.contains(reference.providerPlatformId)) {
      return _result(MetadataLookupStatus.invalidRequest);
    }
    if (cancelToken?.isCancelled == true) {
      return _result(MetadataLookupStatus.cancelled);
    }
    try {
      final authentication = await _authenticatedQuery();
      if (cancelToken?.isCancelled == true) {
        return _result(MetadataLookupStatus.cancelled);
      }
      if (authentication == null) {
        return _result(MetadataLookupStatus.setupRequired);
      }
      final response = await _dio.get<ResponseBody>('mediaJeu.php',
          queryParameters: {
            ...authentication,
            'systemeid': reference.providerPlatformId,
            'jeuid': reference.providerGameId,
            'media': reference.mediaSelector,
            'outputformat': 'png',
            'maxwidth': 1024,
            'maxheight': 1024
          },
          cancelToken: cancelToken);
      if (response.statusCode != 200) {
        await response.data?.stream.listen((_) {}).cancel();
        return _httpFailure(
            response.statusCode ?? 0, response.headers.value('retry-after'));
      }
      final body = response.data;
      final length =
          int.tryParse(response.headers.value('content-length') ?? '');
      final mime =
          response.headers.value('content-type')?.split(';').first.trim();
      if (body == null ||
          (length != null && (length < 1 || length > maxResponseBytes))) {
        await body?.stream.listen((_) {}).cancel();
        return _result(MetadataLookupStatus.invalidResponse);
      }
      if (mime?.startsWith('text/') == true) {
        // The image endpoint documents a literal NOMEDIA response. Do not feed
        // text/challenge pages to the cache or keep an unbounded diagnostic body.
        final text = <int>[];
        await for (final chunk in body.stream) {
          if (cancelToken?.isCancelled == true) {
            return _result(MetadataLookupStatus.cancelled);
          }
          if (text.length + chunk.length > 32) {
            return _result(MetadataLookupStatus.invalidResponse);
          }
          text.addAll(chunk);
        }
        return _result(
            ascii.decode(text, allowInvalid: true).trim() == 'NOMEDIA'
                ? MetadataLookupStatus.unmatched
                : MetadataLookupStatus.invalidResponse);
      }
      if (mime != 'image/png') {
        await body.stream.listen((_) {}).cancel();
        return _result(MetadataLookupStatus.invalidResponse);
      }
      var received = 0;
      var tail = Uint8List(0);
      await for (final chunk in body.stream) {
        if (cancelToken?.isCancelled == true) {
          return _result(MetadataLookupStatus.cancelled);
        }
        received += chunk.length;
        if (received > maxResponseBytes) {
          return _result(MetadataLookupStatus.invalidResponse);
        }
        // Keep only the end-chunk framing across arbitrary transport chunks.
        // Live mediaJeu.php appends ASCII '1' after the complete IEND. Normalize
        // that exact endpoint response, not arbitrary data or whitespace.
        final combined = Uint8List.fromList([...tail, ...chunk]);
        final prefix = combined.length > 13 ? combined.length - 13 : 0;
        if (prefix > 0) await write(Uint8List.sublistView(combined, 0, prefix));
        tail = Uint8List.fromList(Uint8List.sublistView(combined, prefix));
      }
      if (cancelToken?.isCancelled == true) {
        return _result(MetadataLookupStatus.cancelled);
      }
      if (received == 0 || (length != null && received != length)) {
        return _result(MetadataLookupStatus.invalidResponse);
      }
      const endWithMarker = [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130, 49];
      final framed = tail.length == endWithMarker.length &&
          Iterable<int>.generate(tail.length)
              .every((i) => tail[i] == endWithMarker[i]);
      await write(framed ? Uint8List.sublistView(tail, 0, 12) : tail);
      return MetadataLookupResult(
          status: MetadataLookupStatus.matched,
          message: 'Image body received; cache validation is required.');
    } catch (error) {
      if (error is FileSystemException) {
        return _result(MetadataLookupStatus.unavailable);
      }
      return _safeFailure(error, cancelToken);
    }
  }

  @override
  MetadataProviderCapabilities get capabilities =>
      const MetadataProviderCapabilities(
        fields: {
          'title',
          'description',
          'genres',
          'releaseDate',
          'developer',
          'publisher',
          'artwork',
          'screenshots',
          'rating'
        },
        verifiedIdLookup: true,
        rawRomLookup: true,
        titleSearch: true,
        documentedVoteCounts: false,
      );

  @override
  Future<MetadataLookupResult> checkAccess({CancelToken? cancelToken}) async {
    if (cancelToken?.isCancelled == true) {
      return _result(MetadataLookupStatus.cancelled);
    }
    try {
      final query = await _authenticatedQuery();
      if (cancelToken?.isCancelled == true) {
        return _result(MetadataLookupStatus.cancelled);
      }
      if (query == null) return _result(MetadataLookupStatus.setupRequired);
      final response = await _readApi('ssuserInfos.php', query, cancelToken);
      if (response.$2 != null) return response.$2!;
      final account = _map(response.$1!['ssuser']);
      final quota = _quota(account);
      if (_text(account?['id'])?.toLowerCase() !=
              (query['ssid'] as String).toLowerCase() ||
          quota?.maxThreads == null ||
          quota?.maxRequestsPerMinute == null ||
          quota?.requestsToday == null ||
          quota?.maxRequestsPerDay == null ||
          quota?.unmatchedToday == null ||
          quota?.maxUnmatchedPerDay == null) {
        return _result(MetadataLookupStatus.invalidResponse);
      }
      return MetadataLookupResult(
          status: MetadataLookupStatus.matched,
          quota: quota,
          message: 'Provider access checked; no game lookup performed.');
    } catch (error) {
      return _safeFailure(error, cancelToken);
    }
  }

  @override
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
      {CancelToken? cancelToken}) async {
    if (cancelToken?.isCancelled == true) {
      return _result(MetadataLookupStatus.cancelled);
    }
    final platform = platformIds[request.platformId];
    if (platform == null) {
      return _result(MetadataLookupStatus.unsupportedPlatform);
    }
    if (request.gameId.isEmpty ||
        request.editionId.isEmpty ||
        request.refreshGeneration < 0 ||
        request.title.trim().isEmpty ||
        (request.verifiedProviderGameId != null &&
            !_positiveId(request.verifiedProviderGameId))) {
      return _result(MetadataLookupStatus.invalidRequest);
    }
    final identifier = request.romIdentifier;
    final raw = identifier != null &&
            identifier.kind != RomIdentifierKind.container &&
            !_containerFilename(identifier.filename)
        ? identifier
        : null;
    if (raw != null && !_validIdentifier(raw)) {
      return _result(MetadataLookupStatus.invalidRequest);
    }

    try {
      final authentication = await _authenticatedQuery();
      if (cancelToken?.isCancelled == true) {
        return _result(MetadataLookupStatus.cancelled);
      }
      if (authentication == null) {
        return _result(MetadataLookupStatus.setupRequired);
      }
      // gameid lookups omit ROM information. Supplied raw evidence must still
      // identify the exact release, then agree with any reviewed game identity.
      final byId = request.verifiedProviderGameId != null && raw == null;
      final query = <String, dynamic>{
        ...authentication,
        'systemeid': '$platform',
        if (byId) 'gameid': request.verifiedProviderGameId,
        if (!byId && raw != null) ...{
          'romtype': raw.kind == RomIdentifierKind.rawIso ? 'iso' : 'rom',
          'romnom': raw.filename,
          'romtaille': '${raw.sizeBytes}',
          if (raw.crc32 != null) 'crc': raw.crc32!.toUpperCase(),
          if (raw.md5 != null) 'md5': raw.md5!.toLowerCase(),
          if (raw.sha1 != null) 'sha1': raw.sha1!.toLowerCase(),
        },
        if (!byId && raw == null) 'recherche': request.title,
      };
      final response = await _readApi(
          byId || raw != null ? 'jeuInfos.php' : 'jeuRecherche.php',
          query,
          cancelToken);
      if (response.$2 != null) return response.$2!;
      final data = response.$1!;
      final quota = _quota(_map(data['ssuser']));
      final List<Map<String, dynamic>> games;
      if (byId || raw != null) {
        final game = _map(data['jeu']);
        if (game == null) {
          return _result(MetadataLookupStatus.invalidResponse, quota: quota);
        }
        games = [game];
      } else {
        if (data['jeux'] is! List || (data['jeux'] as List).length > 30) {
          return _result(MetadataLookupStatus.invalidResponse, quota: quota);
        }
        games = _maps(data['jeux']);
      }
      final candidates = <MetadataLookupCandidate>[];
      final eligibleTitles = <int>[];
      final matchedGames = <Map<String, dynamic>>[];
      Map<String, dynamic>? matched;
      for (final game in games) {
        final id = _text(game['id']);
        if (!_positiveId(id) ||
            _text(_map(game['systeme'])?['id']) != '$platform') {
          continue;
        }
        if (request.verifiedProviderGameId != null &&
            id != request.verifiedProviderGameId) {
          continue;
        }
        final rawEvidence = raw == null ? null : _identifierEvidence(game, raw);
        if (!byId && raw != null && rawEvidence == null) {
          continue;
        }
        if (!_compatibleRelease(game, request)) {
          continue;
        }
        final titles = _localized(game['noms'], dimension: 'region');
        if (titles.isEmpty && _text(game['nom']) != null) {
          titles.add(MetadataText(text: _text(game['nom'])!));
        }
        if (titles.isEmpty) {
          continue;
        }
        final titleMatched = titles.any((title) =>
            normalizeMetadataTitle(title.text).isNotEmpty &&
            normalizeMetadataTitle(title.text) ==
                normalizeMetadataTitle(request.title));
        final titleQualified = !byId &&
            raw == null &&
            (data['jeux'] as List).length < 30 &&
            request.region != null &&
            titleMatched &&
            request.contentTags.length == 1 &&
            request.contentTags.contains('official') &&
            request.baseProviderGameId == null &&
            request.revision?.isNotEmpty != true &&
            // Search omits raw-classification fields. Existing official tags
            // are required above; an explicit conflicting non-game still vetoes.
            (game['notgame'] == null || _text(game['notgame']) == 'false') &&
            titles.any((title) =>
                normalizeMetadataTitle(title.text) ==
                    normalizeMetadataTitle(request.title) &&
                {_region(request.region!), 'wor'}
                    .contains(_region(title.region ?? ''))) &&
            selectEditionReleaseDate(
                    _localized(game['dates'], dimension: 'region')
                        .where((date) =>
                            _region(date.region ?? '') ==
                            _region(request.region!))
                        .toList(),
                    regions: [_region(request.region!)]) !=
                null &&
            !['hack', 'trad', 'demo', 'unl', 'beta']
                .any((key) => _text(_rom(game)?[key]) == '1');
        if (titleQualified) eligibleTitles.add(candidates.length);
        matchedGames.add(game);
        candidates.add(MetadataLookupCandidate(
            providerGameId: id!,
            platformId: request.platformId,
            titles: titles,
            titleMatched: titleMatched,
            previewDescriptions: _localized(
                game['synopses'] ?? game['synopsis'],
                dimension: 'langue'),
            previewMedia: _mediaEntries(game['medias'])
                .map((entry) => _mediaEntry(entry,
                    providerGameId: id, providerPlatformId: platform))
                .whereType<MetadataMedia>()
                .where((media) =>
                    media.providerReference != null &&
                    {'box-2D', 'box-3D', 'cover'}.contains(media.type))
                .firstOrNull,
            evidence: byId
                ? 'verifiedProviderId'
                : raw != null
                    ? rawEvidence!
                    : titleQualified
                        ? 'exactRegionalOfficialTitle'
                        : titleMatched
                            ? 'platformAndTitle'
                            : 'providerTitleCandidate'));
        matched = game;
      }
      if (candidates.isEmpty) {
        return _result(MetadataLookupStatus.unmatched, quota: quota);
      }
      if (eligibleTitles.length == 1) {
        final selected = eligibleTitles.single;
        matched = matchedGames[selected];
        final candidate = candidates[selected];
        candidates
          ..clear()
          ..add(candidate);
      }
      if (candidates.length > 1) {
        return _result(MetadataLookupStatus.ambiguous,
            candidates: candidates, quota: quota);
      }
      // An API note belongs to the game. A ROM's hack/trad flag cannot turn that
      // game score into a rating of a patch. S4 owns project-level corrections.
      final official = request.contentTags.length == 1 &&
          request.contentTags.single.toLowerCase() == 'official';
      final rom = _rom(matched!);
      const flags = ['hack', 'trad', 'demo', 'unl', 'beta'];
      final inferOfficial = raw != null &&
          [raw.md5, raw.sha1]
              .any((hash) => hash != null && !RegExp(r'^0+$').hasMatch(hash)) &&
          (request.contentTags.isEmpty ||
              (request.contentTags.length == 1 &&
                  request.contentTags.single == 'unknown')) &&
          _text(matched['notgame']) == 'false' &&
          flags.every((key) => _text(rom?[key]) == '0');
      final modifiedRom = ['hack', 'trad', 'demo', 'unl', 'beta']
          .any((key) => _text(rom?[key]) == '1');
      if ((!byId &&
              raw == null &&
              candidates.single.evidence != 'exactRegionalOfficialTitle') ||
          (!official && !inferOfficial) ||
          modifiedRom ||
          request.baseProviderGameId != null ||
          (request.revision?.isNotEmpty == true && raw == null) ||
          _text(matched['notgame']) == 'true') {
        return _result(MetadataLookupStatus.needsReview,
            candidates: candidates, quota: quota);
      }
      List<String> codes(String key) => (_text(rom?[key]) ?? '')
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .where((value) => RegExp(r'^[a-z]{2,3}$').hasMatch(value))
          .toSet()
          .take(16)
          .toList()
        ..sort();
      final regions = codes('romregions');
      final languages = codes('romlangues');
      final effectiveRequest =
          inferOfficial && request.region == null && regions.length == 1
              ? MetadataLookupRequest.fromJson(
                  {...request.toJson(), 'region': regions.single})
              : request;
      final record = _record(matched, effectiveRequest, candidates.single);
      return MetadataLookupResult(
          status: MetadataLookupStatus.matched,
          record: record,
          candidates: candidates,
          quota: quota,
          officialRomEvidence: !inferOfficial
              ? null
              : IdentityEvidence(
                  source: providerId,
                  kind: 'exactRomOfficialRelease',
                  value: jsonEncode({
                    'providerGameId': record.providerGameId,
                    'identifier': raw.toJson(),
                    'flags': {for (final key in flags) key: '0'},
                    'notgame': false,
                    'regions': regions,
                    'languages': languages,
                    'retrievedAt': record.retrievedAt.toUtc().toIso8601String(),
                  })),
          message: candidates.single.evidence == 'rawRomSha1AndCappedSize'
              ? 'Metadata matched by original ISO SHA-1; provider size is capped. '
                  'This is not file-integrity verification; rating confidence is unassessed.'
              : 'Metadata matched; rating confidence is unassessed.');
    } catch (error) {
      return _safeFailure(error, cancelToken);
    }
  }

  Future<Map<String, dynamic>?> _authenticatedQuery() async {
    final developer = await _readDeveloper();
    final user = await _readUser();
    if (developer?.isConfigured != true || user?.isConfigured != true) {
      return null;
    }
    return {
      'devid': developer!.developerId,
      'devpassword': developer.developerPassword,
      'softname': developer.softwareName,
      'ssid': user!.username,
      'sspassword': user.password,
      'output': 'json',
    };
  }

  Future<(Map<String, dynamic>?, MetadataLookupResult?)> _readApi(
      String endpoint, Map<String, dynamic> query, CancelToken? cancel) async {
    final response = await _dio.get<ResponseBody>(endpoint,
        queryParameters: query, cancelToken: cancel);
    final status = response.statusCode ?? 0;
    if (status != 200) {
      await response.data?.stream.listen((_) {}).cancel();
      return (
        null,
        _httpFailure(status, response.headers.value('retry-after'))
      );
    }
    final body = response.data;
    if (body == null) {
      return (null, _result(MetadataLookupStatus.invalidResponse));
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        return (null, _result(MetadataLookupStatus.invalidResponse));
      }
      bytes.add(chunk);
    }
    if (cancel?.isCancelled == true) {
      return (null, _result(MetadataLookupStatus.cancelled));
    }
    final data =
        _map(_map(jsonDecode(utf8.decode(bytes.takeBytes())))?['response']);
    return data == null
        ? (null, _result(MetadataLookupStatus.invalidResponse))
        : (data, null);
  }

  static MetadataLookupResult _safeFailure(Object error, CancelToken? cancel) {
    if (cancel?.isCancelled == true ||
        (error is DioException && error.type == DioExceptionType.cancel)) {
      return _result(MetadataLookupStatus.cancelled);
    }
    if (error is MetadataCredentialStorageException) {
      return _result(MetadataLookupStatus.setupRequired);
    }
    // No raw plugin, transport or parser diagnostics containing secrets escape.
    return _result(error is DioException
        ? MetadataLookupStatus.unavailable
        : MetadataLookupStatus.invalidResponse);
  }

  MetadataRecord _record(Map<String, dynamic> game,
      MetadataLookupRequest request, MetadataLookupCandidate candidate) {
    final fetched = _clock().toUtc();
    final descriptions =
        _localized(game['synopses'] ?? game['synopsis'], dimension: 'langue');
    final releaseDates = _localized(game['dates'], dimension: 'region');
    final developer = _text(game['developpeur']);
    final publisher = _text(game['editeur']);
    final genres = _maps(game['genres'])
        .map((genre) => MetadataGenre(
            providerGenreId: _text(genre['id']) ?? '',
            names: _localized(genre['noms'], dimension: 'langue')))
        .where((genre) =>
            genre.providerGenreId.isNotEmpty && genre.names.isNotEmpty)
        .toList();
    var media = _mediaEntries(game['medias'])
        .map((entry) => _mediaEntry(entry,
            providerGameId: candidate.providerGameId,
            providerPlatformId: platformIds[request.platformId]!))
        .whereType<MetadataMedia>()
        .toList();
    if (request.region != null) {
      const covers = {'box-2D', 'box-3D', 'cover'};
      final wanted = _region(request.region!);
      final exact = media
          .where((m) =>
              covers.contains(m.type) &&
              m.region != null &&
              _region(m.region!) == wanted)
          .toList();
      final neutral = media
          .where((m) =>
              covers.contains(m.type) &&
              (m.region == null ||
                  m.region!.trim().isEmpty ||
                  _region(m.region!) == 'wor'))
          .toList();
      final selected = exact.isNotEmpty ? exact : neutral;
      // Snapshot artwork for this reviewed release. The API's list order is
      // not a regional preference; a foreign cover must not impersonate it.
      media = media
          .where((m) => !covers.contains(m.type) || selected.contains(m))
          .toList();
    }
    final score = SourcedRating.parse(
        sourceId: providerId,
        sourceLabel: 'ScreenScraper',
        providerGameId: candidate.providerGameId,
        rawValue: _text(game['note']),
        scaleMinimum: 0,
        scaleMaximum: 20,
        kind: RatingKind.unknownAggregate,
        retrievedAt: fetched);
    final fields = <String>{
      'title',
      if (descriptions.isNotEmpty) 'description',
      if (releaseDates.isNotEmpty) 'releaseDate',
      if (developer != null) 'developer',
      if (publisher != null) 'publisher',
      if (genres.isNotEmpty) 'genres',
      if (media.isNotEmpty) 'media',
      if (score != null) 'rating'
    };
    return MetadataRecord(
        gameId: request.gameId,
        editionId: request.editionId,
        platformId: request.platformId,
        providerId: providerId,
        providerGameId: candidate.providerGameId,
        retrievedAt: fetched,
        refreshGeneration: request.refreshGeneration,
        matchMethod: candidate.evidence,
        matchEvidence: candidate.evidence == 'exactRegionalOfficialTitle'
            ? {
                'matchingPolicy': 'regionalReleaseV1',
                'title': request.title,
                'region': _region(request.region!)
              }
            : const {},
        titles: candidate.titles,
        descriptions: descriptions,
        releaseDates: releaseDates,
        developer: developer,
        publisher: publisher,
        genres: genres,
        media: media,
        ratings: score == null ? [] : [score],
        fieldProvenance: {
          for (final field in fields)
            field: MetadataFieldProvenance(
                providerId: providerId,
                providerGameId: candidate.providerGameId,
                field: field,
                retrievedAt: fetched)
        });
  }

  MetadataLookupResult _httpFailure(int status, String? retryAfter) => _result(
      switch (status) {
        400 => MetadataLookupStatus.invalidRequest,
        401 => MetadataLookupStatus.authenticationRequired,
        403 || 426 => MetadataLookupStatus.developerAccessRequired,
        404 => MetadataLookupStatus.unmatched,
        429 => MetadataLookupStatus.throttled,
        430 || 431 => MetadataLookupStatus.quotaExceeded,
        _ => MetadataLookupStatus.unavailable,
      },
      retryAfter: status == 429 ? _retryAfter(retryAfter) : null);

  Duration? _retryAfter(String? value) {
    final seconds = int.tryParse(value ?? '');
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }
    if (value != null) {
      try {
        final remaining = HttpDate.parse(value).difference(_clock().toUtc());
        return remaining.isNegative ? Duration.zero : remaining;
      } on HttpException {
        return null;
      }
    }
    return null;
  }

  static MetadataLookupResult _result(MetadataLookupStatus status,
          {List<MetadataLookupCandidate> candidates = const [],
          MetadataQuota? quota,
          Duration? retryAfter}) =>
      MetadataLookupResult(
          status: status,
          candidates: candidates,
          quota: quota,
          retryAfter: retryAfter,
          message: switch (status) {
            MetadataLookupStatus.setupRequired =>
              'Configure ScreenScraper developer authorization and user access.',
            MetadataLookupStatus.authenticationRequired =>
              'ScreenScraper account access is required.',
            MetadataLookupStatus.developerAccessRequired =>
              'ScreenScraper application authorization requires attention.',
            MetadataLookupStatus.quotaExceeded =>
              'ScreenScraper quota is exhausted. Resume when provider access resets.',
            MetadataLookupStatus.throttled =>
              'ScreenScraper requests are throttled. Respect the provider delay.',
            MetadataLookupStatus.unsupportedPlatform =>
              'This platform has no verified ScreenScraper mapping.',
            MetadataLookupStatus.invalidRequest =>
              'The metadata identification request is incomplete or invalid.',
            MetadataLookupStatus.invalidResponse =>
              'ScreenScraper returned an invalid or oversized metadata response.',
            MetadataLookupStatus.unavailable =>
              'ScreenScraper is unavailable. Metadata can be retried later.',
            MetadataLookupStatus.cancelled => 'Metadata lookup cancelled.',
            MetadataLookupStatus.ambiguous =>
              'Several candidates require identity review.',
            MetadataLookupStatus.needsReview =>
              'Verify game and edition ownership before publishing this metadata.',
            MetadataLookupStatus.unmatched =>
              'No candidate satisfies the platform and identity evidence.',
            MetadataLookupStatus.matched => 'Metadata matched.',
          });

  static bool _positiveId(String? id) =>
      id != null && RegExp(r'^[1-9][0-9]*$').hasMatch(id);

  static bool _containerFilename(String name) =>
      RegExp(r'\.(zip|7z|rar|chd|rvz|wua|cso|zso|pbp|nsz|xcz)$',
              caseSensitive: false)
          .hasMatch(name);

  static bool _validIdentifier(MetadataRomIdentifier identifier) {
    if (identifier.sizeBytes <= 0 ||
        identifier.filename.isEmpty ||
        identifier.filename.contains(RegExp(r'[/\\:\x00]'))) {
      return false;
    }
    final values = {
      8: identifier.crc32,
      32: identifier.md5,
      40: identifier.sha1
    };
    return values.values.any((value) => value != null) &&
        values.entries.every((entry) =>
            entry.value == null ||
            RegExp('^[0-9a-fA-F]{${entry.key}}\$').hasMatch(entry.value!));
  }

  static String? _identifierEvidence(
      Map<String, dynamic> game, MetadataRomIdentifier identifier) {
    final rom = _rom(game);
    if (rom == null) return null;
    final hashesMatch = {
      'romcrc': identifier.crc32,
      'rommd5': identifier.md5,
      'romsha1': identifier.sha1
    }.entries.every((entry) =>
        entry.value == null ||
        _text(rom[entry.key])?.toLowerCase() == entry.value!.toLowerCase());
    if (!hashesMatch) return null;
    final size = _nonnegativeInt(rom['romsize']);
    if (size == identifier.sizeBytes) return 'rawRomHashAndSize';
    // Live API v2 observations for large original DVDs return INT32_MAX even
    // with the exact original SHA-1. Preserve the actual requested size and
    // report this limitation distinctly; never relax transport verification.
    const cappedSize = 0x7fffffff;
    if (identifier.kind == RomIdentifierKind.rawIso &&
        identifier.sizeBytes > cappedSize &&
        size == cappedSize &&
        identifier.sha1 != null &&
        !RegExp(r'^0+$').hasMatch(identifier.sha1!)) {
      return 'rawRomSha1AndCappedSize';
    }
    return null;
  }

  static bool _compatibleRelease(
      Map<String, dynamic> game, MetadataLookupRequest request) {
    final rom = _rom(game);
    if (request.region != null) {
      final romRegions = _text(rom?['romregions']);
      final regions = romRegions
              ?.split(',')
              .map((region) => _region(region.trim()))
              .toSet() ??
          _localized(game['dates'], dimension: 'region')
              .map((value) => _region(value.region ?? ''))
              .toSet();
      if (!regions.contains(_region(request.region!))) {
        return false;
      }
    }
    if (request.language != null) {
      final languages = _text(rom?['romlangues'])
          ?.split(',')
          .map((value) => value.trim().toLowerCase());
      if (languages?.contains(request.language!.toLowerCase()) != true) {
        return false;
      }
    }
    return true;
  }

  static String _region(String value) => switch (value.toLowerCase()) {
        'usa' => 'us',
        'japan' || 'japon' => 'jp',
        'europe' => 'eu',
        'world' => 'wor',
        'france' => 'fr',
        _ => value.toLowerCase(),
      };

  static MetadataMedia? _mediaEntry(Map<String, dynamic> entry,
      {required String providerGameId, required int providerPlatformId}) {
    final url = _text(entry['url']);
    final type = _text(entry['type']);
    if (url == null || type == null) {
      return null;
    }
    final region = _text(entry['region']);
    final memberIndex = entry['memberIndex'] as int?;
    final reference = _mediaReference(url,
        providerGameId: providerGameId,
        providerPlatformId: providerPlatformId,
        expectedType: type,
        expectedRegion: region,
        expectedMemberIndex: memberIndex);
    if (reference != null) {
      return MetadataMedia(
          type: reference.mediaType,
          region: reference.region,
          memberIndex: reference.memberIndex,
          providerReference: reference);
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !MetadataMedia.isSafeDirectUrl(url) ||
        !(uri.host == 'screenscraper.fr' ||
            uri.host.endsWith('.screenscraper.fr'))) {
      return null;
    }
    return MetadataMedia(
        type: type, url: url, region: region, memberIndex: memberIndex);
  }

  static ScreenScraperMediaReference? _mediaReference(String url,
      {required String providerGameId,
      required int providerPlatformId,
      required String expectedType,
      String? expectedRegion,
      int? expectedMemberIndex}) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        // Live API v2 metadata also uses this provider-owned media shard.
        // Parse identifiers only; neither hostname nor credential-bearing URL
        // is persisted or used as an arbitrary download destination.
        !const {'api.screenscraper.fr', 'neoclone.screenscraper.fr'}
            .contains(uri.host) ||
        uri.port != 443 ||
        uri.path != '/api2/mediaJeu.php' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    final parameters = uri.queryParametersAll;
    const documentedKeys = {
      'devid',
      'devpassword',
      'softname',
      'ssid',
      'sspassword',
      'crc',
      'md5',
      'sha1',
      'systemeid',
      'jeuid',
      'media',
      'mediaformat',
      'maxwidth',
      'maxheight',
      'outputformat'
    };
    if (parameters.keys.any((key) => !documentedKeys.contains(key)) ||
        parameters.values.any((values) => values.length != 1)) {
      return null;
    }
    final game = parameters['jeuid']?.single;
    final platform = parameters['systemeid']?.single;
    final selector = parameters['media']?.single;
    if (game != providerGameId ||
        platform != '$providerPlatformId' ||
        selector == null) {
      return null;
    }
    final match = RegExp(
            r'^([a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*)(?:\(([a-z]{2,3})([1-9][0-9]*)?\))?$')
        .firstMatch(selector);
    if (match == null ||
        match.group(1) != expectedType ||
        (expectedRegion != null && match.group(2) != expectedRegion)) {
      return null;
    }
    final memberIndex =
        match.group(3) == null ? null : int.tryParse(match.group(3)!);
    if ((match.group(3) != null && memberIndex == null) ||
        (expectedMemberIndex != null && memberIndex != expectedMemberIndex)) {
      return null;
    }
    // Copy only identifiers. Original URL, developer/account values, checksum
    // query fields and presentation options never enter the metadata record.
    return ScreenScraperMediaReference(
        providerGameId: providerGameId,
        providerPlatformId: providerPlatformId,
        mediaType: match.group(1)!,
        region: match.group(2),
        memberIndex: memberIndex);
  }

  /// API v2 documents both individual fields and grouped media objects at
  /// webapi2.php (medias, media_wheels, media_boitiers, media_supports, etc.).
  /// Traverse only those named groups; unrelated objects are not URL sources.
  static Iterable<Map<String, dynamic>> _mediaEntries(Object? value) sync* {
    if (value is List) {
      yield* _maps(value);
      return;
    }
    final media = _map(value);
    if (media == null) {
      return;
    }
    const singles = {
      'media_screenshot': 'ss',
      'media_fanart': 'fanart',
      'media_video': 'video',
      'media_marquee': 'marquee',
      'media_screenmarquee': 'screenmarquee'
    };
    for (final field in singles.entries) {
      final url = _text(media[field.key]);
      if (url != null) {
        yield {'type': field.value, 'url': url};
      }
    }
    const groups = [
      (path: 'media_wheels', prefix: 'media_wheel_', type: 'wheel'),
      (
        path: 'media_wheelscarbon',
        prefix: 'media_wheelcarbon_',
        type: 'wheel-carbon'
      ),
      (
        path: 'media_wheelssteel',
        prefix: 'media_wheelsteel_',
        type: 'wheel-steel'
      ),
      (
        path: 'media_boitiers.media_boitiers_texture',
        prefix: 'media_boitier_texture_',
        type: 'box-texture'
      ),
      (
        path: 'media_boitiers.media_boitiers_2d',
        prefix: 'media_boitier_2d_',
        type: 'box-2D'
      ),
      (
        path: 'media_boitiers.media_boitiers_3d',
        prefix: 'media_boitier_3d_',
        type: 'box-3D'
      ),
      (
        path: 'media_supports.media_supports_texture',
        prefix: 'media_support_texture_',
        type: 'support-texture'
      ),
      (
        path: 'media_supports.media_supports_2d',
        prefix: 'media_support_2d_',
        type: 'support-2D'
      ),
      (path: 'media_flyer', prefix: 'media_flyer_', type: 'flyer'),
      (
        path: 'media_bezels.media_bezel4-3',
        prefix: 'media_bezel4-3_',
        type: 'bezel4-3'
      ),
      (
        path: 'media_bezels.media_bezel16-9',
        prefix: 'media_bezel16-9_',
        type: 'bezel16-9'
      ),
      (
        path: 'media_bezels.media_bezel16-10',
        prefix: 'media_bezel16-10_',
        type: 'bezel16-10'
      ),
    ];
    for (final group in groups) {
      Map<String, dynamic>? nested = media;
      for (final key in group.path.split('.')) {
        nested = _map(nested?[key]);
      }
      if (nested == null) {
        continue;
      }
      for (final entry in nested.entries) {
        if (!entry.key.startsWith(group.prefix)) {
          continue;
        }
        final regionAndMember = RegExp(r'^([a-z]{2,3})([1-9][0-9]*)?$')
            .firstMatch(entry.key.substring(group.prefix.length));
        final url = _text(entry.value);
        if (url == null || regionAndMember == null) {
          continue;
        }
        final memberIndex = regionAndMember.group(2) == null
            ? null
            : int.tryParse(regionAndMember.group(2)!);
        if (regionAndMember.group(2) != null && memberIndex == null) {
          continue;
        }
        yield {
          'type': group.type,
          'region': regionAndMember.group(1),
          if (memberIndex != null) 'memberIndex': memberIndex,
          'url': url
        };
      }
    }
  }

  static MetadataQuota? _quota(Map<String, dynamic>? data) => data == null
      ? null
      : MetadataQuota(
          maxThreads: _nonnegativeInt(data['maxthreads']),
          requestsToday: _nonnegativeInt(data['requeststoday']),
          maxRequestsPerDay: _nonnegativeInt(data['maxrequestsperday']),
          maxRequestsPerMinute: _nonnegativeInt(
              data['maxrequestsperdmin'] ?? data['maxrequestspermin']),
          unmatchedToday: _nonnegativeInt(data['requestskotoday']),
          maxUnmatchedPerDay: _nonnegativeInt(data['maxrequestskoperday']));

  static int? _nonnegativeInt(Object? value) {
    final parsed = int.tryParse(_text(value) ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map<String, dynamic> ? value : null;
  static List<Map<String, dynamic>> _maps(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>().toList() : [];
  static String? _text(Object? value) {
    if (value is Map<String, dynamic>) {
      return _text(value['text']);
    }
    if (value is! String && value is! num && value is! bool) {
      return null;
    }
    final text = value.toString();
    return text.trim().isEmpty ? null : text;
  }

  static Map<String, dynamic>? _rom(Map<String, dynamic> game) {
    final rom = _map(game['rom']);
    if (rom == null) {
      return null;
    }
    if (rom.containsKey('romsize') || rom.containsKey('romfilename')) {
      return rom;
    }
    final children = rom.values.whereType<Map<String, dynamic>>().toList();
    return children.length == 1 ? children.single : null;
  }

  static List<MetadataText> _localized(Object? value,
      {required String dimension}) {
    if (value is List) {
      return _maps(value)
          .where((entry) => _text(entry['text']) != null)
          .map((entry) => MetadataText(
              text: _text(entry['text'])!,
              region: dimension == 'region' ? _text(entry['region']) : null,
              language: dimension == 'langue' ? _text(entry['langue']) : null))
          .toList();
    }
    if (value is Map<String, dynamic>) {
      return value.entries
          .where((entry) => _text(entry.value) != null)
          .map((entry) {
        final locale = entry.key.split('_').last;
        return MetadataText(
            text: _text(entry.value)!,
            region: dimension == 'region' ? locale : null,
            language: dimension == 'langue' ? locale : null);
      }).toList();
    }
    return [];
  }

  @override
  void close() => _dio.close();
}
