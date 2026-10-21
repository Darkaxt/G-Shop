import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../models/scraped_metadata.dart';
import 'metadata_provider.dart';
import 'screenscraper_provider.dart';
import 'shared_metadata_store.dart';

/// Content-addressed clips and exact ownership receipts in the selected shared
/// store. Relative paths survive full-device migration; no authenticated URLs.
class PreviewVideoCache {
  final SharedMetadataStore store;
  final Future<void> Function(File) validateDecoder;
  PreviewVideoCache(this.store, {Future<void> Function(File)? validateDecoder})
      : validateDecoder = validateDecoder ?? _nativeDecoder;
  Directory get root => Directory(p.join(store.root.path, 'preview-videos'));
  static String key(MetadataMedia media) =>
      sha256.convert(utf8.encode(jsonEncode(media.toJson()))).toString();
  static Future<void> _nativeDecoder(File file) async {
    final result = await const MethodChannel('com.darkaxt.gshop/storage')
        .invokeMapMethod<String, dynamic>(
            'validatePreviewVideo', {'path': file.path});
    if (result?['ready'] != true)
      throw const FormatException('Video could not be decoded');
  }

  Future<String?> find(MetadataMedia media, {bool background = true}) async {
    await store.requireAccess();
    var receipt = await _receipt(File(p.join(root.path, '${key(media)}.json')));
    if (receipt == null ||
        !await _intact(
            File(p.join(root.path, receipt['file'] as String)), receipt)) {
      await store.fetchCloudMedia?.call(key(media), userRequested: !background);
      receipt = await _receipt(File(p.join(root.path, '${key(media)}.json')));
    }
    if (receipt == null) return null;
    final video = File(p.join(root.path, receipt['file'] as String));
    if (!await _intact(video, receipt)) return null;
    return video.path;
  }

  Future<String> acquire(
      MetadataMedia media, MetadataArtworkProvider provider, CancelToken cancel,
      {required int budgetBytes,
      String? protectedPath,
      void Function(MetadataLookupResult)? onResponse}) async {
    await store.requireAccess();
    if (!ScreenScraperProvider.videoTypes.contains(media.type))
      throw const FormatException('Not a gameplay clip');
    final existing = await find(media, background: false);
    if (existing != null) return existing;
    await root.create(recursive: true);
    final id = key(media);
    final staging = File(p.join(root.path, '$id.part'));
    RandomAccessFile? writer;
    try {
      writer = await staging.open(mode: FileMode.write);
      var length = 0;
      final result = await provider.fetchArtwork(media, cancelToken: cancel,
          write: (chunk) async {
        if (cancel.isCancelled) throw cancel.cancelError!;
        length += chunk.length;
        if (length > ScreenScraperProvider.maxVideoBytes ||
            length > budgetBytes) {
          throw const FormatException('Clip exceeds video cache budget');
        }
        await writer!.writeFrom(chunk);
      });
      onResponse?.call(result);
      await writer.flush();
      await writer.close();
      writer = null;
      if (cancel.isCancelled) throw cancel.cancelError!;
      if (result.status != MetadataLookupStatus.matched)
        throw StateError(result.message);
      await validateMp4(staging);
      await validateDecoder(staging);
      if (cancel.isCancelled) throw cancel.cancelError!;
      await store.requireAccess();
      final digest = (await sha256.bind(staging.openRead()).first).toString();
      final filename = '$digest.mp4';
      final target = File(p.join(root.path, filename));
      if (await target.exists()) {
        if (await target.length() != length ||
            (await sha256.bind(target.openRead()).first).toString() != digest) {
          throw const FormatException('Cached clip integrity mismatch');
        }
      } else {
        await staging.rename(target.path);
      }
      final receipt = File(p.join(root.path, '$id.json'));
      // This worker is serialized by MetadataControls, and migration joins it.
      await receipt.writeAsString(
          jsonEncode({
            'version': 1,
            'key': id,
            'file': filename,
            'bytes': length,
            'sha256': digest,
            'usedAt': DateTime.now().toUtc().toIso8601String()
          }),
          flush: true);
      store.cloudChanged?.call();
      await trim(budgetBytes, protectedPaths: {
        target.path,
        if (protectedPath != null) protectedPath
      });
      return target.path;
    } finally {
      await writer?.close();
      if (await staging.exists()) await staging.delete();
    }
  }

  /// Validate top-level MP4 bounds without loading or inflating the movie.
  static Future<void> validateMp4(File file) async {
    final reader = await file.open();
    try {
      final length = await reader.length();
      if (length < 24 || length > ScreenScraperProvider.maxVideoBytes)
        throw const FormatException('Invalid clip length');
      var offset = 0;
      final boxes = <String>{};
      while (offset < length) {
        if (length - offset < 8)
          throw const FormatException('Truncated MP4 box');
        await reader.setPosition(offset);
        final header = await reader.read(8);
        var size = ByteData.sublistView(header).getUint32(0);
        final type = ascii.decode(header.sublist(4), allowInvalid: true);
        var headerSize = 8;
        if (size == 1) {
          final extended = await reader.read(8);
          if (extended.length != 8)
            throw const FormatException('Truncated MP4 size');
          size = ByteData.sublistView(extended).getUint64(0);
          headerSize = 16;
        } else if (size == 0) {
          size = length - offset;
        }
        if (size < headerSize ||
            size > length - offset ||
            (offset == 0 && type != 'ftyp')) {
          throw const FormatException('Invalid MP4 box');
        }
        boxes.add(type);
        offset += size;
      }
      if (!boxes.containsAll({'ftyp', 'moov', 'mdat'}))
        throw const FormatException('Incomplete MP4 movie');
    } finally {
      await reader.close();
    }
  }

  Future<Map<String, dynamic>?> _receipt(File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > 1024) return null;
    try {
      final value = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
      if (value['version'] != 1 ||
          value['key'] != p.basenameWithoutExtension(file.path) ||
          !RegExp(r'^[0-9a-f]{64}\.mp4$')
              .hasMatch(value['file'] as String? ?? '') ||
          value['file'] != '${value['sha256']}.mp4' ||
          value['bytes'] is! int ||
          (value['bytes'] as int) <= 0 ||
          (value['bytes'] as int) > ScreenScraperProvider.maxVideoBytes ||
          DateTime.tryParse(value['usedAt'] as String? ?? '') == null)
        return null;
      return value;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<bool> _intact(File file, Map<String, dynamic> receipt) async =>
      await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.file &&
      await file.length() == receipt['bytes'] &&
      (await sha256.bind(file.openRead()).first).toString() ==
          receipt['sha256'];

  Future<void> trim(int budgetBytes,
      {Set<String> protectedPaths = const {}}) async {
    if (store.cloudManaged)
      return; // The combined cache owns verified eviction.
    await store.requireAccess();
    if (!await root.exists()) return;
    final owned = <({File receipt, Map<String, dynamic> data})>[];
    await for (final member in root.list(followLinks: false)) {
      if (member is! File ||
          !RegExp(r'^[0-9a-f]{64}\.json$').hasMatch(p.basename(member.path)))
        continue;
      final data = await _receipt(member);
      if (data != null) owned.add((receipt: member, data: data));
    }
    owned.sort((a, b) =>
        (a.data['usedAt'] as String).compareTo(b.data['usedAt'] as String));
    var total = {
      for (final entry in owned) entry.data['file']: entry.data['bytes'] as int
    }.values.fold<int>(0, (sum, n) => sum + n);
    for (final entry in owned) {
      if (total <= budgetBytes) break;
      final video = File(p.join(root.path, entry.data['file'] as String));
      if (protectedPaths.contains(video.path)) continue;
      if (!await _intact(video, entry.data)) continue;
      final aliases =
          owned.where((v) => v.data['file'] == entry.data['file']).toList();
      if (aliases.any((v) => !v.receipt.existsSync())) continue;
      await video.delete();
      for (final alias in aliases) {
        await alias.receipt.delete();
      }
      total -= entry.data['bytes'] as int;
    }
  }
}
