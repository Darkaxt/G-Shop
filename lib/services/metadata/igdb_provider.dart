import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/scraped_metadata.dart';
import '../romm_platform_matcher.dart';
import 'metadata_credentials.dart';
import 'metadata_provider.dart';
export 'metadata_credentials.dart' show IgdbCredentials;

/// Legitimate IGDB v4 source for the externally defined overall score and its
/// separate critic/community support. Receiving scores does not approve META-05.
/// API contract: https://api-docs.igdb.com/ (checked 2026-10-03).
class IgdbMetadataProvider implements MetadataProvider {
  final Dio _dio;
  final Future<IgdbCredentials?> Function() _readCredentials;
  final DateTime Function() _clock;
  String? _token;
  DateTime? _expiresAt;
  IgdbCredentials? _tokenOwner;
  static const maxResponseBytes = 4 * 1024 * 1024;
  static const _fields =
      'id,name,alternative_names.name,platforms,game_type.type,'
      'version_parent,parent_game,summary,first_release_date,'
      'rating,rating_count,aggregated_rating,aggregated_rating_count,'
      'total_rating,total_rating_count';
  static const _corroborationFields =
      'release_dates.platform,release_dates.date,release_dates.date_format.format,'
      'release_dates.release_region.region,involved_companies.company.name,'
      'involved_companies.developer,involved_companies.publisher';
  static const _quota = MetadataQuota(maxThreads: 1, maxRequestsPerMinute: 240);

  IgdbMetadataProvider({
    HttpClientAdapter? httpClientAdapter,
    required Future<IgdbCredentials?> Function() readCredentials,
    DateTime Function()? clock,
  })  : _readCredentials = readCredentials,
        _clock = clock ?? DateTime.now,
        _dio = Dio(BaseOptions(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (_) => true)) {
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;
  }

  @override
  String get providerId => 'igdb';
  @override
  MetadataProviderCapabilities get capabilities =>
      const MetadataProviderCapabilities(
          fields: {'title', 'description', 'releaseDate', 'rating'},
          verifiedIdLookup: true,
          rawRomLookup: false,
          titleSearch: true,
          documentedVoteCounts: true);

  @override
  Future<MetadataLookupResult> lookup(MetadataLookupRequest request,
      {CancelToken? cancelToken}) async {
    if (cancelToken?.isCancelled == true) {
      return _result(MetadataLookupStatus.cancelled);
    }
    final platform = RommPlatformMatcher.igdbPlatformIdFor(request.platformId);
    if (platform == null) {
      return _result(MetadataLookupStatus.unsupportedPlatform);
    }
    final id = request.verifiedProviderGameId;
    if (request.gameId.isEmpty ||
        request.editionId.isEmpty ||
        request.refreshGeneration < 0 ||
        request.title.trim().isEmpty ||
        request.title.length > 512 ||
        (id != null && !RegExp(r'^[1-9][0-9]*$').hasMatch(id))) {
      return _result(MetadataLookupStatus.invalidRequest);
    }
    try {
      final credentials = await _readCredentials();
      if (cancelToken?.isCancelled == true) {
        return _result(MetadataLookupStatus.cancelled);
      }
      if (credentials?.isConfigured != true) {
        _clearToken();
        return _result(MetadataLookupStatus.setupRequired);
      }
      if (_tokenOwner?.clientId != credentials!.clientId ||
          _tokenOwner?.clientSecret != credentials.clientSecret ||
          _expiresAt == null ||
          !_clock().isBefore(_expiresAt!)) {
        _clearToken();
        final authentication = await _post(
            'https://id.twitch.tv/oauth2/token',
            {
              'client_id': credentials.clientId,
              'client_secret': credentials.clientSecret,
              'grant_type': 'client_credentials'
            },
            Options(contentType: Headers.formUrlEncodedContentType),
            cancelToken);
        if (authentication.failure != null) return authentication.failure!;
        final value = authentication.data;
        if (value is! Map<String, dynamic> ||
            value['access_token'] is! String ||
            (value['access_token'] as String).isEmpty ||
            value['expires_in'] is! int ||
            (value['expires_in'] as int) <= 0 ||
            value['token_type'] != 'bearer') {
          return _result(MetadataLookupStatus.invalidResponse);
        }
        _token = value['access_token'] as String;
        _expiresAt =
            _clock().add(Duration(seconds: value['expires_in'] as int));
        _tokenOwner = credentials;
      }
      final query =
          'fields $_fields${request.corroboration == null ? '' : ',$_corroborationFields'}; '
          '${id == null ? 'search ${jsonEncode(request.title)}; where platforms = ($platform);' : 'where id = $id;'} limit 30;';
      final response = await _post(
          'https://api.igdb.com/v4/games',
          query,
          Options(contentType: 'text/plain', headers: {
            'Client-ID': credentials.clientId,
            'Authorization': 'Bearer $_token'
          }),
          cancelToken);
      if (response.failure != null) return response.failure!;
      final data = response.data;
      if (data is! List ||
          data.length > 30 ||
          data.any((r) => r is! Map<String, dynamic>)) {
        return _result(MetadataLookupStatus.invalidResponse);
      }
      final games = <Map<String, dynamic>>[];
      final candidates = <MetadataLookupCandidate>[];
      for (final game in data.cast<Map<String, dynamic>>()) {
        if (game['id'] is! int ||
            (game['id'] as int) < 1 ||
            game['name'] is! String ||
            (game['name'] as String).isEmpty ||
            game['platforms'] is! List ||
            !(game['platforms'] as List).contains(platform) ||
            (id != null && '${game['id']}' != id)) {
          continue;
        }
        final titles = <MetadataText>[
          MetadataText(text: game['name'] as String)
        ];
        final alternatives = game['alternative_names'];
        if (alternatives is List && alternatives.length <= 128) {
          for (final alternative in alternatives) {
            if (alternative is Map && alternative['name'] is String) {
              titles.add(MetadataText(text: alternative['name'] as String));
            }
          }
        }
        candidates.add(MetadataLookupCandidate(
            providerGameId: '${game['id']}',
            platformId: request.platformId,
            titles: titles,
            previewDescriptions: game['summary'] is String
                ? [MetadataText(text: game['summary'] as String)]
                : const [],
            titleMatched: titles
                .any((t) => _normalize(t.text) == _normalize(request.title)),
            evidence: id == null ? 'platformAndTitle' : 'verifiedProviderId'));
        games.add(game);
      }
      if (games.isEmpty) return _result(MetadataLookupStatus.unmatched);
      var corroborated = false;
      if (id == null &&
          request.corroboration != null &&
          data.length < 30 &&
          request.contentTags.length == 1 &&
          request.contentTags.contains('official') &&
          request.baseProviderGameId == null &&
          request.revision?.isNotEmpty != true) {
        final agreeing = <int>[];
        for (var index = 0; index < games.length; index++) {
          if (_corroborates(games[index], request.corroboration!, platform)) {
            agreeing.add(index);
          }
        }
        if (agreeing.length > 1) {
          return _result(MetadataLookupStatus.ambiguous,
              candidates: candidates);
        }
        if (agreeing.length == 1) {
          final selected = agreeing.single;
          final game = games[selected];
          final candidate = candidates[selected];
          games
            ..clear()
            ..add(game);
          candidates
            ..clear()
            ..add(candidate);
          corroborated = true;
        }
      }
      if (games.length > 1) {
        return _result(MetadataLookupStatus.ambiguous, candidates: candidates);
      }
      final game = games.single;
      final type = game['game_type'];
      final kind = type is Map && type['type'] is String
          ? _normalize(type['type'] as String)
          : null;
      final official = request.contentTags.length == 1 &&
          request.contentTags.contains('official');
      // A reviewed global game ID may describe the original behind a known
      // translation/audio/restoration edition. It does not rate patch quality.
      const originalModifications = {'T-Eng', 'Dub', 'Undub', 'Uncensor'};
      final originalModification = request.contentTags.isNotEmpty &&
          originalModifications.containsAll(request.contentTags);
      final project = request.contentTags.contains('Hack') &&
          (kind == 'mod' || kind == 'fork') &&
          candidates.single.titleMatched &&
          request.baseProviderGameId != id;
      if ((id == null && !corroborated) ||
          (!official && !project && !originalModification) ||
          ((official || originalModification) &&
              (kind == null || kind == 'mod' || kind == 'fork')) ||
          request.revision?.isNotEmpty == true ||
          (request.baseProviderGameId != null &&
              !project &&
              (!originalModification || request.baseProviderGameId != id))) {
        return _result(MetadataLookupStatus.needsReview,
            candidates: candidates);
      }
      final at = _clock().toUtc();
      final matchedId = '${game['id']}';
      final ratings = <SourcedRating>[];
      for (final field in const [
        ('total_rating', 'IGDB overall', RatingKind.overallAggregate),
        ('aggregated_rating', 'IGDB critics', RatingKind.criticAggregate),
        ('rating', 'IGDB users', RatingKind.communityAggregate)
      ]) {
        final count = game['${field.$1}_count'];
        final rating = SourcedRating.parse(
            sourceId: providerId,
            sourceLabel: field.$2,
            providerGameId: matchedId,
            rawValue: game[field.$1],
            scaleMinimum: 0,
            scaleMaximum: 100,
            voteCount: count is int && count >= 0 ? count : null,
            kind: field.$3,
            retrievedAt: at);
        if (rating != null) ratings.add(rating);
      }
      final summary = game['summary'];
      final date = game['first_release_date'];
      return MetadataLookupResult(
          status: MetadataLookupStatus.matched,
          quota: _quota,
          candidates: candidates,
          message: originalModification
              ? 'Original-game facts retrieved, not patch quality; reception assessment remains required.'
              : 'Sourced aggregate retrieved; reception assessment remains required.',
          record: MetadataRecord(
              gameId: request.gameId,
              editionId: request.editionId,
              platformId: request.platformId,
              providerId: providerId,
              providerGameId: matchedId,
              retrievedAt: at,
              refreshGeneration: request.refreshGeneration,
              matchEvidence:
                  corroborated ? request.corroboration!.toJson() : const {},
              matchMethod: corroborated
                  ? 'corroboratedOfficialRelease'
                  : project
                      ? 'verifiedProjectId'
                      : 'verifiedProviderIdGlobalGame',
              titles: candidates.single.titles,
              descriptions:
                  summary is String ? [MetadataText(text: summary)] : [],
              releaseDates: date is int
                  ? [
                      MetadataText(
                          text: DateTime.fromMillisecondsSinceEpoch(date * 1000,
                                  isUtc: true)
                              .toIso8601String())
                    ]
                  : [],
              ratings: ratings,
              fieldProvenance: {
                for (final field in [
                  'title',
                  if (summary is String) 'description',
                  if (date is int) 'releaseDate',
                  if (ratings.isNotEmpty) 'rating'
                ])
                  field: MetadataFieldProvenance(
                      providerId: providerId,
                      providerGameId: matchedId,
                      field: field,
                      retrievedAt: at)
              }));
    } catch (error) {
      return _result(cancelToken?.isCancelled == true ||
              (error is DioException && error.type == DioExceptionType.cancel)
          ? MetadataLookupStatus.cancelled
          : error is MetadataCredentialStorageException
              ? MetadataLookupStatus.setupRequired
              : error is DioException
                  ? MetadataLookupStatus.unavailable
                  : MetadataLookupStatus.invalidResponse);
    }
  }

  static bool _corroborates(
      Map<String, dynamic> game, MetadataCorroboration facts, int platform) {
    final type = game['game_type'];
    if (type is! Map ||
        type['type'] is! String ||
        _normalize(type['type'] as String) != 'maingame' ||
        game['version_parent'] != null ||
        game['parent_game'] != null ||
        (game['alternative_names'] is List &&
            (game['alternative_names'] as List).length > 128)) {
      return false;
    }
    final titles = [
      game['name'],
      if (game['alternative_names'] is List)
        for (final alternative in game['alternative_names'] as List)
          if (alternative is Map) alternative['name']
    ];
    if (!titles.whereType<String>().any((title) =>
        _normalize(title).isNotEmpty &&
        facts.titles.any((known) => _normalize(known) == _normalize(title)))) {
      return false;
    }
    final releases = game['release_dates'];
    const regions = {
      'us': 'north_america',
      'eu': 'europe',
      'jp': 'japan',
      'wor': 'worldwide'
    };
    if (releases is! List ||
        releases.length > 256 ||
        !releases.any((release) {
          if (release is! Map ||
              release['platform'] != platform ||
              release['date'] is! int ||
              release['date_format'] is! Map ||
              (release['date_format'] as Map)['format'] != 'YYYYMMDD' ||
              release['release_region'] is! Map ||
              (release['release_region'] as Map)['region'] !=
                  regions[facts.region]) {
            return false;
          }
          return DateTime.fromMillisecondsSinceEpoch(
                      (release['date'] as int) * 1000,
                      isUtc: true)
                  .toIso8601String()
                  .substring(0, 10) ==
              facts.releaseDate;
        })) {
      return false;
    }
    final companies = game['involved_companies'];
    if (companies is! List || companies.length > 256) return false;
    bool role(String role, String expected) => companies.any((company) =>
        company is Map &&
        company[role] == true &&
        company['company'] is Map &&
        (company['company'] as Map)['name'] is String &&
        _normalize(expected).isNotEmpty &&
        _normalize((company['company'] as Map)['name'] as String) ==
            _normalize(expected));
    return role('developer', facts.developer) &&
        role('publisher', facts.publisher);
  }

  Future<({Object? data, MetadataLookupResult? failure})> _post(
      String url, Object data, Options options, CancelToken? cancel) async {
    final response = await _dio.post<ResponseBody>(url,
        data: data, options: options, cancelToken: cancel);
    final status = response.statusCode ?? 0;
    if (status != 200) {
      await response.data?.stream.listen((_) {}).cancel();
      if (status == 401) _clearToken();
      final delay = int.tryParse(response.headers.value('retry-after') ?? '');
      return (
        data: null,
        failure: MetadataLookupResult(
            status: status == 401 || status == 403
                ? MetadataLookupStatus.authenticationRequired
                : status == 429
                    ? MetadataLookupStatus.throttled
                    : MetadataLookupStatus.unavailable,
            quota: _quota,
            retryAfter:
                delay != null && delay >= 0 ? Duration(seconds: delay) : null,
            message:
                'IGDB request did not succeed; review access or provider availability.')
      );
    }
    final body = response.data;
    if (body == null) {
      return (
        data: null,
        failure: _result(MetadataLookupStatus.invalidResponse)
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        return (
          data: null,
          failure: _result(MetadataLookupStatus.invalidResponse)
        );
      }
      bytes.add(chunk);
    }
    if (cancel?.isCancelled == true) {
      return (data: null, failure: _result(MetadataLookupStatus.cancelled));
    }
    return (data: jsonDecode(utf8.decode(bytes.takeBytes())), failure: null);
  }

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  static MetadataLookupResult _result(MetadataLookupStatus status,
          {List<MetadataLookupCandidate> candidates = const []}) =>
      MetadataLookupResult(
          status: status,
          candidates: candidates,
          quota: _quota,
          message:
              'IGDB lookup ${status.name}; no unverified score was published.');
  void _clearToken() {
    _token = null;
    _expiresAt = null;
    _tokenOwner = null;
  }

  @override
  void close() {
    _clearToken();
    _dio.close(force: true);
  }
}
