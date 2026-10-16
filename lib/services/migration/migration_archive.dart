import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

/// An entry's name is an archive-relative identifier, never a destination path.
class MigrationFile {
  final String name;
  final File source;
  const MigrationFile(this.name, this.source);
}

class MigrationArchiveException implements Exception {
  final String code;
  const MigrationArchiveException(this.code);
  // Do not include passwords, manifest values or local paths in diagnostics.
  @override
  String toString() => 'MigrationArchiveException($code)';
}

/// Returned only after every authenticated frame, digest and the final EOF pass.
/// The caller owns this app-private generation until commit or rollback.
class MigrationSnapshot {
  final Directory root;
  final Map<String, dynamic> state;
  final List<Map<String, dynamic>> entries;
  const MigrationSnapshot(this.root, this.state, this.entries);
  File file(String name) {
    MigrationArchive.checkName(name);
    if (!entries.any((entry) => entry['name'] == name)) {
      throw const MigrationArchiveException('missing_entry');
    }
    return File(p.joinAll([root.path, ...name.split('/')]));
  }
}

/// RSMIG001: PBKDF2-HMAC-SHA256 / AES-256-GCM, bounded authenticated frames.
/// Nonces are a fresh random 64-bit archive prefix + monotonic 32-bit counter.
/// Header, frame kind/length/counter and previous MAC are AAD. The encrypted
/// manifest fixes entry order, sizes and SHA-256; an authenticated terminator
/// plus exact EOF prevents truncation, insertion, reordering and concatenation.
/// ROM IO is sequential and bounded to one MiB, not a whole-file allocation.
class MigrationArchive {
  static const iterations = 600000;
  static const chunkBytes = 1024 * 1024;
  static const maxManifestBytes = 16 * 1024 * 1024;
  static const maxEntries = 250000;
  static final _magic = ascii.encode('RSMIG001');
  final AesGcm cipher;
  final Pbkdf2 kdf;
  MigrationArchive({AesGcm? cipher, Pbkdf2? kdf})
      : cipher = cipher ?? AesGcm.with256bits(),
        kdf = kdf ?? Pbkdf2.hmacSha256(iterations: iterations, bits: 256);

  static void checkName(String name) {
    if (name.isEmpty ||
        name.length > 1024 ||
        name.contains('\\') ||
        name.contains(':') ||
        name.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        name
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const MigrationArchiveException('unsafe_path');
    }
  }

  Future<void> write(File destination,
      {required String password,
      required Map<String, Object?> state,
      required List<MigrationFile> files,
      void Function(int completed, int total)? progress,
      void Function()? checkCancellation}) async {
    if (password.length < 12) {
      throw const MigrationArchiveException('short_password');
    }
    if (files.length > maxEntries) {
      throw const MigrationArchiveException('too_many_entries');
    }
    final names = <String>{};
    final entries = <Map<String, Object?>>[];
    var total = 0;
    for (final file in files) {
      checkCancellation?.call();
      checkName(file.name);
      // Reject case-fold collisions too: backups must remain portable to
      // case-insensitive storage and must not create ambiguous activation paths.
      if (!names.add(file.name.toLowerCase())) {
        throw const MigrationArchiveException('duplicate_entry');
      }
      await _requireRegular(file.source);
      final size = await file.source.length();
      final digest = await hashes.sha256.bind(file.source.openRead()).first;
      entries.add({'name': file.name, 'size': size, 'sha256': '$digest'});
      total += size;
    }
    final manifest = utf8.encode(jsonEncode({
      'schema': 1,
      'state': state,
      'entries': entries,
    }));
    if (manifest.length > maxManifestBytes) {
      throw const MigrationArchiveException('oversized_manifest');
    }
    if (await destination.exists()) {
      throw const MigrationArchiveException('destination_exists');
    }
    final random = Random.secure();
    final header = Uint8List(40)..setRange(0, 8, _magic);
    ByteData.sublistView(header)
      ..setUint32(8, 1)
      ..setUint32(12, iterations);
    for (var i = 16; i < header.length; i++) {
      header[i] = random.nextInt(256);
    }
    final key = await kdf.deriveKeyFromPassword(
        password: password, nonce: header.sublist(16, 32));
    RandomAccessFile? output;
    var created = false;
    try {
      await destination.create(exclusive: true);
      created = true;
      output = await destination.open(mode: FileMode.write);
      await output.writeFrom(header);
      final frames = _ArchiveFrames(cipher, key, header);
      await frames.write(output, 0, manifest);
      var completed = 0;
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        await _requireRegular(file.source);
        final input = await file.source.open();
        final digest = _Digest();
        try {
          var remaining = entries[i]['size'] as int;
          while (remaining > 0) {
            checkCancellation?.call();
            final bytes = await input.read(min(remaining, chunkBytes));
            if (bytes.isEmpty) {
              throw const MigrationArchiveException('source_changed');
            }
            digest.add(bytes);
            await frames.write(output, 1, bytes);
            remaining -= bytes.length;
            completed += bytes.length;
            progress?.call(completed, total);
          }
          if ((await input.read(1)).isNotEmpty ||
              digest.finish() != entries[i]['sha256']) {
            throw const MigrationArchiveException('source_changed');
          }
        } finally {
          await input.close();
        }
      }
      checkCancellation?.call();
      await frames.write(output, 2, const []);
      await output.flush();
    } catch (_) {
      await output?.close();
      output = null;
      // This invocation created this exact file, not a pre-existing archive.
      if (created && await destination.exists()) await destination.delete();
      rethrow;
    } finally {
      await output?.close();
    }
  }

  Future<MigrationSnapshot> read(File archive,
      {required String password,
      required Directory privateRoot,
      void Function(int completed, int total)? progress,
      void Function()? checkCancellation}) async {
    await _requireRegular(archive);
    final input = await archive.open();
    Directory? generation;
    try {
      final header = await _exact(input, 40);
      final fields = ByteData.sublistView(header);
      if (!_same(header.sublist(0, 8), _magic) ||
          fields.getUint32(8) != 1 ||
          fields.getUint32(12) != iterations) {
        throw const MigrationArchiveException('unsupported_archive');
      }
      final key = await kdf.deriveKeyFromPassword(
          password: password, nonce: header.sublist(16, 32));
      final frames = _ArchiveFrames(cipher, key, header);
      final clearManifest = await frames.read(input, 0, maxManifestBytes);
      final decoded = jsonDecode(utf8.decode(clearManifest));
      if (decoded is! Map ||
          decoded['schema'] != 1 ||
          decoded['state'] is! Map ||
          decoded['entries'] is! List ||
          (decoded['entries'] as List).length > maxEntries) {
        throw const MigrationArchiveException('invalid_manifest');
      }
      final entries = <Map<String, dynamic>>[];
      final names = <String>{};
      var total = 0;
      for (final value in decoded['entries'] as List) {
        if (value is! Map ||
            value['name'] is! String ||
            value['size'] is! int ||
            value['size'] < 0 ||
            value['sha256'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['sha256'])) {
          throw const MigrationArchiveException('invalid_manifest');
        }
        final entry = value.cast<String, dynamic>();
        checkName(entry['name'] as String);
        if (!names.add((entry['name'] as String).toLowerCase())) {
          throw const MigrationArchiveException('duplicate_entry');
        }
        entries.add(entry);
        total += entry['size'] as int;
      }
      // A file cannot also be an ancestor directory of another entry.
      for (final name in names) {
        final parts = name.split('/');
        for (var i = 1; i < parts.length; i++) {
          if (names.contains(parts.take(i).join('/'))) {
            throw const MigrationArchiveException('duplicate_entry');
          }
        }
      }
      await privateRoot.create(recursive: true);
      if (await FileSystemEntity.type(privateRoot.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          p.normalize(await privateRoot.resolveSymbolicLinks()) !=
              p.normalize(privateRoot.absolute.path)) {
        throw const MigrationArchiveException('unsafe_staging');
      }
      generation = await privateRoot.createTemp('incoming-');
      var completed = 0;
      for (final entry in entries) {
        checkCancellation?.call();
        final file = File(p.joinAll(
            [generation.path, ...(entry['name'] as String).split('/')]));
        await file.parent.create(recursive: true);
        final output = await file.open(mode: FileMode.write);
        final digest = _Digest();
        try {
          var remaining = entry['size'] as int;
          while (remaining > 0) {
            checkCancellation?.call();
            final clear =
                await frames.read(input, 1, min(remaining, chunkBytes));
            if (clear.isEmpty) {
              throw const MigrationArchiveException('invalid_frame');
            }
            await output.writeFrom(clear);
            digest.add(clear);
            remaining -= clear.length;
            completed += clear.length;
            progress?.call(completed, total);
          }
          if (digest.finish() != entry['sha256']) {
            throw const MigrationArchiveException('invalid_digest');
          }
          await output.flush();
        } finally {
          await output.close();
        }
      }
      if ((await frames.read(input, 2, 0)).isNotEmpty ||
          (await input.read(1)).isNotEmpty) {
        throw const MigrationArchiveException('trailing_data');
      }
      checkCancellation?.call();
      return MigrationSnapshot(generation,
          (decoded['state'] as Map).cast<String, dynamic>(), entries);
    } catch (error) {
      if (generation != null) await generation.delete(recursive: true);
      if (error is MigrationArchiveException) rethrow;
      // Authentication/JSON/IO errors must never expose private payload values.
      throw const MigrationArchiveException('invalid_archive_or_password');
    } finally {
      await input.close();
    }
  }

  static Future<void> _requireRegular(File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        p.normalize(await file.resolveSymbolicLinks()) !=
            p.normalize(file.absolute.path)) {
      throw const MigrationArchiveException('unsafe_source');
    }
  }
}

class _ArchiveFrames {
  final AesGcm cipher;
  final SecretKey key;
  final Uint8List header;
  int sequence = 0;
  List<int> previousMac = List.filled(16, 0);
  _ArchiveFrames(this.cipher, this.key, this.header);
  List<int> _nonce() => (Uint8List(12)
    ..setRange(0, 8, header.sublist(32))
    ..buffer.asByteData().setUint32(8, sequence));
  List<int> _aad(Uint8List frame) => [...header, ...frame, ...previousMac];
  void _checkSequence() {
    if (sequence >= 0xffffffff) {
      throw const MigrationArchiveException('archive_too_large');
    }
  }

  Future<void> write(RandomAccessFile output, int kind, List<int> clear) async {
    _checkSequence();
    final frame = Uint8List(9);
    ByteData.sublistView(frame)
      ..setUint8(0, kind)
      ..setUint32(1, sequence)
      ..setUint32(5, clear.length);
    final box = await cipher.encrypt(clear,
        secretKey: key, nonce: _nonce(), aad: _aad(frame));
    await output.writeFrom(frame);
    await output.writeFrom(box.cipherText);
    await output.writeFrom(box.mac.bytes);
    previousMac = box.mac.bytes;
    sequence++;
  }

  Future<List<int>> read(RandomAccessFile input, int kind, int maximum) async {
    _checkSequence();
    final frame = await _exact(input, 9);
    final fields = ByteData.sublistView(frame);
    final size = fields.getUint32(5);
    if (fields.getUint8(0) != kind ||
        fields.getUint32(1) != sequence ||
        size > maximum) {
      throw const MigrationArchiveException('invalid_frame');
    }
    final encrypted = await _exact(input, size);
    final mac = await _exact(input, 16);
    final clear = await cipher.decrypt(
        SecretBox(encrypted, nonce: _nonce(), mac: Mac(mac)),
        secretKey: key,
        aad: _aad(frame));
    previousMac = mac;
    sequence++;
    return clear;
  }
}

Future<Uint8List> _exact(RandomAccessFile input, int size) async {
  final bytes = Uint8List(size);
  var offset = 0;
  while (offset < size) {
    final read = await input.readInto(bytes, offset, size);
    if (read == 0) throw const MigrationArchiveException('truncated_archive');
    offset += read;
  }
  return bytes;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

class _Digest {
  final _DigestResult result = _DigestResult();
  late final Sink<List<int>> input =
      hashes.sha256.startChunkedConversion(result);
  void add(List<int> bytes) => input.add(bytes);
  String finish() {
    input.close();
    return result.value.toString();
  }
}

class _DigestResult implements Sink<hashes.Digest> {
  hashes.Digest? value;
  @override
  void add(hashes.Digest data) => value = data;
  @override
  void close() {}
}
