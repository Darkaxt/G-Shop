import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/scraped_metadata.dart';
import '../library_store.dart';
import 'metadata_provider.dart';
import 'shared_metadata_store.dart';

class MetadataArtworkBlob {
  final String key;
  final String filename;
  final int length;
  MetadataArtworkBlob(this.key, this.filename, this.length);
}

/// Selected-cache artwork, independent of ROM residency. Image selectors and hashed
/// relative names are persisted, never authenticated URLs or arbitrary paths.
class MetadataArtworkCache {
  static const maxBytes = 4 * 1024 * 1024;
  final Future<Database> _database;
  final Directory root;
  final SharedMetadataStore? sharedStore;
  MetadataArtworkCache(this._database, Directory root, {this.sharedStore})
      : root = root.absolute;

  static Future<MetadataArtworkCache> open(Future<Database> database) async =>
      MetadataArtworkCache(
          database,
          Directory(p.join((await getApplicationSupportDirectory()).path,
              'metadata-artwork')));

  Future<void> _requireAccess() async {
    if (sharedStore != null) {
      await sharedStore!.requireAccess();
    } else if (Platform.isAndroid && root.path.startsWith('/storage/')) {
      // A read-only cache can still reference the selected shared root after
      // opening its database failed. Do not bypass revoked permission there.
      await SharedMetadataStore.requireStoragePermission();
    }
  }

  static Future<void> install(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS metadata_artwork_cache (
      media_key TEXT PRIMARY KEY, filename TEXT NOT NULL,
      byte_length INTEGER NOT NULL, retrieved_at TEXT NOT NULL
    )''');

  static String key(MetadataMedia media) => sha256
      .convert(utf8.encode(jsonEncode([media.toJson(), 'png-1024-v1'])))
      .toString();

  /// Explicit edition review permits reuse of a local image, not stale facts.
  /// Bound the compressed body and encoded dimensions before native decoding.
  Future<({MetadataArtworkBlob blob, String sourceHash, int sourceLength})>
      importReviewedImage(File source, MetadataMedia media) async {
    await _requireAccess();
    var cursor = source.absolute.path;
    while (true) {
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException('Reviewed artwork cannot follow links');
      }
      final parent = p.dirname(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }
    if (!{'.png', '.jpg', '.webp'}.contains(p.extension(source.path))) {
      throw const FormatException('Unsupported ES-DE image format');
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in source.openRead()) {
      if (body.length + chunk.length > maxBytes) {
        throw const FormatException('Reviewed image exceeds body budget');
      }
      body.add(chunk);
    }
    final original = body.takeBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(original);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    Uint8List bytes;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width < 1 ||
          descriptor.height < 1 ||
          descriptor.width * descriptor.height > 4 * 1024 * 1024) {
        throw const FormatException('Reviewed image exceeds pixel budget');
      }
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = longest > 1024 ? 1024 / longest : 1.0;
      codec = await descriptor.instantiateCodec(
          targetWidth: (descriptor.width * scale).round().clamp(1, 1024),
          targetHeight: (descriptor.height * scale).round().clamp(1, 1024));
      if (codec.frameCount != 1) {
        throw const FormatException('Animated artwork cannot be imported');
      }
      final frame = await codec.getNextFrame();
      try {
        final encoded =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (encoded == null) {
          throw const FormatException('Image encoding failed');
        }
        bytes = _validPng(original)
            ? original
            : encoded.buffer
                .asUint8List(encoded.offsetInBytes, encoded.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
    if (!_validPng(bytes)) {
      throw const FormatException('Invalid normalized artwork');
    }
    await root.create(recursive: true);
    final filename = '${sha256.convert(bytes)}.png';
    final target = File(p.join(root.path, filename));
    if (await target.exists()) {
      if (await target.length() != bytes.length ||
          sha256.convert(await target.readAsBytes()).toString() !=
              filename.substring(0, 64)) {
        throw const FormatException('Immutable artwork content changed');
      }
    } else {
      final staging = await root.createTemp('reviewed-');
      try {
        final staged = File(p.join(staging.path, filename));
        await staged.writeAsBytes(bytes, flush: true);
        await staged.rename(target.path);
      } finally {
        await staging.delete(recursive: true);
      }
    }
    return (
      blob: MetadataArtworkBlob(key(media), filename, bytes.length),
      sourceHash: sha256.convert(original).toString(),
      sourceLength: original.length
    );
  }

  Future<({MetadataLookupResult result, MetadataArtworkBlob? blob})> download(
      MetadataMedia media,
      MetadataArtworkProvider provider,
      int workId,
      CancelToken cancel) async {
    final mediaKey = key(media);
    final staging = File(p.join(root.path, '$mediaKey-$workId.part'));
    RandomAccessFile? writer;
    try {
      await _requireAccess();
      await root.create(recursive: true);
      writer = await staging.open(mode: FileMode.write);
      var length = 0;
      final result = await provider.fetchArtwork(media, cancelToken: cancel,
          write: (chunk) async {
        length += chunk.length;
        if (length > maxBytes) {
          throw const FormatException('Image body exceeds cache limit');
        }
        if (!cancel.isCancelled) await writer!.writeFrom(chunk);
      });
      await writer.flush();
      await writer.close();
      writer = null;
      if (result.status != MetadataLookupStatus.matched || cancel.isCancelled) {
        return (
          result: cancel.isCancelled
              ? _failure(MetadataLookupStatus.cancelled)
              : result,
          blob: null
        );
      }
      final bytes = await staging.readAsBytes();
      if (!_validPng(bytes)) {
        return (
          result: _failure(MetadataLookupStatus.invalidResponse),
          blob: null
        );
      }
      // The bounded header alone cannot prove that IDAT decodes. Use Flutter's
      // native image decoder only after CRC, body, dimensions and frame limits.
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        if (codec.frameCount != 1) {
          return (
            result: _failure(MetadataLookupStatus.invalidResponse),
            blob: null
          );
        }
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      final filename = '${sha256.convert(bytes)}.png';
      final target = File(p.join(root.path, filename));
      await _requireAccess();
      // Immutable content-addressed publication; an older usable image survives
      // any failed refresh. An existing blob is never blindly overwritten.
      if (!await target.exists()) {
        await staging.rename(target.path);
      } else if (await target.length() != bytes.length ||
          sha256.convert(await target.readAsBytes()).toString() !=
              filename.substring(0, 64)) {
        return (
          result: _failure(MetadataLookupStatus.invalidResponse),
          blob: null
        );
      }
      return (
        result: result,
        blob: MetadataArtworkBlob(mediaKey, filename, bytes.length)
      );
    } on FileSystemException {
      return (result: _failure(MetadataLookupStatus.unavailable), blob: null);
    } catch (_) {
      return (
        result: _failure(cancel.isCancelled
            ? MetadataLookupStatus.cancelled
            : MetadataLookupStatus.invalidResponse),
        blob: null
      );
    } finally {
      await writer?.close();
      if (await staging.exists()) await staging.delete();
    }
  }

  static MetadataLookupResult _failure(MetadataLookupStatus status) =>
      MetadataLookupResult(
          status: status,
          message: 'Artwork was not published; cached images were preserved.');

  /// Bounded transient preview using the existing authenticated image transport
  /// and PNG validation. No disk entry, accepted fact or preview history.
  static Future<({MetadataLookupResult result, Uint8List? bytes})> fetchPreview(
      MetadataMedia media,
      MetadataArtworkProvider provider,
      CancelToken cancel) async {
    final buffer = BytesBuilder(copy: false);
    try {
      final result = await provider.fetchArtwork(media, cancelToken: cancel,
          write: (chunk) async {
        if (buffer.length + chunk.length > maxBytes) {
          throw const FormatException('Image body exceeds preview limit');
        }
        if (!cancel.isCancelled) buffer.add(chunk);
      });
      if (cancel.isCancelled || result.status != MetadataLookupStatus.matched) {
        return (
          result: cancel.isCancelled
              ? _failure(MetadataLookupStatus.cancelled)
              : result,
          bytes: null
        );
      }
      final bytes = buffer.takeBytes();
      if (!_validPng(bytes)) {
        return (
          result: _failure(MetadataLookupStatus.invalidResponse),
          bytes: null
        );
      }
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        if (codec.frameCount != 1) {
          return (
            result: _failure(MetadataLookupStatus.invalidResponse),
            bytes: null
          );
        }
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      return (result: result, bytes: cancel.isCancelled ? null : bytes);
    } catch (_) {
      return (
        result: _failure(cancel.isCancelled
            ? MetadataLookupStatus.cancelled
            : MetadataLookupStatus.invalidResponse),
        bytes: null
      );
    }
  }

  /// Validate bounded PNG structure/CRCs/dimensions without inflating image or
  /// metadata streams. Decode/resource limits are not inferred from MIME alone.
  static bool validNormalizedPng(Uint8List bytes) => _validPng(bytes);

  static bool _validPng(Uint8List bytes) {
    if (bytes.length < 57 ||
        bytes.length > maxBytes ||
        base64Encode(Uint8List.sublistView(bytes, 0, 8)) != 'iVBORw0KGgo=') {
      return false;
    }
    final data = ByteData.sublistView(bytes);
    var offset = 8;
    var imageData = false;
    while (offset + 12 <= bytes.length) {
      final length = data.getUint32(offset);
      final end = offset + length + 12;
      if (end > bytes.length) return false;
      final type = ascii.decode(bytes.sublist(offset + 4, offset + 8),
          allowInvalid: true);
      if (getCrc32(Uint8List.sublistView(bytes, offset + 4, end - 4)) !=
          data.getUint32(end - 4)) {
        return false;
      }
      if (offset == 8) {
        if (type != 'IHDR' || length != 13) return false;
        final width = data.getUint32(offset + 8);
        final height = data.getUint32(offset + 12);
        if (width < 1 || height < 1 || width > 1024 || height > 1024) {
          return false;
        }
      } else if (type == 'IHDR' || type == 'acTL') {
        return false; // No duplicate header or unbounded animation frames.
      }
      if (type == 'IDAT' && length > 0) imageData = true;
      if (type == 'IEND') {
        return length == 0 && imageData && end == bytes.length;
      }
      offset = end;
    }
    return false;
  }

  static Future<void> publish(DatabaseExecutor db, MetadataArtworkBlob blob,
          DateTime retrievedAt) =>
      db
          .insert(
              'metadata_artwork_cache',
              {
                'media_key': blob.key,
                'filename': blob.filename,
                'byte_length': blob.length,
                'retrieved_at': retrievedAt.toUtc().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace)
          .then((_) {});

  /// Read-only consumption verifies edition ownership using current metadata.
  /// It never discovers/fetches missing media, and never looks at installed ROMs.
  Future<File?> fileFor(
      String editionId, String providerId, MetadataMedia media) async {
    try {
      await _requireAccess();
    } on FileSystemException {
      return null;
    }
    return _fileFor(editionId, providerId, media);
  }

  Future<File?> _fileFor(
      String editionId, String providerId, MetadataMedia media) async {
    final store = LibraryStore(_database);
    final metadata = await store.metadata(editionId, providerId);
    final mediaKey = key(media);
    if (metadata == null) return null;
    final regions =
        (await store.edition(editionId))?.regions ?? const <String>[];
    if (![
      ...metadata.media,
      ...displayMedia(metadata, regions: regions, includePhysicalLabel: true)
    ].any((m) => key(m) == mediaKey)) {
      return null;
    }
    final db = await _database;
    final rows = await db.query('metadata_artwork_cache',
        where: 'media_key = ?', whereArgs: [mediaKey], limit: 1);
    if (rows.isEmpty) return null;
    final filename = rows.single['filename'] as String;
    if (!RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(filename)) return null;
    final file = File(p.join(root.path, filename));
    final length = rows.single['byte_length'] as int;
    if (length < 57 || length > maxBytes) return null;
    try {
      if (!await file.exists() || await file.length() != length) return null;
      var received = 0;
      final digest = await sha256
          .bind(file.openRead().map((chunk) {
            received += chunk.length;
            if (received > maxBytes) {
              throw const FormatException(
                  'Artwork exceeds the bounded body budget');
            }
            return chunk;
          }))
          .first;
      return received == length &&
              digest.toString() == filename.substring(0, 64)
          ? file
          : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Current, owned local media only. No selectors/URLs escape to card loaders.
  /// This same selection is snapshotted by the normal refresh, so it does not
  /// download every regional cover, logo, video or background the API offers.
  static List<MetadataMedia> displayMedia(MetadataRecord record,
      {bool includePhysicalLabel = false,
      bool includeVideo = false,
      Iterable<String> regions = const []}) {
    final labels = physicalLabels(record, regions: regions);
    MetadataMedia? video =
        record.media.where((m) => m.type == 'video-normalized').firstOrNull ??
            record.media.where((m) => m.type == 'video').firstOrNull;
    // Older collectors retained image selectors but omitted gameplay video.
    // Reuse the same verified provider identity; this requests a resource,
    // not a new game match or a claim that the provider has a valid clip.
    if (includeVideo && video == null && record.providerId == 'screenscraper') {
      final reference = record.media
          .map((m) => m.providerReference)
          .whereType<ScreenScraperMediaReference>()
          .where((r) => r.providerGameId == record.providerGameId)
          .firstOrNull;
      if (reference != null) {
        video = MetadataMedia(
            type: 'video',
            providerReference: ScreenScraperMediaReference(
                providerGameId: record.providerGameId,
                providerPlatformId: reference.providerPlatformId,
                mediaType: 'video'));
      }
    }
    MetadataMedia? cover;
    for (final type in ['box-2D', 'box-3D', 'cover']) {
      final matches = record.media.where((m) => m.type == type);
      if (matches.isNotEmpty) {
        cover = matches.first;
        break;
      }
    }
    // Legacy verified records may omit the front-box selector while retaining
    // the provider's physical-label reference. This is a typed API request, not
    // an assertion that artwork exists: only a validated response is published.
    if (cover == null &&
        record.providerId == 'screenscraper' &&
        labels.isNotEmpty) {
      final label = labels.first;
      final reference = label.providerReference;
      if (reference != null &&
          reference.providerGameId == record.providerGameId) {
        cover = MetadataMedia(
            type: 'box-2D',
            region: label.region,
            providerReference: ScreenScraperMediaReference(
                providerGameId: reference.providerGameId,
                providerPlatformId: reference.providerPlatformId,
                mediaType: 'box-2D',
                region: reference.region));
      }
    }
    return [
      if (cover != null) cover,
      if (includePhysicalLabel) ...labels,
      ...record.media.where((m) => {'ss', 'screenshot'}.contains(m.type)),
      if (includeVideo && video != null) video
    ];
  }

  /// World releases can use a representative English-market label. Exact
  /// regional editions never borrow a foreign label; unresolved same-region
  /// alternatives remain ambiguous. Disc members stay individually associated.
  static List<MetadataMedia> physicalLabels(MetadataRecord record,
      {Iterable<String> regions = const []}) {
    String normalized(String value) => switch (value.trim().toLowerCase()) {
          'usa' => 'us',
          'europe' => 'eu',
          'japan' || 'japon' => 'jp',
          'world' => 'wor',
          'france' => 'fr',
          _ => value.trim().toLowerCase()
        };
    final explicit = regions
        .map(normalized)
        .where((v) => v.isNotEmpty && v != 'wor')
        .toSet();
    final evidence = record.matchEvidence['region'];
    if (explicit.isEmpty &&
        evidence is String &&
        normalized(evidence) != 'wor') {
      explicit.add(normalized(evidence));
    }
    final labels =
        record.media.where((m) => m.type == 'support-texture').toList();
    final preferred = explicit.isNotEmpty
        ? [...explicit, 'wor', '']
        : ['wor', '', 'us', 'eu', 'jp'];
    List<MetadataMedia> selected = [];
    for (final region in preferred) {
      selected =
          labels.where((m) => normalized(m.region ?? '') == region).toList();
      if (selected.isNotEmpty) break;
    }
    if (selected.isEmpty && explicit.isEmpty && labels.length == 1) {
      selected = labels;
    }
    if (selected.length <= 1) return selected;
    if (selected.every((m) => m.memberIndex != null) &&
        selected.map((m) => m.memberIndex).toSet().length == selected.length) {
      return selected;
    }
    return const [];
  }

  Future<({String? cover, String? supportTexture, List<String> screenshots})>
      artworkForEdition(String editionId) async {
    try {
      await _requireAccess();
    } on FileSystemException {
      return (cover: null, supportTexture: null, screenshots: const <String>[]);
    }
    String? cover;
    String? supportTexture;
    final screenshots = <String>[];
    final regions =
        (await LibraryStore(_database).edition(editionId))?.regions ??
            const <String>[];
    for (final provider in ['screenscraper', 'romm']) {
      final record =
          await LibraryStore(_database).metadata(editionId, provider);
      if (record == null) continue;
      final selectedMedia =
          displayMedia(record, regions: regions, includePhysicalLabel: true);
      final labels = selectedMedia
          .where((m) => m.type == 'support-texture' && m.memberIndex == null)
          .toList();
      for (final item in selectedMedia) {
        final isCover = {'box-2D', 'box-3D', 'cover'}.contains(item.type);
        final isScreenshot = {'ss', 'screenshot'}.contains(item.type);
        final isLabel = item.type == 'support-texture' &&
            labels.length == 1 &&
            identical(item, labels.single);
        if ((!isCover || cover != null) &&
            !isScreenshot &&
            (!isLabel || supportTexture != null)) {
          continue;
        }
        final file = await _fileFor(editionId, provider, item);
        if (file == null) continue;
        final uri = file.uri.toString();
        if (isCover) cover ??= uri;
        if (isLabel) supportTexture ??= uri;
        if (isScreenshot && !screenshots.contains(uri)) screenshots.add(uri);
      }
    }
    return (
      cover: cover,
      supportTexture: supportTexture,
      screenshots: List<String>.unmodifiable(screenshots)
    );
  }

  /// Edition-owned cached gallery images only. No catalogue scan or provider
  /// lookup is triggered by opening the explorer. Missing faces remain missing.
  Future<Map<String, List<String>>> galleryForEdition(String editionId) async {
    await _requireAccess();
    final result = <String, List<String>>{};
    final store = LibraryStore(_database);
    final regions =
        (await store.edition(editionId))?.regions ?? const <String>[];
    const types = {
      'box-2D',
      'box-3D',
      'box-2D-back',
      'box-2D-side',
      'cover',
      'support-texture',
      'ss',
      'screenshot',
      'fanart',
      'manual-page'
    };
    String region(String value) => switch (value.toLowerCase()) {
          'europe' => 'eu',
          'usa' => 'us',
          'japan' => 'jp',
          _ => value.toLowerCase()
        };
    for (final provider in ['launchbox', 'screenscraper', 'romm']) {
      final record = await store.metadata(editionId, provider);
      if (record == null) continue;
      for (final media in record.media.where((m) => types.contains(m.type))) {
        if (media.region != null &&
            regions.isNotEmpty &&
            !regions.any((r) => region(r) == region(media.region!))) continue;
        final file = await _fileFor(editionId, provider, media);
        if (file != null) {
          final paths = result.putIfAbsent(media.type, () => []);
          if (!paths.contains(file.uri.toString()))
            paths.add(file.uri.toString());
        }
      }
    }
    return result;
  }

  /// Exact currently owned cover only, with the same bounded PNG policy.
  /// A changed or unreadable file produces the normal fallback, not a lookup.
  Future<Uint8List?> previewForEdition(String editionId) async {
    try {
      final cover = (await artworkForEdition(editionId)).cover;
      if (cover == null) return null;
      final reader = await File.fromUri(Uri.parse(cover)).open();
      try {
        final bytes = await reader.read(maxBytes + 1);
        return _validPng(bytes) ? bytes : null;
      } finally {
        await reader.close();
      }
    } on FileSystemException {
      return null;
    }
  }
}
