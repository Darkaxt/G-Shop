import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/scraped_metadata.dart';
import '../library_store.dart';
import 'metadata_provider.dart';

class MetadataArtworkBlob {
  final String key;
  final String filename;
  final int length;
  MetadataArtworkBlob(this.key, this.filename, this.length);
}

/// App-private artwork, independent of ROM residency. Image selectors and hashed
/// relative names are persisted, never authenticated URLs or arbitrary paths.
class MetadataArtworkCache {
  static const maxBytes = 4 * 1024 * 1024;
  final Future<Database> _database;
  final Directory root;
  MetadataArtworkCache(this._database, Directory root) : root = root.absolute;

  static Future<void> install(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS metadata_artwork_cache (
      media_key TEXT PRIMARY KEY, filename TEXT NOT NULL,
      byte_length INTEGER NOT NULL, retrieved_at TEXT NOT NULL
    )''');

  static String key(MetadataMedia media) => sha256
      .convert(utf8.encode(jsonEncode([media.toJson(), 'png-1024-v1'])))
      .toString();

  Future<({MetadataLookupResult result, MetadataArtworkBlob? blob})> download(
      MetadataMedia media,
      MetadataArtworkProvider provider,
      int workId,
      CancelToken cancel) async {
    final mediaKey = key(media);
    final staging = File(p.join(root.path, '$mediaKey-$workId.part'));
    RandomAccessFile? writer;
    try {
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

  /// Validate bounded PNG structure/CRCs/dimensions without inflating image or
  /// metadata streams. Decode/resource limits are not inferred from MIME alone.
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
    final metadata =
        await LibraryStore(_database).metadata(editionId, providerId);
    final mediaKey = key(media);
    if (metadata == null || !metadata.media.any((m) => key(m) == mediaKey)) {
      return null;
    }
    final db = await _database;
    final rows = await db.query('metadata_artwork_cache',
        where: 'media_key = ?', whereArgs: [mediaKey], limit: 1);
    if (rows.isEmpty) return null;
    final filename = rows.single['filename'] as String;
    if (!RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(filename)) return null;
    final file = File(p.join(root.path, filename));
    return await file.exists() &&
            await file.length() == rows.single['byte_length']
        ? file
        : null;
  }
}
