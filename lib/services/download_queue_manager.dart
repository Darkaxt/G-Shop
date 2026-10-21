import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/config/app_config.dart';
import '../models/config/provider_config.dart';
import '../models/download_item.dart';
import '../models/game_item.dart';
import '../models/system_model.dart';
import '../models/transfer_record.dart';
import 'drive/drive_runtime.dart';
import 'drive/drive_transfer_engine.dart';
import 'drive/drive_authorization.dart';
import 'drive/drive_media.dart';
import 'drive/drive_bundle.dart';
import 'owned_storage.dart';
import 'download_foreground_service.dart';
import 'storage_service.dart';

class DownloadQueueState {
  final List<DownloadItem> queue;
  final int maxConcurrent;

  const DownloadQueueState({
    this.queue = const [],
    this.maxConcurrent = 2,
  });

  List<DownloadItem> get activeDownloads =>
      queue.where((item) => item.isActive).toList();

  List<DownloadItem> get queuedItems =>
      queue.where((item) => item.status == DownloadStatus.queued).toList();

  List<DownloadItem> get completedItems =>
      queue.where((item) => item.isComplete).toList();

  List<DownloadItem> get failedItems =>
      queue.where((item) => item.isFailed).toList();

  List<DownloadItem> get recentItems {
    final unfinished = queue.where((item) => !item.isFinished).toList();
    final finished = queue.where((item) => item.isFinished).toList();
    return [...unfinished, ...finished];
  }

  int get activeCount => activeDownloads.length;

  int get queuedCount => queuedItems.length;

  int get totalCount => queue.length;

  int get finishedCount => completedItems.length + failedItems.length;

  bool get hasActiveDownloads => activeDownloads.isNotEmpty;

  bool get hasQueuedItems => queuedItems.isNotEmpty;

  bool get isEmpty => queue.isEmpty;

  bool canStartNewDownload() => activeCount < maxConcurrent;

  DownloadItem? getDownloadById(String id) {
    for (final item in queue) {
      if (item.id == id) return item;
    }
    return null;
  }

  DownloadQueueState copyWith({
    List<DownloadItem>? queue,
    int? maxConcurrent,
  }) {
    return DownloadQueueState(
      queue: queue ?? this.queue,
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
    );
  }
}

class DownloadQueueManager extends ChangeNotifier {
  static const int _maxQueueSize = 100;

  DownloadQueueState _state = const DownloadQueueState();
  DownloadQueueState get state => _state;
  bool _disposed = false;
  bool _isProcessingQueue = false;
  bool _closing = false;
  Future<void>? _closeFuture;
  Future<StageRetirementRecoveryReport>? _stageRetirementRecovery;
  Future<OwnedRemovalRecoveryReport>? _ownedRemovalRecovery;
  final Map<String, _DriveQueueAttempt> _driveAttempts = {};
  final DriveRuntime _driveRuntime;

  final StorageService _storage;

  /// Called after a download completes successfully. Used for post-download
  /// processing like RA hash verification.
  FutureOr<void> Function(DownloadItem item)? onItemCompleted;

  DownloadQueueManager(this._storage, {DriveRuntime? driveRuntime})
      : _driveRuntime = driveRuntime ?? DriveRuntime.instance {
    final maxConcurrent = _storage.getMaxConcurrentDownloads();
    _state = _state.copyWith(maxConcurrent: maxConcurrent);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void setMaxConcurrent(int value) {
    final clamped = value.clamp(1, 3);
    _state = _state.copyWith(maxConcurrent: clamped);
    _storage.setMaxConcurrentDownloads(clamped);
    _safeNotify();
    _processQueue();
  }

  String addToQueue(GameItem game, SystemModel system, String targetFolder,
      {bool autoExtract = false}) {
    if (!game.hasDownloadSource)
      throw UnsupportedError('Choose a Google Drive game to download');
    final id = idFor(game, system);
    if (_closing || _disposed || _driveAttempts.containsKey(id)) return id;

    final existing = _state.getDownloadById(id);
    if (existing != null && !existing.isFinished) {
      return id;
    }

    if (existing == null && _state.queue.length >= _maxQueueSize) {
      // Auto-clear finished items before rejecting
      final unfinished =
          _state.queue.where((item) => !item.isFinished).toList();
      if (unfinished.length < _state.queue.length) {
        _state = _state.copyWith(queue: unfinished);
        _safeNotify();
        _persistQueue();
      }
      if (_state.queue.length >= _maxQueueSize) {
        debugPrint(
            'DownloadQueue: queue full ($_maxQueueSize items), rejecting');
        return id;
      }
    }

    final item = DownloadItem(
      id: id,
      game: game,
      system: system,
      targetFolder: targetFolder,
      autoExtract: autoExtract,
    );

    final newQueue = List<DownloadItem>.from(_state.queue);

    if (existing != null) {
      newQueue.removeWhere((i) => i.id == id);
    }

    newQueue.insert(0, item);
    _state = _state.copyWith(queue: newQueue);
    _safeNotify();
    _persistQueue();

    _processQueue();

    return id;
  }

  Future<void> cancelDownload(String id) async {
    final item = _state.getDownloadById(id);
    if (item == null) return;
    if (_isDrive(item)) {
      // Drive cancellation retains exact journaled bytes. Removing a queue row
      // is distinct from deleting an owned partial or installed ROM.
      await pauseDownload(id);
      return;
    }

    _updateItem(id, status: DownloadStatus.cancelled);
    _persistQueue();
    _stopForegroundServiceIfIdle();
    _processQueue();
  }

  Future<void> removeDownload(String id) async {
    final item = _state.getDownloadById(id);
    if (item == null) return;

    if (item.isActive) {
      await cancelDownload(id);
    }

    final newQueue = List<DownloadItem>.from(_state.queue)
      ..removeWhere((i) => i.id == id);
    _state = _state.copyWith(queue: newQueue);
    _safeNotify();
    _persistQueue();
  }

  void clearCompleted() {
    final newQueue = _state.queue.where((item) => !item.isFinished).toList();
    _state = _state.copyWith(queue: newQueue);
    _safeNotify();
    _persistQueue();
  }

  void retryDownload(String id) {
    final item = _state.getDownloadById(id);
    if (item == null ||
        item.isActive ||
        _driveAttempts.containsKey(id) ||
        _closing) {
      return;
    }

    _updateItem(
      id,
      status: DownloadStatus.queued,
      progress: 0,
      receivedBytes: 0,
      retryCount: 0,
      clearError: true,
      clearSpeed: true,
    );

    _processQueue();
  }

  static bool _isDrive(DownloadItem item) =>
      item.game.remoteArtifact?.id.providerId == 'drive' &&
      item.game.providerConfig?.type == ProviderType.drive;

  Future<void> pauseDownload(String id) async {
    final item = _state.getDownloadById(id);
    if (item == null || !_isDrive(item) || item.isComplete) return;
    final attempt = _driveAttempts[id];
    if (attempt != null) {
      attempt.pauseRequested = true;
      attempt.planningCancellation.cancel();
      // result already has an observer in _runDrive. Keep the slot occupied
      // until that run has joined the returned operation and all native work.
      attempt.operation?.pause();
      await attempt.settled;
    } else {
      _updateItem(id, status: DownloadStatus.paused, clearSpeed: true);
      await _persistQueue();
      _stopForegroundServiceIfIdle();
    }
  }

  /// Reorders pending entries only; active operations keep their attempt IDs.
  void moveQueued(String id, int queuedIndex) {
    final pending = _state.queuedItems;
    final old = pending.indexWhere((i) => i.id == id);
    if (old < 0 || queuedIndex < 0 || queuedIndex >= pending.length) return;
    pending.insert(queuedIndex, pending.removeAt(old));
    var next = 0;
    _state = _state.copyWith(queue: [
      for (final item in _state.queue)
        if (item.status == DownloadStatus.queued) pending[next++] else item
    ]);
    _persistQueue();
    _safeNotify();
  }

  void _processQueue() {
    if (_disposed || _closing || _isProcessingQueue) return;
    if (!_state.canStartNewDownload()) return;

    _isProcessingQueue = true;
    try {
      final queuedItems = _state.queuedItems;
      if (queuedItems.isEmpty) return;

      for (final item in queuedItems) {
        if (!_state.canStartNewDownload()) break;
        // Re-check item is still queued before starting
        final current = _state.getDownloadById(item.id);
        if (current == null || current.status != DownloadStatus.queued) {
          continue;
        }
        _startDownload(item);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _startDownload(DownloadItem item) async {
    if (_closing || _disposed) return;
    // Exact artifacts require S3's verified transfer/publication contract.
    // In particular, filename existence must never imply their completion.
    if (_isDrive(item)) {
      final attempt = _DriveQueueAttempt();
      _driveAttempts[item.id] = attempt;
      _updateItem(item.id,
          status: DownloadStatus.downloading, clearError: true);
      _updateForegroundService();
      _runDrive(item, attempt)
          .then(attempt.join.complete, onError: attempt.join.completeError);
      await attempt.settled;
      return;
    }
    _updateItem(item.id,
        status: DownloadStatus.error,
        error: 'This source is no longer supported. Connect Google Drive.');
    await _persistQueue();
    _processQueue();
  }

  bool _ownsDrive(String id, _DriveQueueAttempt attempt) =>
      identical(_driveAttempts[id], attempt);

  void _driveCheckpoint(
      String id, _DriveQueueAttempt attempt, TransferRecord record,
      {bool terminal = false,
      String? maintenanceWarning,
      String? parentTransferId,
      int precedingBytes = 0,
      int? bundleBytes}) {
    if (!_ownsDrive(id, attempt)) return;
    if (!terminal &&
        (record.lifecycle == TransferLifecycle.completed ||
            record.lifecycle == TransferLifecycle.paused ||
            record.lifecycle == TransferLifecycle.awaitingAuthorization ||
            record.lifecycle == TransferLifecycle.failed)) {
      return;
    }
    final status = switch (record.lifecycle) {
      TransferLifecycle.queued => DownloadStatus.downloading,
      TransferLifecycle.transferring => DownloadStatus.downloading,
      TransferLifecycle.verifying => DownloadStatus.verifying,
      TransferLifecycle.publishing => DownloadStatus.publishing,
      TransferLifecycle.paused => DownloadStatus.paused,
      TransferLifecycle.awaitingAuthorization =>
        DownloadStatus.awaitingAuthorization,
      TransferLifecycle.completed => DownloadStatus.completed,
      TransferLifecycle.failed => DownloadStatus.error,
    };
    final total = bundleBytes ?? record.artifact.sizeBytes;
    final received = precedingBytes + record.durableOffset;
    _updateItem(id,
        status: status,
        transferId: parentTransferId ?? record.id,
        receivedBytes: received,
        totalBytes: total,
        progress: total != null && total > 0 ? received / total : 0,
        error: record.errorCode ?? maintenanceWarning,
        clearError: record.errorCode == null && maintenanceWarning == null,
        clearSpeed: status != DownloadStatus.downloading);
    _throttledNotificationUpdate();
  }

  Future<void> _runDrive(DownloadItem item, _DriveQueueAttempt attempt) async {
    try {
      // Queue intent must be durable before reserving a native path or starting
      // payload IO. Reservation IDs are deterministic across this crash window.
      await _persistQueue();
      if (attempt.pauseRequested || _closing) {
        _updateItem(item.id, status: DownloadStatus.paused);
        return;
      }
      final artifact = item.game.remoteArtifact;
      final config = item.game.providerConfig;
      final extension = item.game.filename.toLowerCase();
      final bundle = BundleReferences.isManifest(extension);
      final supportsPlaylist = item.system.romExtensions.contains('.cue');
      final mappedArchive = TransferRecord.supportsArchiveMapping(
          item.game.filename, item.system.id);
      if (artifact == null ||
          config == null ||
          item.game.isFolder ||
          !(mappedArchive ||
              item.system.romExtensions.any(extension.endsWith) ||
              (supportsPlaylist && extension.endsWith('.m3u'))) ||
          (!mappedArchive && ['.zip', '.rar', '.7z'].any(extension.endsWith))) {
        throw const DriveTransferException(DriveTransferIssue.invalidSource);
      }
      var record = bundle
          ? await _driveRuntime.reserveBundle(
              config: config,
              artifact: artifact,
              destinationRoot: item.targetFolder,
              supportedExtensions: {
                ...item.system.romExtensions,
                ...?item.system.multiFileExtensions
              },
              cancellation: attempt.planningCancellation,
              transferId: item.transferId)
          : await _driveRuntime.reserveTransfer(
              config: config,
              artifact: artifact,
              destinationRoot: item.targetFolder,
              relativePath: item.game.filename,
              archivePlatformId: mappedArchive ? item.system.id : null);
      if (item.transferId != null && item.transferId != record.id) {
        throw const OwnedStorageException('changed');
      }
      _updateItem(item.id, transferId: record.id);
      await _persistQueue();
      var precedingBytes = 0;
      final bundleBytes = record.bundleMembers.isEmpty
          ? null
          : record.artifact.sizeBytes! +
              record.bundleMembers.fold<int>(
                  0, (sum, member) => sum + member.artifact.sizeBytes!);
      if (record.lifecycle != TransferLifecycle.completed) {
        for (final member in record.bundleMembers) {
          if (attempt.pauseRequested || _closing) {
            _updateItem(item.id, status: DownloadStatus.paused);
            return;
          }
          var child = await _driveRuntime.reserveBundleMember(record, member);
          if (child.lifecycle == TransferLifecycle.completed) {
            await _driveRuntime.requireInstalledTransfer(child,
                bundleOwner: record.id);
            child = await _driveRuntime.finishRetainedStage(child);
          } else {
            final base = precedingBytes;
            final operation = await _driveRuntime.startTransfer(
                config: config,
                transferId: child.id,
                onCheckpoint: (value) => _driveCheckpoint(
                    item.id, attempt, value,
                    parentTransferId: record.id,
                    precedingBytes: base,
                    bundleBytes: bundleBytes));
            attempt.operation = operation;
            if (attempt.pauseRequested || _closing) operation.pause();
            child = await operation.result;
          }
          if (child.lifecycle != TransferLifecycle.completed) {
            _driveCheckpoint(item.id, attempt, child,
                terminal: true,
                parentTransferId: record.id,
                precedingBytes: precedingBytes,
                bundleBytes: bundleBytes);
            return;
          }
          precedingBytes += child.artifact.sizeBytes!;
        }
      } else {
        precedingBytes = record.bundleMembers
            .fold<int>(0, (sum, member) => sum + member.artifact.sizeBytes!);
      }
      if (record.lifecycle == TransferLifecycle.completed) {
        await _driveRuntime.requireInstalledTransfer(record);
        record = await _driveRuntime.finishRetainedStage(record);
        await _driveRuntime.finishReplacement(record);
      } else if (attempt.pauseRequested || _closing) {
        if (record.lifecycle != TransferLifecycle.completed) {
          record = await _driveRuntime.journal
              .save(record.copyWith(lifecycle: TransferLifecycle.paused));
        }
      } else {
        final operation = await _driveRuntime.startTransfer(
            config: config,
            transferId: record.id,
            onCheckpoint: (record) => _driveCheckpoint(item.id, attempt, record,
                precedingBytes: precedingBytes, bundleBytes: bundleBytes));
        attempt.operation = operation;
        if (attempt.pauseRequested || _closing) operation.pause();
        record = await operation.result;
      }
      String? warning;
      if (record.replacesInstallation != null &&
          record.lifecycle == TransferLifecycle.completed) {
        try {
          final issue = await _driveRuntime.journal.replacementIssue(record.id);
          if (issue != null) warning = 'Previous version preserved: $issue';
        } catch (_) {
          warning = 'Replacement cleanup status unavailable';
        }
      }
      if (!_ownsDrive(item.id, attempt)) return;
      _driveCheckpoint(item.id, attempt, record,
          terminal: true,
          maintenanceWarning: warning,
          precedingBytes: precedingBytes,
          bundleBytes: bundleBytes);
      if (record.lifecycle == TransferLifecycle.completed && !_disposed) {
        final completedItem = item.copyWith(
            status: DownloadStatus.completed,
            transferId: record.id,
            progress: 1,
            receivedBytes: precedingBytes + record.durableOffset,
            totalBytes: bundleBytes ?? record.artifact.sizeBytes,
            error: warning,
            clearError: warning == null,
            clearSpeed: true);
        final observer = onItemCompleted;
        if (observer != null) {
          try {
            await observer(completedItem);
          } catch (error, stack) {
            Zone.current.handleUncaughtError(error, stack);
          }
        }
      }
    } catch (error) {
      if (_ownsDrive(item.id, attempt)) {
        final auth = error is DriveAuthorizationException;
        final needsAuthorization =
            auth && error.issue != DriveAuthorizationIssue.unavailable;
        final cancelled = attempt.pauseRequested ||
            _closing ||
            (error is DriveTransferException &&
                error.issue == DriveTransferIssue.cancelled);
        _updateItem(item.id,
            status: cancelled
                ? DownloadStatus.paused
                : needsAuthorization
                    ? DownloadStatus.awaitingAuthorization
                    : DownloadStatus.error,
            error: cancelled
                ? null
                : error is BundleLayoutException
                    ? 'bundle_${error.code}'
                    : error is DriveTransferException
                        ? 'transfer_${error.issue.name}'
                        : error is OwnedStorageException
                            ? 'storage_${error.code}'
                            : auth
                                ? 'auth_${error.issue.name}'
                                : 'transfer_unavailable',
            clearError: cancelled,
            clearSpeed: true);
      }
    } finally {
      if (_ownsDrive(item.id, attempt)) {
        _driveAttempts.remove(item.id);
        try {
          await _persistQueue();
        } catch (_) {/* Error already observed. */}
        _stopForegroundServiceIfIdle();
        _processQueue();
      }
    }
  }

  void _updateItem(
    String id, {
    DownloadStatus? status,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    double? downloadSpeed,
    String? error,
    bool clearError = false,
    bool clearSpeed = false,
    int? retryCount,
    String? tempFilePath,
    bool clearTempFilePath = false,
    String? transferId,
  }) {
    final newQueue = _state.queue.map((item) {
      if (item.id == id) {
        return item.copyWith(
          status: status,
          progress: progress,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          downloadSpeed: downloadSpeed,
          error: error,
          clearError: clearError,
          clearSpeed: clearSpeed,
          retryCount: retryCount,
          tempFilePath: tempFilePath,
          clearTempFilePath: clearTempFilePath,
          transferId: transferId,
        );
      }
      return item;
    }).toList();

    _state = _state.copyWith(queue: newQueue);
    _safeNotify();
  }

  // --- Foreground service helpers ---

  Timer? _notificationThrottle;

  void _updateForegroundService() {
    DownloadForegroundService.startIfNeeded(
      activeCount: _state.activeCount,
      queuedCount: _state.queuedCount,
    );
  }

  void _throttledNotificationUpdate() {
    if (_notificationThrottle?.isActive ?? false) return;
    _notificationThrottle = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
      final active = _state.activeDownloads;
      String? detail;
      if (active.length == 1) {
        detail = active.first.displayText;
      }
      DownloadForegroundService.updateProgress(
        activeCount: _state.activeCount,
        queuedCount: _state.queuedCount,
        progressDetail: detail,
      );
    });
  }

  void _stopForegroundServiceIfIdle() {
    // Check after current state update: any active or queued left?
    if (!_state.hasActiveDownloads && !_state.hasQueuedItems) {
      debugPrint(
          'DownloadQueue: no active/queued items, stopping foreground service');
      _notificationThrottle?.cancel();
      DownloadForegroundService.stop().catchError((e) {
        debugPrint('DownloadQueue: foreground service stop error: $e');
      });
    }
  }

  static String idFor(GameItem game, SystemModel system) {
    if (game.remoteArtifact != null) {
      return 'artifact:${jsonEncode([system.id, game.remoteArtifact!.id.key])}';
    }
    return '${system.name}_${game.filename}';
  }

  // --- Queue Persistence ---

  Future<void> _persistence = Future.value();

  Future<void> _persistQueue() {
    final persistable = _state.queue
        .where((item) =>
            (_isDrive(item) && !item.isComplete) ||
            item.status == DownloadStatus.queued ||
            item.status == DownloadStatus.error)
        .map((item) => item.toJson())
        .toList();
    final snapshot = jsonEncode(persistable);
    final write = _persistence.then((_) => persistable.isEmpty
        ? _storage.clearDownloadQueue()
        : _storage.setDownloadQueue(snapshot));
    // Observe fire-and-forget legacy callers immediately; Drive awaits the
    // original future and cannot begin after a failed intent write.
    _persistence = write.then<void>((_) {}, onError: (Object _, StackTrace __) {
      debugPrint('DownloadQueue: queue persistence failed');
    });
    return write;
  }

  Future<StageRetirementRecoveryReport> recoverPendingStageRetirements() =>
      _stageRetirementRecovery ??= _driveRuntime
          .recoverPendingStageRetirements(
              shouldContinue: () => !_closing && !_disposed)
          .then((report) {
        if (report.pending > 0 || report.issues.isNotEmpty) {
          debugPrint('Stage retirement recovery: pending=${report.pending}, '
              'issues=${report.issues}');
        }
        return report;
      });

  Future<OwnedRemovalRecoveryReport> recoverPendingRemovals() =>
      _ownedRemovalRecovery ??= recoverPendingStageRetirements()
          .then((_) => _driveRuntime.recoverPendingReplacements(
              shouldContinue: () => !_closing && !_disposed))
          .then((_) => _driveRuntime.recoverPendingRemovals(
              shouldContinue: () => !_closing && !_disposed))
          .then((report) {
        if (report.pending > 0 || report.issues.isNotEmpty) {
          debugPrint('Owned removal recovery: pending=${report.pending}, '
              'issues=${report.issues}');
        }
        return report;
      });

  void restoreQueue(List<SystemModel> systems, {AppConfig? appConfig}) {
    if (_closing || _disposed) return;
    unawaited(recoverPendingRemovals());
    final json = _storage.getDownloadQueue();
    if (json == null) return;

    try {
      final List<dynamic> list = jsonDecode(json) as List<dynamic>;
      final systemMapById = {for (final s in systems) s.id: s};
      // Legacy fallback: older persisted queues used system.name
      final systemMapByName = {for (final s in systems) s.name: s};

      final restored = <DownloadItem>[];
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final systemId = map['systemId'] as String?;
        final systemName = map['systemName'] as String?;
        final system = (systemId != null ? systemMapById[systemId] : null) ??
            (systemName != null ? systemMapByName[systemName] : null);
        if (system == null) {
          debugPrint('DownloadQueue: skipping restore item with unknown system '
              '(id=$systemId, name=$systemName)');
          continue;
        }

        final downloadItem = DownloadItem.fromJson(map, system);
        // Re-inject auth credentials from AppConfig (stripped during persist)
        final restoredItem = _rehydrateAuth(downloadItem, appConfig);

        // Interrupted Drive attempts require explicit resume; their journal,
        // not preference progress, decides verification/publication recovery.
        if (_isDrive(restoredItem)) {
          restored.add(restoredItem.copyWith(
              status: restoredItem.isActive
                  ? DownloadStatus.paused
                  : restoredItem.status,
              clearSpeed: true));
        } else {
          restored.add(restoredItem.isComplete
              ? restoredItem
              : restoredItem.copyWith(
                  status: DownloadStatus.error,
                  error:
                      'This source is no longer supported. Connect Google Drive.',
                  clearSpeed: true,
                ));
        }
      }

      if (restored.isNotEmpty) {
        final newQueue = List<DownloadItem>.from(_state.queue)
          ..addAll(restored);
        _state = _state.copyWith(queue: newQueue);
        _safeNotify();
        _processQueue();
      }
    } catch (e) {
      debugPrint('DownloadQueue: failed to restore queue (clearing): $e');
      _storage.clearDownloadQueue();
    }
  }

  /// Re-injects auth credentials from AppConfig into a restored DownloadItem.
  /// The persisted queue strips auth via toJsonWithoutAuth() — this matches
  /// the item's provider back to the current AppConfig and restores auth.
  DownloadItem _rehydrateAuth(DownloadItem item, AppConfig? appConfig) {
    if (appConfig == null) return item;
    final pc = item.game.providerConfig;
    if (pc == null || pc.auth != null) return item;

    final systemConfig = appConfig.systemById(item.system.id);
    if (systemConfig == null) return item;

    final match = pc.findMatchIn(systemConfig.providers);
    if (match?.auth == null) return item;

    final rehydrated = pc.copyWith(auth: match!.auth);
    final updatedGame = item.game.copyWith(providerConfig: rehydrated);
    return item.copyWith(game: updatedGame);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    _notificationThrottle?.cancel();

    DownloadForegroundService.stop();
    super.dispose();
  }

  /// Async shutdown join for lifecycle owners. dispose signals it immediately;
  /// callers needing a durable pause acknowledgement await this future.
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closing = true;
    final attempts = _driveAttempts.values.toList();
    for (final attempt in attempts) {
      attempt.pauseRequested = true;
      attempt.planningCancellation.cancel();
      attempt.operation?.pause();
    }
    await Future.wait(attempts.map((attempt) => attempt.settled));
    await _stageRetirementRecovery;
    await _ownedRemovalRecovery;
    await _persistence;
  }
}

class _DriveQueueAttempt {
  bool pauseRequested = false;
  final planningCancellation = CancelToken();
  DriveTransferOperation? operation;
  final join = Completer<void>();
  Future<void> get settled => join.future;
}
