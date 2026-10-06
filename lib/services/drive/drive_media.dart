import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../models/library_identity.dart';
import 'drive_authorization.dart';

enum DriveTransferIssue {
  invalidSource,
  missingChecksum,
  sourceChanged,
  checksumMismatch,
  invalidRange,
  restartRequired,
  truncated,
  invalidResponse,
  accessDenied,
  notFound,
  quota,
  unavailable,
  cancelled,
}

class DriveTransferException implements Exception {
  final DriveTransferIssue issue;
  const DriveTransferException(this.issue);
  @override
  String toString() => 'Google Drive transfer: ${issue.name}';
}

class DriveMediaResponse {
  final Stream<Uint8List> bytes;
  final int offset;
  final int length;
  final int total;
  const DriveMediaResponse({
    required this.bytes,
    required this.offset,
    required this.length,
    required this.total,
  });
}

/// Binary-only transport; publication and installation belong to the transfer
/// engine. A saved artifact is never an authenticated URL.
class DriveMediaApi {
  static const maxChunkBytes = 1024 * 1024;
  final DriveAuthorization authorization;
  final String accountId;
  final HttpClientAdapter _transport;
  DriveMediaApi({
    required this.authorization,
    required this.accountId,
    HttpClientAdapter? httpClientAdapter,
  }) : _transport = httpClientAdapter ?? IOHttpClientAdapter();

  Future<DriveMediaResponse> open(RemoteArtifact artifact,
      {required int offset,
      int? endInclusive,
      required CancelToken cancelToken}) async {
    final total = artifact.sizeBytes;
    if (artifact.id.providerId != 'drive' ||
        artifact.id.accountId != accountId ||
        total == null ||
        total < 0 ||
        artifact.canDownload != true ||
        artifact.version?.isNotEmpty != true) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
    if (offset < 0 ||
        offset > total ||
        (endInclusive != null &&
            (endInclusive < offset || endInclusive >= total))) {
      throw const DriveTransferException(DriveTransferIssue.invalidRange);
    }
    try {
      String? rejected;
      for (var attempt = 0; attempt < 2; attempt++) {
        _checkCancellation(cancelToken);
        final grant = await authorization.acquire(
            expectedAccountId: accountId, rejectedToken: rejected);
        _checkCancellation(cancelToken);
        // Use the native adapter's original single-subscription stream. Dio
        // 5.9.1's high-level response handler eagerly subscribes and does not
        // propagate pause/cancel to its upstream, allowing unbounded buffering
        // behind a slow destination. The raw adapter retains socket backpressure.
        final request = RequestOptions(
            baseUrl: 'https://www.googleapis.com/drive/v3/',
            path: 'files/${Uri.encodeComponent(artifact.id.providerFileId)}',
            method: 'GET',
            responseType: ResponseType.stream,
            followRedirects: false,
            queryParameters: const {
              'alt': 'media'
            },
            headers: {
              'Authorization': 'Bearer ${grant.accessToken}',
              // Range and checksum refer to exact stored bytes, not a content
              // encoding chosen by an intermediary.
              'Accept-Encoding': 'identity',
              if (endInclusive != null || offset > 0)
                'Range': 'bytes=$offset-${endInclusive ?? ''}',
            });
        final body =
            await _transport.fetch(request, null, cancelToken.whenCancel);
        final headers = Headers.fromMap(body.headers);
        try {
          _checkCancellation(cancelToken);
          final status = body.statusCode;
          if (status == 401) {
            if (attempt == 0) {
              rejected = grant.accessToken;
              await _discard(body);
              continue;
            }
            throw const DriveAuthorizationException(
                DriveAuthorizationIssue.interactionRequired);
          }
          final encoding = headers.value('content-encoding');
          if (encoding != null && encoding.toLowerCase() != 'identity') {
            throw const DriveTransferException(
                DriveTransferIssue.invalidResponse);
          }
          if (status == 416 &&
              endInclusive == null &&
              offset == total &&
              headers.value('content-range') == 'bytes */$total') {
            // This establishes no installation claim. The caller must still
            // hash the durable file and revalidate the source before publishing.
            await _discard(body);
            return DriveMediaResponse(
                bytes: const Stream.empty(),
                offset: offset,
                length: 0,
                total: total);
          }
          if (status == 200 && endInclusive != null) {
            throw const DriveTransferException(DriveTransferIssue.invalidRange);
          }
          if (status == 200 && offset > 0) {
            // The engine may explicitly discard this transfer's partial and
            // restart. It must never append a full response to old bytes.
            throw const DriveTransferException(
                DriveTransferIssue.restartRequired);
          }
          final end = endInclusive ?? total - 1;
          final expectedLength = end + 1 - offset;
          if (status == 206) {
            final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
                .firstMatch(headers.value('content-range') ?? '');
            if (range == null ||
                int.tryParse(range[1]!) != offset ||
                int.tryParse(range[2]!) != end ||
                int.tryParse(range[3]!) != total ||
                expectedLength <= 0) {
              throw const DriveTransferException(
                  DriveTransferIssue.invalidRange);
            }
          } else if (status != 200) {
            throw DriveTransferException(switch (status) {
              403 => DriveTransferIssue.accessDenied,
              404 => DriveTransferIssue.notFound,
              416 => DriveTransferIssue.invalidRange,
              429 => DriveTransferIssue.quota,
              _ => DriveTransferIssue.unavailable,
            });
          } else if (headers.value('content-range') != null) {
            throw const DriveTransferException(DriveTransferIssue.invalidRange);
          }
          final rawLength = headers.value('content-length');
          if (rawLength != null && int.tryParse(rawLength) != expectedLength) {
            throw const DriveTransferException(DriveTransferIssue.invalidRange);
          }
          return DriveMediaResponse(
              bytes: _checkedBytes(body.stream, expectedLength, cancelToken),
              offset: offset,
              length: expectedLength,
              total: total);
        } catch (_) {
          await _discard(body);
          rethrow;
        }
      }
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.interactionRequired);
    } on DriveTransferException {
      rethrow;
    } on DriveAuthorizationException {
      rethrow;
    } on DioException catch (error) {
      throw DriveTransferException(
          cancelToken.isCancelled || error.type == DioExceptionType.cancel
              ? DriveTransferIssue.cancelled
              : DriveTransferIssue.unavailable);
    } on IOException {
      // The raw native adapter can surface HttpException from request.close(),
      // including its explicit abort. It is not a malformed HTTP response.
      throw DriveTransferException(cancelToken.isCancelled
          ? DriveTransferIssue.cancelled
          : DriveTransferIssue.unavailable);
    } catch (_) {
      // Malformed/multi-valued headers are untrusted response data as well.
      throw DriveTransferException(cancelToken.isCancelled
          ? DriveTransferIssue.cancelled
          : DriveTransferIssue.invalidResponse);
    }
  }

  Stream<Uint8List> _checkedBytes(Stream<Uint8List> input, int expectedLength,
      CancelToken cancellation) async* {
    var received = 0;
    try {
      await for (final chunk in input) {
        _checkCancellation(cancellation);
        if (chunk.length > maxChunkBytes ||
            received + chunk.length > expectedLength) {
          throw const DriveTransferException(
              DriveTransferIssue.invalidResponse);
        }
        received += chunk.length;
        yield chunk;
      }
      _checkCancellation(cancellation);
      if (received != expectedLength) {
        throw const DriveTransferException(DriveTransferIssue.truncated);
      }
    } on DriveTransferException {
      rethrow;
    } catch (_) {
      throw DriveTransferException(cancellation.isCancelled
          ? DriveTransferIssue.cancelled
          : DriveTransferIssue.unavailable);
    }
  }

  static void _checkCancellation(CancelToken cancellation) {
    if (cancellation.isCancelled) {
      throw const DriveTransferException(DriveTransferIssue.cancelled);
    }
  }

  static Future<void> _discard(ResponseBody body) =>
      body.stream.listen((_) {}, onError: (Object _) {}).cancel();

  void close() => _transport.close();
}
