import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/app_intents.dart';

import '../../../models/config/provider_config.dart';
import '../../../models/library_identity.dart';
import '../../../models/transfer_record.dart';
import '../../../providers/rom_status_providers.dart';
import '../../../services/drive/drive_authorization.dart';
import '../../../services/drive/drive_media.dart';
import '../../../services/drive/drive_runtime.dart';
import '../../../services/owned_storage.dart';
import '../../../services/library_query.dart';
import '../../../services/database_service.dart';
import '../../../utils/game_metadata.dart';

/// Byte review is read-only. Adoption is a separate explicit ownership action;
/// neither operation changes ROM bytes or performs retention/removal.
class DriveRecoveryReviewDialog extends ConsumerStatefulWidget {
  final ProviderConfig config;
  final RemoteArtifact artifact;
  final String destinationRoot;
  final Set<String> supportedExtensions;
  final DriveRuntime? runtime;
  final String? platformId;
  final LibraryQuery? libraryQuery;
  const DriveRecoveryReviewDialog(
      {super.key,
      required this.config,
      required this.artifact,
      required this.destinationRoot,
      this.supportedExtensions = const {},
      this.platformId,
      this.libraryQuery,
      this.runtime});

  @override
  ConsumerState<DriveRecoveryReviewDialog> createState() =>
      _DriveRecoveryReviewDialogState();
}

class _DriveRecoveryReviewDialogState
    extends ConsumerState<DriveRecoveryReviewDialog> {
  CancelToken? _cancellation;
  bool _running = false, _closeRequested = false;
  DriveLocalCloudObservation? _result;
  DriveLocalCloudObservation? _saved;
  bool _savedReadFailed = false;
  bool _adopting = false;
  InstalledArtifact? _adopted;
  String? _issue;
  LibraryRetentionPage? _retention;
  bool _retentionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _loadRetention();
  }

  Future<void> _loadRetention() async {
    if (_retentionLoading || widget.platformId == null) return;
    setState(() {
      _retentionLoading = true;
      _retention = null;
    });
    LibraryRetentionPage? result;
    try {
      result = await (widget.libraryQuery ??
              LibraryQuery(DatabaseService().database))
          .retentionForArtifact(
              platformId: widget.platformId!, artifact: widget.artifact);
    } catch (_) {
      // Missing/failed current evidence never becomes an outside-sample claim.
    }
    if (!mounted) return;
    setState(() {
      _retention = result;
      _retentionLoading = false;
    });
  }

  String _retentionSummary() {
    final page = _retention;
    if (page == null || page.members.length != 1) {
      return 'Keep for now · this game could not be checked against the Top 25';
    }
    final member = page.members.single;
    return switch (page.disposition(member)) {
      LibraryRetentionDisposition.keep =>
        'Keep offline · #${member.canonicalRank} in this console’s Top 25',
      LibraryRetentionDisposition.preserve =>
        'Keep for now · ratings are still being updated',
      LibraryRetentionDisposition.outsideSample => member.canonicalRank == null
          ? 'Not in the offline sample · no reliable rating yet'
          : 'Not in the offline sample · ranked #${member.canonicalRank}',
    };
  }

  String _issueMessage(String issue) => switch (issue) {
        'cancelled' =>
          'Comparison cancelled. Your files have not been changed.',
        'checksumMismatch' =>
          'The files do not match. Your files have not been changed.',
        'sourceChanged' =>
          'The Drive file changed during the check. Refresh your library and try again.',
        'notFound' =>
          'The Drive file could not be found. Refresh your library to check its location.',
        'interactionRequired' ||
        'accountMismatch' ||
        'accessDenied' =>
          'Google Drive access needs attention. Reconnect the source in Settings, then try again.',
        'quota' => 'Google Drive has limited access for now. Try again later.',
        'truncated' =>
          'The complete file could not be read. Check your connection and try again.',
        'ownership_conflict_or_journal_failure' =>
          'G-Shop could not safely register this file. Your files have not been changed.',
        _ =>
          'The comparison could not finish. Check your connection and storage access, then try again. Your files have not been changed.',
      };

  Future<void> _loadSaved() async {
    DriveLocalCloudObservation? saved;
    var failed = false;
    try {
      saved = await (widget.runtime ?? DriveRuntime.instance)
          .savedLocalCloudObservation(
              artifact: widget.artifact,
              destinationRoot: widget.destinationRoot,
              relativePath: widget.artifact.displayName);
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _savedReadFailed = failed;
    });
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  void _close() {
    if (_running) {
      _closeRequested = true;
      _cancellation?.cancel();
      setState(() {});
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _verify({bool adopt = false}) async {
    if (_running) return;
    final cancellation = CancelToken();
    setState(() {
      _cancellation = cancellation;
      _running = true;
      _result = null;
      _issue = null;
      _adopting = adopt;
    });
    DriveLocalCloudObservation? result;
    String? issue;
    InstalledArtifact? adopted;
    try {
      if (adopt) {
        adopted = await (widget.runtime ?? DriveRuntime.instance)
            .adoptLocalCloudBytes(
                config: widget.config,
                artifact: widget.artifact,
                destinationRoot: widget.destinationRoot,
                relativePath: widget.artifact.displayName,
                supportedExtensions: widget.supportedExtensions,
                cancellation: cancellation);
      } else {
        result = await (widget.runtime ?? DriveRuntime.instance)
            .verifyLocalCloudBytes(
                config: widget.config,
                artifact: widget.artifact,
                destinationRoot: widget.destinationRoot,
                relativePath: widget.artifact.displayName,
                cancellation: cancellation);
      }
    } on DriveTransferException catch (error) {
      issue = error.issue.name;
    } on DriveAuthorizationException catch (error) {
      issue = error.issue.name;
    } on OwnedStorageException catch (error) {
      issue = error.code;
    } on StateError {
      issue = 'ownership_conflict_or_journal_failure';
    } catch (_) {
      issue = 'unavailable';
    }
    // Runtime completion includes awaited native close and transport drain.
    if (!mounted) return;
    // A byte observation/adoption changes exact availability without touching
    // the ROM, so neither filesystem nor download watchers see it. Refresh the
    // existing shared index after the operation drains, including a cancellation
    // or failure that may have followed a durable journal commit.
    ref.read(romChangeSignalProvider.notifier).state++;
    setState(() {
      _running = false;
      _cancellation = null;
      _result = cancellation.isCancelled ? null : result;
      // Successful atomic ownership commit remains real even if cancellation
      // arrived after its linearization point.
      _adopted = adopted;
      _issue = issue;
    });
    if (_closeRequested) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_running,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: Actions(
          actions: {
            BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
              _close();
              return null;
            }),
            ConfirmIntent: CallbackAction<ConfirmIntent>(onInvoke: (_) {
              final focused = FocusManager.instance.primaryFocus?.context;
              if (focused != null) {
                Actions.maybeInvoke(focused, const ActivateIntent());
              }
              return null;
            }),
            NavigateIntent: CallbackAction<NavigateIntent>(onInvoke: (intent) {
              final focused = FocusManager.instance.primaryFocus?.context;
              if (focused != null) {
                final scope = FocusScope.of(focused);
                if (intent.direction == GridDirection.left ||
                    intent.direction == GridDirection.up) {
                  scope.previousFocus();
                } else {
                  scope.nextFocus();
                }
              }
              return null;
            }),
          },
          child: AlertDialog(
            title: const Text('Compare with Google Drive'),
            content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.artifact.displayName),
                    const SizedBox(height: 12),
                    const Text('Offline sample · Top 25 per console'),
                    Text(_retentionLoading
                        ? 'Checking this game’s place in your collection…'
                        : _retentionSummary()),
                    if (_retention case final page?)
                      Text(
                          '${page.rankedGames} of ${page.collectionGames} games have ranking scores'
                          '${page.provisional ? ' · Results may change as ratings are added' : ''}'),
                    const Text(
                        'This check does not delete files or choose games to remove.'),
                    if (widget.platformId != null)
                      TextButton(
                          onPressed: _running || _retentionLoading
                              ? null
                              : _loadRetention,
                          child: const Text('Refresh Top 25 status')),
                    const SizedBox(height: 12),
                    if (DriveRuntime.supportsStandaloneAdoption(
                            widget.artifact.displayName,
                            widget.supportedExtensions) &&
                        _adopted == null) ...[
                      const Text(
                          'Add to G-Shop checks that the files match, then lets '
                          'G-Shop manage this existing download. Nothing is deleted.'),
                      const SizedBox(height: 12),
                    ],
                    Text(
                        'Compare files reads the full Drive file (${GameMetadata.formatFileSize(widget.artifact.sizeBytes ?? 0)}) to check that it matches your local copy. '
                        'It uses internet data but does not save another copy or change your files.'),
                    const SizedBox(height: 12),
                    if (_saved case final saved?
                        when _result == null && !_running) ...[
                      Text(
                          'Last successful comparison: ${saved.observedAt.toLocal()}\n'
                          'The files have not been checked again since then. '
                          'Choose Compare files for a new check.'),
                      const SizedBox(height: 12),
                    ],
                    if (_savedReadFailed && _result == null && !_running)
                      const Text(
                          'The previous comparison could not be loaded. You can run a new check.'),
                    if (_running) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(_closeRequested
                          ? 'Stopping the comparison…'
                          : _adopting
                              ? 'Checking the file before adding it to G-Shop…'
                              : 'Comparing your local copy with Google Drive…'),
                    ],
                    if (_issue != null && !_running)
                      Text(_issueMessage(_issue!)),
                    if (_result case final result?) ...[
                      const Text('Your local copy matches Google Drive.'),
                      Text('Checked: ${result.observedAt.toLocal()}'),
                      const SizedBox(height: 8),
                      const Text(
                          'This confirms the files match, not that the game runs in your emulator. Nothing was deleted.'),
                    ],
                    if (_adopted != null) ...[
                      const Text('Your existing download was added to G-Shop.'),
                      const Text(
                          'Nothing was deleted. G-Shop will check this file again before removing it. This does not confirm that the game runs in your emulator.'),
                    ],
                    ExpansionTile(
                      title: const Text('Technical details'),
                      children: [
                        SelectableText(
                            '${widget.destinationRoot}/${widget.artifact.displayName}'),
                        if (_issue != null)
                          SelectableText('Error code: $_issue'),
                        if (_result case final result?)
                          SelectableText(
                              'Drive version: ${result.artifact.version}\nSHA-256: ${result.checksums['sha256']}'),
                        if (_adopted case final installation?)
                          SelectableText(
                              'Drive version: ${installation.artifact.version}\nSHA-256: ${installation.verifiedChecksums['sha256']}'),
                      ],
                    ),
                  ],
                ))),
            actions: [
              TextButton(
                  autofocus: _running || _result != null,
                  onPressed: _closeRequested ? null : _close,
                  child: Text(_running ? 'Cancel' : 'Close')),
              if (!_running &&
                  _adopted == null &&
                  DriveRuntime.supportsStandaloneAdoption(
                      widget.artifact.displayName, widget.supportedExtensions))
                OutlinedButton(
                    onPressed: () => _verify(adopt: true),
                    child: const Text('Add to G-Shop')),
              if (!_running && _adopted == null)
                FilledButton(
                    autofocus: _result == null,
                    onPressed: _verify,
                    child: const Text('Compare files')),
            ],
          ),
        ),
      );
}
