import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/library_identity.dart';
import '../../models/transfer_record.dart';
import '../installation_index.dart';
import '../owned_storage.dart';
import '../transfer_journal.dart';
import '../stage_retirement.dart';
import '../owned_replacement.dart';
import 'drive_api.dart';
import 'drive_authorization.dart';
import 'drive_media.dart';
import 'drive_verification.dart';

/// Coordinates exact journaled artifacts. Callers supply the selected source's
/// DriveDownloadBoundary.revalidate and DriveMediaApi.open, not a saved URL.
/// Each operation owns cancellation and joins all native/stream work on result.
class DriveTransferEngine {
  final TransferJournal journal;
  final OwnedStorage storage;
  final Future<void> Function(RemoteArtifact, CancelToken) revalidate;
  final Future<DriveMediaResponse> Function(RemoteArtifact, int, CancelToken)
      openMedia;
  final _active = <String, DriveTransferOperation>{};
  DriveTransferEngine(
      {required this.journal,
      required this.storage,
      required this.revalidate,
      required this.openMedia});
  DriveTransferOperation start(String transferId,
      {void Function(TransferRecord)? onCheckpoint}) {
    if (_active.containsKey(transferId)) {
      throw StateError('Transfer already active');
    }
    final operation = DriveTransferOperation._(this, transferId, onCheckpoint);
    _active[transferId] = operation;
    operation.result = operation._execute();
    return operation;
  }
}

class DriveTransferOperation {
  final DriveTransferEngine _engine;
  final String transferId;
  final _cancellation = CancelToken();
  final void Function(TransferRecord)? _onCheckpoint;
  late final Future<TransferRecord> result;
  TransferRecord? _record;
  OwnedStorageSession? _session;
  OwnedStorageCopy? _copy;
  StreamIterator<Uint8List>? _reader;
  Future<void>? _readerClose;
  bool _readerCloseFailed = false;
  bool _resourcesClosed = false;
  DriveTransferOperation._(this._engine, this.transferId, this._onCheckpoint);
  TransferRecord get record => _record!;

  /// Signal cancellation immediately, then wait for the actual stream, pending
  /// writes, publication receipt and durable checkpoint to drain. No sleep race.
  Future<TransferRecord> pause() {
    _cancellation.cancel();
    // Cancelling the native input is necessary even while waiting for its next
    // byte. The reader-close future is joined by the operation's finally block.
    unawaited(_closeReader());
    return result;
  }

  Future<void> _closeReader() =>
      _readerClose ??= Future<void>.sync(() => _reader?.cancel())
          .then<void>((_) {}, onError: (Object _, StackTrace __) {
        _readerCloseFailed = true;
      });

  void _checkCancellation() {
    if (_cancellation.isCancelled) {
      throw const DriveTransferException(DriveTransferIssue.cancelled);
    }
  }

  Future<void> _save(TransferRecord next) async {
    _record = await _engine.journal.save(next);
    _notifyCheckpoint();
  }

  // Observer errors cannot change durable transfer state. No stream buffer is
  // allocated for progress: observers see only the latest committed checkpoint.
  void _notifyCheckpoint() {
    final observer = _onCheckpoint;
    if (observer != null) Zone.current.runUnaryGuarded(observer, record);
  }

  Future<void> _state(TransferLifecycle state) =>
      _save(record.copyWith(lifecycle: state, clearErrorCode: true));

  Future<void> _stageCheckpoint() async {
    final identity = await _session!.checkpoint();
    await _save(record.copyWith(
        stageIdentity: identity, durableOffset: identity.sizeBytes));
  }

  Future<void> _copyCheckpoint(
      {bool confirmed = false, NativeFileIdentity? identity}) async {
    final current = record.publication!;
    final checkpoint = identity ?? await _copy!.checkpoint();
    await _save(record.copyWith(
        publication: TransferPublication(
            method: current.method,
            sourceIdentity: current.sourceIdentity,
            destinationIdentity: checkpoint,
            confirmed: confirmed || current.confirmed)));
  }

  Future<TransferRecord> _execute() async {
    try {
      final transferred = await _executeTransfer();
      _record = await retireCommittedStage(
          _engine.journal, _engine.storage, transferred,
          resourcesClosed: _resourcesClosed);
      _notifyCheckpoint();
      if (_resourcesClosed) {
        await retireReplacedInstallation(_engine.journal, _engine.storage, record);
      }
      return record;
    } finally {
      if (identical(_engine._active[transferId], this)) {
        _engine._active.remove(transferId);
      }
    }
  }

  Future<TransferRecord> _executeTransfer() async {
    try {
      _record = await _engine.journal.transfer(transferId);
      if (_record == null) throw StateError('Unknown transfer');
      _notifyCheckpoint();
      if (['.zip', '.7z', '.rar'].any(record.relativePath.toLowerCase().endsWith) &&
          !TransferRecord.supportsArchiveMapping(record.relativePath, record.archivePlatformId)) {
        throw const OwnedStorageException('unsupported_archive');
      }
      if (record.lifecycle == TransferLifecycle.completed) {
        final installation = await _engine.journal.installationForTarget(
            destinationRoot: record.destinationRoot,
            relativePath: record.relativePath);
        await InstallationIndex(_engine.journal, storage: _engine.storage)
            .requireInstallation(record, installation);
        if (record.archivePlatformId != null) {
          _session = await _open(published: true, identity: installation!.fileIdentity);
          await _validateArchive();
        }
        return record;
      }
      final verification = DriveVerification(record.artifact);
      _checkCancellation();
      await _engine.revalidate(record.artifact, _cancellation);
      _checkCancellation();

      final publication = record.publication;
      if (publication != null) {
        await _state(TransferLifecycle.publishing);
        await _recoverPublication(verification);
      } else {
        final plan = await _engine.storage.prepare(record.destinationRoot);
        if (record.destinationRoot != plan.destinationRoot ||
            record.stagePath != plan.stagePath(record.id)) {
          throw const OwnedStorageException('changed');
        }
        if (plan.stageFreeBytes <
            record.artifact.sizeBytes! - record.durableOffset) {
          throw const OwnedStorageException('out_of_space');
        }
        if (record.stageIdentity == null && record.durableOffset != 0) {
          throw const OwnedStorageException('changed');
        }
        // Full bytes with prior verification can resume verification without
        // weakening their immutable identity evidence or restarting the network.
        if (record.lifecycle != TransferLifecycle.verifying &&
            record.verifiedChecksums.isEmpty) {
          await _state(TransferLifecycle.transferring);
        } else {
          await _state(TransferLifecycle.verifying);
        }
        _session = await _open();
        if (record.stageIdentity == null) {
          await _stageCheckpoint();
        } else {
          // The owned native resume may trim a non-durable private tail. Its
          // returned timestamp is rebound by the explicit journal operation,
          // never by weakening ordinary checkpoint identity validation.
          _record = await _engine.journal
              .resumeStageCheckpoint(record, _session!.openedIdentity);
          _notifyCheckpoint();
        }
        _checkCancellation();
        if (record.durableOffset < record.artifact.sizeBytes!) await _receive();
        await _state(TransferLifecycle.verifying);
        final hashes = await verification.verifyBytes(
            _session!.bytes(record.artifact.sizeBytes!),
            cancellation: _cancellation);
        await _validateArchive();
        _checkCancellation();
        await _engine.revalidate(record.artifact, _cancellation);
        _checkCancellation();
        // Verification must describe the same file as the pre-hash checkpoint.
        final identity = await _session!.checkpoint();
        if (!identity.matches(record.stageIdentity!)) {
          throw const OwnedStorageException('changed');
        }
        await _save(record.copyWith(verifiedChecksums: hashes));
        await _save(record.copyWith(
            lifecycle: TransferLifecycle.publishing,
            publication: TransferPublication(
                method: PublicationMethod.rename, sourceIdentity: identity)));
        _checkCancellation();
        await _publish(verification);
      }
      _checkCancellation();
      // A source which changed during local verification/publication is never
      // installed. Confirm the selected subtree/version again immediately here.
      await _engine.revalidate(record.artifact, _cancellation);
      _checkCancellation();
      final destination = record.publication!.destinationIdentity!;
      final observed = await _engine.storage.inspect(
          destinationRoot: record.destinationRoot,
          relativePath: record.relativePath,
          stagePath: record.stagePath,
          published: true);
      if (observed == null || !observed.matches(destination)) {
        throw const OwnedStorageException('changed');
      }
      _checkCancellation();
      final dependencies = await _engine.journal.bundleInstallations(record);
      for (final member in dependencies) {
        _checkCancellation();
        await _engine.revalidate(member.artifact, _cancellation);
        await InstallationIndex(_engine.journal, storage: _engine.storage)
            .requireInstallation((await _engine.journal.transfer(member.transferId))!,
                member, bundleOwner: record.id);
      }
      if (record.replacesInstallation case final old?) {
        final previous = await _engine.journal.transfer(old.transferId);
        if (previous == null) throw const OwnedStorageException('changed');
        await InstallationIndex(_engine.journal, storage: _engine.storage)
            .requireInstallation(previous, old);
      }
      _record = await _engine.journal.complete(
          record,
          InstalledArtifact(
              id: record.id,
              transferId: record.id,
              artifact: record.artifact,
              destinationRoot: record.destinationRoot,
              relativePath: record.relativePath,
              sizeBytes: record.artifact.sizeBytes!,
              verifiedChecksums: record.verifiedChecksums,
              dependencies: dependencies,
              fileIdentity: destination),
          checkCancellation: _checkCancellation);
      _notifyCheckpoint();
      return record;
    } catch (error) {
      if (_record == null || record.lifecycle == TransferLifecycle.completed) {
        rethrow;
      }
      // Persist only after the current writer is done. A failed checkpoint is a
      // real failure, never a successful pause acknowledgement.
      var problem = error;
      try {
        if (_copy != null && record.publication?.confirmed != true) {
          await _copyCheckpoint();
        } else if (_session != null && record.publication == null) {
          await _stageCheckpoint();
        }
      } catch (_) {
        problem = const OwnedStorageException('io_error');
      }
      final current = await _engine.journal.transfer(transferId);
      if (current?.revision != record.revision) rethrow;
      final paused = (problem is DriveTransferException &&
              problem.issue == DriveTransferIssue.cancelled) ||
          (problem is DriveApiException &&
              problem.issue == DriveApiIssue.cancelled) ||
          (problem is DriveAuthorizationException &&
              problem.issue == DriveAuthorizationIssue.cancelled &&
              _cancellation.isCancelled);
      final auth = problem is DriveAuthorizationException;
      await _save(record.copyWith(
          lifecycle: paused
              ? TransferLifecycle.paused
              : auth
                  ? TransferLifecycle.awaitingAuthorization
                  : TransferLifecycle.failed,
          errorCode: paused ? 'cancelled' : _code(problem)));
      return record;
    } finally {
      try {
        try {
          await _closeReader();
        } finally {
          await _session?.close();
        }
        _resourcesClosed = true;
      } catch (_) {
        // Never unlink the private recovery copy on an uncertain close. An
        // already committed installation remains completed; the outer layer
        // records pending cleanup, and native replay refuses active sessions.
        // Precommit shutdown failures still propagate as failures.
        if (_record?.lifecycle != TransferLifecycle.completed) rethrow;
      }
    }
  }

  Future<OwnedStorageSession> _open(
          {bool published = false, NativeFileIdentity? identity}) =>
      _engine.storage.open(
          destinationRoot: record.destinationRoot,
          relativePath: record.relativePath,
          stagePath: record.stagePath,
          durableOffset: record.durableOffset,
          expectedIdentity: identity ?? record.stageIdentity,
          published: published);

  Future<void> _receive() async {
    _checkCancellation();
    final response = await _engine.openMedia(
        record.artifact, record.durableOffset, _cancellation);
    _reader = StreamIterator(response.bytes);
    _readerClose = null;
    _readerCloseFailed = false;
    var offset = record.durableOffset;
    try {
      if (response.offset != offset ||
          response.total != record.artifact.sizeBytes ||
          response.length != response.total - offset) {
        throw const DriveTransferException(DriveTransferIssue.invalidRange);
      }
      while (true) {
        _checkCancellation();
        if (!await _reader!.moveNext()) break;
        _checkCancellation();
        final chunk = _reader!.current;
        if (chunk.length > DriveMediaApi.maxChunkBytes ||
            offset + chunk.length > response.total) {
          throw const DriveTransferException(
              DriveTransferIssue.invalidResponse);
        }
        for (var start = 0; start < chunk.length;) {
          _checkCancellation();
          final end = start + OwnedStorage.maxChunkBytes < chunk.length
              ? start + OwnedStorage.maxChunkBytes
              : chunk.length;
          await _session!
              .write(offset, Uint8List.sublistView(chunk, start, end));
          offset += end - start;
          start = end;
        }
        if (offset - record.durableOffset >= DriveMediaApi.maxChunkBytes) {
          await _stageCheckpoint();
        }
      }
      _checkCancellation();
      if (offset != response.total) {
        throw const DriveTransferException(DriveTransferIssue.truncated);
      }
      await _stageCheckpoint();
    } finally {
      await _closeReader();
      if (_readerCloseFailed) {
        throw const DriveTransferException(DriveTransferIssue.unavailable);
      }
    }
  }

  Future<void> _recoverPublication(DriveVerification verification) async {
    final intent = record.publication!;
    final stage = await _engine.storage.inspect(
        destinationRoot: record.destinationRoot,
        relativePath: record.relativePath,
        stagePath: record.stagePath);
    if (intent.method == PublicationMethod.rename && stage == null) {
      // A crash may occur after rename but before storing its receipt. Only the
      // exact pre-recorded source object and full checksum authorize recovery.
      _session = await _open(published: true, identity: intent.sourceIdentity);
      await _verifyRecorded(
          verification, _session!.bytes(record.durableOffset));
      await _validateArchive();
      final identity = await _session!.checkpoint();
      if (!identity.matches(intent.sourceIdentity)) {
        throw const OwnedStorageException('changed');
      }
      if (!intent.confirmed) {
        await _copyCheckpoint(confirmed: true, identity: identity);
      }
      return;
    }
    if (stage == null || !stage.matches(intent.sourceIdentity)) {
      throw const OwnedStorageException('changed');
    }
    _session = await _open();
    await _verifyRecorded(verification, _session!.bytes(record.durableOffset));
    await _validateArchive();
    final identity = await _session!.checkpoint();
    if (!identity.matches(intent.sourceIdentity)) {
      throw const OwnedStorageException('changed');
    }
    _checkCancellation();
    await _publish(verification);
  }

  Future<void> _validateArchive() async {
    if (record.archivePlatformId == 'gamegear') {
      _checkCancellation();
      await _session!.validateGameGearZip();
      _checkCancellation();
    } else if (record.archivePlatformId == 'n64') {
      _checkCancellation();
      await _session!.validateN64Archive(record.relativePath);
      _checkCancellation();
    } else if (record.archivePlatformId == 'nes') {
      _checkCancellation();
      await _session!.validateNesSevenZip();
      _checkCancellation();
    } else if (const {'gb', 'gbc', 'gba'}.contains(record.archivePlatformId)) {
      _checkCancellation();
      await _session!.validateGameBoySevenZip(record.archivePlatformId!);
      _checkCancellation();
    }
  }

  Future<void> _publish(DriveVerification verification) async {
    if (record.publication!.method == PublicationMethod.rename) {
      try {
        final destination =
            await _session!.publish(record.publication!.sourceIdentity);
        await _copyCheckpoint(confirmed: true, identity: destination);
        return;
      } on OwnedStorageException catch (error) {
        if (error.code != 'unsupported' && error.code != 'cross_volume') {
          rethrow;
        }
        // Only a definitive unsupported/cross-mount result authorizes this new
        // intent. General IO failures may have already renamed the file.
        await _save(record.copyWith(
            publication: TransferPublication(
                method: PublicationMethod.copy,
                sourceIdentity: record.publication!.sourceIdentity)));
      }
    }
    _checkCancellation();
    final intent = record.publication!;
    final plan = await _engine.storage.prepare(record.destinationRoot);
    if (plan.destinationFreeBytes <
        record.durableOffset - intent.copiedOffset) {
      throw const OwnedStorageException('out_of_space');
    }
    _copy = await _session!.beginPublicationCopy(intent.sourceIdentity,
        durableOffset: intent.copiedOffset,
        destinationIdentity: intent.destinationIdentity);
    if (intent.destinationIdentity == null) {
      await _copyCheckpoint(identity: _copy!.openedIdentity);
    }
    await _copy!.validateResumePrefix(checkCancellation: _checkCancellation);
    var checkpoint = record.publication!.copiedOffset;
    while (_copy!.copiedBytes < record.durableOffset) {
      _checkCancellation();
      final remaining = record.durableOffset - _copy!.copiedBytes;
      await _copy!.copyNext(remaining < OwnedStorage.maxChunkBytes
          ? remaining
          : OwnedStorage.maxChunkBytes);
      if (_copy!.copiedBytes - checkpoint >= DriveMediaApi.maxChunkBytes) {
        await _copyCheckpoint();
        checkpoint = _copy!.copiedBytes;
      }
    }
    await _copyCheckpoint();
    _checkCancellation();
    await _verifyRecorded(verification, _copy!.bytes());
    final destination =
        await _copy!.finish(record.publication!.destinationIdentity!);
    if (!record.publication!.confirmed) {
      await _copyCheckpoint(confirmed: true, identity: destination);
    }
  }

  Future<void> _verifyRecorded(
      DriveVerification verification, Stream<Uint8List> bytes) async {
    final actual =
        await verification.verifyBytes(bytes, cancellation: _cancellation);
    if (actual.length != record.verifiedChecksums.length ||
        actual.entries.any((entry) =>
            record.verifiedChecksums[entry.key]?.toLowerCase() !=
            entry.value)) {
      throw const DriveTransferException(DriveTransferIssue.checksumMismatch);
    }
  }

  static String _code(Object error) {
    final value = switch (error) {
      DriveTransferException() => error.issue.name,
      DriveAuthorizationException() => 'authorization_${error.issue.name}',
      DriveApiException() => 'api_${error.issue.name}',
      OwnedStorageException() => 'storage_${error.code}',
      _ => 'persistence_error',
    };
    return value.replaceAllMapped(
        RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
  }
}
