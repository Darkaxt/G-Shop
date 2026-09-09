import 'package:flutter/services.dart';

import '../models/transfer_record.dart';

class OwnedStorageException implements Exception {
  final String code;
  const OwnedStorageException(this.code);
  @override
  String toString() => 'Owned storage: $code';
}

/// The selected staging directory is persistent app storage, never cache or a
/// ROM directory. Volume equality is a hint, not a publication capability claim.
class OwnedStoragePlan {
  final String destinationRoot;
  final String stageRoot;
  final String destinationVolume;
  final String stageVolume;

  /// Runtime namespace hints only, not persistent ownership or capabilities.
  final String destinationMount;
  final String stageMount;
  final int destinationFreeBytes;
  final int stageFreeBytes;
  const OwnedStoragePlan(
      {required this.destinationRoot,
      required this.stageRoot,
      required this.destinationVolume,
      required this.stageVolume,
      required this.destinationMount,
      required this.stageMount,
      required this.destinationFreeBytes,
      required this.stageFreeBytes});
  bool get sameVolumeHint => destinationVolume == stageVolume;
  bool get sameMountHint => destinationMount == stageMount;
  String stagePath(String transferId) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,96}$').hasMatch(transferId)) {
      throw const OwnedStorageException('invalid_arguments');
    }
    return '$stageRoot/$transferId.partial';
  }
}

/// Narrow native storage boundary. It does not authorize downloads, claim
/// installation, remove existing targets or invoke legacy extraction helpers.
class OwnedStorage {
  static const maxChunkBytes = 64 * 1024;
  final MethodChannel channel;
  const OwnedStorage(
      {this.channel = const MethodChannel('com.retro.rshop/storage')});

  Future<Object?> _invoke(String method,
      [Map<String, Object?>? arguments]) async {
    try {
      return await channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      const codes = {
        'invalid_arguments',
        'collision',
        'not_found',
        'unsupported',
        'cross_volume',
        'out_of_space',
        'access_denied',
        'changed',
        'closed',
        'io_error'
      };
      throw OwnedStorageException(
          codes.contains(error.code) ? error.code : 'io_error');
    } on MissingPluginException {
      throw const OwnedStorageException('unsupported');
    }
  }

  Future<OwnedStoragePlan> prepare(String destinationRoot) async {
    final value =
        await _invoke('ownedPrepare', {'destinationRoot': destinationRoot});
    final map = (value as Map).cast<String, Object?>();
    return OwnedStoragePlan(
        destinationRoot: map['destinationRoot'] as String,
        stageRoot: map['stageRoot'] as String,
        destinationVolume: map['destinationVolume'] as String,
        stageVolume: map['stageVolume'] as String,
        destinationMount: map['destinationMount'] as String,
        stageMount: map['stageMount'] as String,
        destinationFreeBytes: map['destinationFreeBytes'] as int,
        stageFreeBytes: map['stageFreeBytes'] as int);
  }

  /// The caller persists the intent before creating its stage. A resume requires
  /// the recorded inode, not merely a matching filename; uncommitted tail bytes
  /// are truncated only after that ownership check. Published recovery is read-only.
  Future<OwnedStorageSession> open(
      {required String destinationRoot,
      required String relativePath,
      required String stagePath,
      int durableOffset = 0,
      NativeFileIdentity? expectedIdentity,
      bool published = false}) async {
    if (durableOffset < 0 ||
        (expectedIdentity == null && (durableOffset != 0 || published))) {
      throw const OwnedStorageException('invalid_arguments');
    }
    final value = await _invoke('ownedOpen', {
      'destinationRoot': destinationRoot,
      'relativePath': relativePath,
      'stagePath': stagePath,
      'durableOffset': durableOffset,
      'mode': published
          ? 'published'
          : expectedIdentity == null
              ? 'create'
              : 'resume',
      if (expectedIdentity != null)
        'expectedIdentity': nativeIdentity(expectedIdentity),
    });
    final map = (value as Map).cast<String, Object?>();
    return OwnedStorageSession._(this, map['session'] as String,
        decodeIdentity(map['identity']), published);
  }

  Future<NativeFileIdentity?> inspect(
      {required String destinationRoot,
      required String relativePath,
      required String stagePath,
      bool published = false}) async {
    final result = await _invoke('ownedInspect', {
      'destinationRoot': destinationRoot,
      'relativePath': relativePath,
      'stagePath': stagePath,
      'published': published
    });
    return result == null ? null : decodeIdentity(result);
  }

  static Map<String, Object> nativeIdentity(NativeFileIdentity identity) => {
        'device': identity.volumeId,
        'inode': identity.fileId,
        'size': identity.sizeBytes,
        'modifiedSeconds': (identity.modifiedAt.toUtc().microsecondsSinceEpoch -
                identity.modifiedNanoseconds ~/ 1000) ~/
            1000000,
        'modifiedNanos': identity.modifiedNanoseconds,
      };

  static NativeFileIdentity decodeIdentity(Object? value) {
    final map = (value as Map).cast<String, Object?>();
    final nanos = map['modifiedNanos'] as int;
    return NativeFileIdentity(
        volumeId: map['device'] as String,
        fileId: map['inode'] as String,
        sizeBytes: map['size'] as int,
        modifiedAt: DateTime.fromMicrosecondsSinceEpoch(
            (map['modifiedSeconds'] as int) * 1000000 + nanos ~/ 1000,
            isUtc: true),
        modifiedNanoseconds: nanos);
  }
}

/// One pinned native file and its parent directories. Callers await every write;
/// there is no sink which could buffer an entire network response behind IO.
class OwnedStorageSession {
  final OwnedStorage _storage;
  final String id;
  final NativeFileIdentity openedIdentity;
  bool _published;
  bool _closing = false;
  Future<void>? _closeFuture;
  OwnedStorageSession._(
      this._storage, this.id, this.openedIdentity, this._published);

  void _requireOpen() {
    if (_closing) throw const OwnedStorageException('closed');
  }

  Future<void> write(int offset, Uint8List bytes) async {
    _requireOpen();
    if (_published || offset < 0 || bytes.length > OwnedStorage.maxChunkBytes) {
      throw const OwnedStorageException('invalid_arguments');
    }
    await _storage._invoke(
        'ownedWrite', {'session': id, 'offset': offset, 'bytes': bytes});
  }

  Future<Uint8List> read(int offset, int length) async {
    _requireOpen();
    if (offset < 0 || length < 0 || length > OwnedStorage.maxChunkBytes) {
      throw const OwnedStorageException('invalid_arguments');
    }
    return (await _storage._invoke(
            'ownedRead', {'session': id, 'offset': offset, 'length': length}))
        as Uint8List;
  }

  Stream<Uint8List> bytes(int size) async* {
    if (size < 0) throw const OwnedStorageException('invalid_arguments');
    var offset = 0;
    while (offset < size) {
      final remaining = size - offset;
      final chunk = await read(
          offset,
          remaining < OwnedStorage.maxChunkBytes
              ? remaining
              : OwnedStorage.maxChunkBytes);
      if (chunk.isEmpty) throw const OwnedStorageException('changed');
      offset += chunk.length;
      yield chunk;
    }
  }

  Future<NativeFileIdentity> checkpoint() async {
    _requireOpen();
    return OwnedStorage.decodeIdentity(
        await _storage._invoke('ownedCheckpoint', {'session': id}));
  }

  /// Caller must journal publishing intent and verified evidence beforehand.
  /// This no-clobber namespace operation alone never commits an installation.
  Future<NativeFileIdentity> publish(
      NativeFileIdentity verifiedIdentity) async {
    _requireOpen();
    if (_published) throw const OwnedStorageException('invalid_arguments');
    final result = await _storage._invoke('ownedPublish', {
      'session': id,
      'expectedIdentity': OwnedStorage.nativeIdentity(verifiedIdentity)
    });
    _published = true;
    return OwnedStorage.decodeIdentity(result);
  }

  Future<void> close() {
    _closing = true;
    return _closeFuture ??=
        _storage._invoke('ownedClose', {'session': id}).then((_) {});
  }

  /// For filesystems without no-replace rename, after the caller journals the
  /// publishing-copy intent. Only the verified private source can be copied;
  /// source bytes remain intact until the installed-state commit/owned cleanup.
  Future<OwnedStorageCopy> beginPublicationCopy(
      NativeFileIdentity verifiedSource,
      {int durableOffset = 0,
      NativeFileIdentity? destinationIdentity}) async {
    _requireOpen();
    if (_published ||
        durableOffset < 0 ||
        (destinationIdentity == null && durableOffset != 0)) {
      throw const OwnedStorageException('invalid_arguments');
    }
    final value = await _storage._invoke('ownedCopyOpen', {
      'session': id,
      'expectedIdentity': OwnedStorage.nativeIdentity(verifiedSource),
      'durableOffset': durableOffset,
      if (destinationIdentity != null)
        'destinationIdentity': OwnedStorage.nativeIdentity(destinationIdentity),
    });
    return OwnedStorageCopy._(
        this, OwnedStorage.decodeIdentity(value), durableOffset);
  }
}

/// An uncommitted destination copy, NOT an installation. The target is created
/// exclusively, so an existing file is never truncated. It may be visible to
/// external file browsers while publishing; R-Shop must use its journal, not
/// filename existence, to expose ready games. No network-data write API exists.
class OwnedStorageCopy {
  final OwnedStorageSession _source;
  final NativeFileIdentity openedIdentity;
  int _offset;
  final int _requiredPrefix;
  int _validatedPrefix = 0;
  bool _finished = false;
  OwnedStorageCopy._(this._source, this.openedIdentity, this._offset)
      : _requiredPrefix = _offset;
  int get copiedBytes => _offset;

  Future<Object?> _invoke(String method,
      [Map<String, Object?> args = const {}]) {
    _source._requireOpen();
    return _source._storage._invoke(method, {'session': _source.id, ...args});
  }

  Future<void> copyNext(int length) async {
    if (_finished || length < 1 || length > OwnedStorage.maxChunkBytes) {
      throw const OwnedStorageException('invalid_arguments');
    }
    _offset =
        (await _invoke('ownedCopyChunk', {'offset': _offset, 'length': length}))
            as int;
  }

  /// Stat alone cannot detect same-size edits on coarse-timestamp SD media.
  /// Recompare the recorded public prefix with the retained verified source
  /// before any resumed append. The native boundary enforces this gate too.
  Future<void> validateResumePrefix(
      {void Function()? checkCancellation}) async {
    while (_validatedPrefix < _requiredPrefix) {
      checkCancellation?.call();
      final remaining = _requiredPrefix - _validatedPrefix;
      final length = remaining < OwnedStorage.maxChunkBytes
          ? remaining
          : OwnedStorage.maxChunkBytes;
      _validatedPrefix = (await _invoke('ownedCopyValidatePrefix',
          {'offset': _validatedPrefix, 'length': length})) as int;
    }
    checkCancellation?.call();
  }

  Future<NativeFileIdentity> checkpoint() async =>
      OwnedStorage.decodeIdentity(await _invoke('ownedCopyCheckpoint'));

  Stream<Uint8List> bytes() async* {
    var offset = 0;
    final size = _offset;
    while (offset < size) {
      final remaining = size - offset;
      final length = remaining < OwnedStorage.maxChunkBytes
          ? remaining
          : OwnedStorage.maxChunkBytes;
      final chunk =
          (await _invoke('ownedCopyRead', {'offset': offset, 'length': length}))
              as Uint8List;
      if (chunk.length != length) throw const OwnedStorageException('changed');
      offset += chunk.length;
      yield chunk;
    }
  }

  /// Caller rehashes destination bytes against the trusted provider digests
  /// before this durability step, then commits the installation transaction.
  Future<NativeFileIdentity> finish(
      NativeFileIdentity verifiedDestination) async {
    final value = await _invoke('ownedCopyFinish',
        {'expectedIdentity': OwnedStorage.nativeIdentity(verifiedDestination)});
    _finished = true;
    return OwnedStorage.decodeIdentity(value);
  }

  Future<void> close() => _source.close();
}
