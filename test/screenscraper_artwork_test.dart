import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/scraped_metadata.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';
import 'package:retro_eshop/services/metadata/metadata_provider.dart';
import 'package:retro_eshop/services/metadata/screenscraper_provider.dart';

class _Images implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  List<int> bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==');
  Map<String, List<String>> headers = {
    'content-type': ['image/png']
  };
  bool splitLastByte = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return splitLastByte
        ? ResponseBody(
            Stream.fromIterable([
              Uint8List.fromList(bytes.sublist(0, bytes.length - 1)),
              Uint8List.fromList(bytes.sublist(bytes.length - 1)),
            ]),
            status,
            headers: headers)
        : ResponseBody.fromBytes(bytes, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Images wire;
  late ScreenScraperProvider provider;
  final media = MetadataMedia(
      type: 'box-2D',
      region: 'us',
      providerReference: ScreenScraperMediaReference(
          providerGameId: '42',
          providerPlatformId: 4,
          mediaType: 'box-2D',
          region: 'us'));
  setUp(() {
    wire = _Images();
    provider = ScreenScraperProvider(
        httpClientAdapter: wire,
        readDeveloperCredentials: () async =>
            const ScreenScraperDeveloperCredentials(
                developerId: 'fixture',
                developerPassword: 'private',
                softwareName: 'fixture'),
        readUserCredentials: () async => const ScreenScraperUserCredentials(
            username: 'fixture', password: 'private'));
  });
  tearDown(() => provider.close());

  test('physical support textures use the normal authenticated image path',
      () async {
    final label = MetadataMedia(
        type: 'support-texture',
        region: 'us',
        providerReference: ScreenScraperMediaReference(
            providerGameId: '42',
            providerPlatformId: 4,
            mediaType: 'support-texture',
            region: 'us'));
    final received = <int>[];
    final result = await provider.fetchArtwork(label,
        write: (bytes) async => received.addAll(bytes));
    expect(result.status, MetadataLookupStatus.matched);
    expect(received, wire.bytes);
    expect(
        wire.requests.single.queryParameters['media'], 'support-texture(us)');
  });

  test('image selector uses fixed authenticated endpoint and bounded output',
      () async {
    final received = <int>[];
    final result = await provider.fetchArtwork(media,
        write: (List<int> bytes) async => received.addAll(bytes));
    expect(result.status, MetadataLookupStatus.matched);
    expect(received, wire.bytes);
    final request = wire.requests.single;
    expect(request.uri.host, 'api.screenscraper.fr');
    expect(request.uri.path, '/api2/mediaJeu.php');
    expect(request.queryParameters['media'], 'box-2D(us)');
    expect(request.queryParameters['systemeid'], 4);
    expect(request.queryParameters['jeuid'], '42');
    expect(request.queryParameters['outputformat'], 'png');
    expect(request.followRedirects, isFalse);
    expect(media.toJson().toString(), isNot(contains('private')));
  });

  test('documented NOMEDIA is a missing image, not a corrupt cache body',
      () async {
    wire.bytes = utf8.encode('NOMEDIA');
    wire.headers = {
      'content-type': ['text/plain']
    };
    var written = false;
    final result = await provider.fetchArtwork(media, write: (_) async {
      written = true;
    });
    expect(result.status, MetadataLookupStatus.unmatched);
    expect(written, isFalse);
  });

  test('live endpoint success marker is removed only after an exact PNG end',
      () async {
    final png = List<int>.from(wire.bytes);
    wire.bytes = [...png, 49];
    wire.splitLastByte = true;
    wire.headers['content-length'] = ['${wire.bytes.length}'];
    final written = <int>[];
    expect(
        (await provider.fetchArtwork(media,
                write: (bytes) async => written.addAll(bytes)))
            .status,
        MetadataLookupStatus.matched);
    expect(written, png);
    written.clear();
    wire.bytes = [...png, 49, 49];
    wire.headers['content-length'] = ['${wire.bytes.length}'];
    await provider.fetchArtwork(media,
        write: (bytes) async => written.addAll(bytes));
    expect(written, wire.bytes,
        reason: 'Do not trim arbitrary appended content or repeated markers.');
  });

  test('HTML and truncated responses cannot be reported received', () async {
    wire.bytes = utf8.encode('<html>challenge</html>');
    wire.headers = {
      'content-type': ['text/html']
    };
    final html = await provider.fetchArtwork(media, write: (_) async {});
    expect(html.status, MetadataLookupStatus.invalidResponse);
    wire.headers = {
      'content-type': ['image/png'],
      'content-length': ['1000']
    };
    final truncated = await provider.fetchArtwork(media, write: (_) async {});
    expect(truncated.status, MetadataLookupStatus.invalidResponse);
  });

  test('provider throttle retains Retry-After and does not publish its body',
      () async {
    wire.status = 429;
    wire.headers = {
      'retry-after': ['60']
    };
    var written = false;
    final result = await provider.fetchArtwork(media, write: (_) async {
      written = true;
    });
    expect(result.status, MetadataLookupStatus.throttled);
    expect(result.retryAfter, const Duration(seconds: 60));
    expect(written, isFalse);
  });

  test('image sink failure remains resumable storage unavailability', () async {
    final result = await provider.fetchArtwork(media,
        write: (_) async => throw const FileSystemException('fixture'));
    expect(result.status, MetadataLookupStatus.unavailable);
    expect(result.message, isNot(contains('fixture')));
  });

  test('oversized declared body is rejected before any image bytes are written',
      () async {
    wire.headers['content-length'] = [
      '${ScreenScraperProvider.maxResponseBytes + 1}'
    ];
    var written = false;
    final result = await provider.fetchArtwork(media, write: (_) async {
      written = true;
    });
    expect(result.status, MetadataLookupStatus.invalidResponse);
    expect(written, isFalse);
  });
}
