import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/input/app_intents.dart';

import '../../../models/config/provider_config.dart';
import '../../../models/library_identity.dart';
import '../../../models/transfer_record.dart';
import '../../../services/drive/drive_authorization.dart';
import '../../../services/drive/drive_media.dart';
import '../../../services/drive/drive_runtime.dart';
import '../../../services/owned_storage.dart';
import '../../../services/library_query.dart';
import '../../../services/database_service.dart';
import '../../../utils/game_metadata.dart';

/// Byte review is read-only. Adoption is a separate explicit ownership action;
/// neither operation changes ROM bytes or performs retention/removal.
class DriveRecoveryReviewDialog extends StatefulWidget {
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
  State<DriveRecoveryReviewDialog> createState() =>
      _DriveRecoveryReviewDialogState();
}

class _DriveRecoveryReviewDialogState extends State<DriveRecoveryReviewDialog> {
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
      return 'Preserve · exact current retention binding unavailable';
    }
    final member = page.members.single;
    return switch (page.disposition(member)) {
      LibraryRetentionDisposition.keep =>
        'Keep · canonical rank ${member.canonicalRank} (Top 25)',
      LibraryRetentionDisposition.preserve => 'Preserve · ranking incomplete',
      LibraryRetentionDisposition.outsideSample =>
        'Outside sample · canonical rank ${member.canonicalRank}',
    };
  }

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
            title: const Text('Check local/cloud bytes'),
            content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${widget.destinationRoot}/${widget.artifact.displayName}'),
                    const SizedBox(height: 12),
                    const Text('Cached Top-25 retention review'),
                    Text(_retentionLoading
                        ? 'Resolving exact collection binding…'
                        : _retentionSummary()),
                    if (_retention case final page?)
                      Text('${page.rankedGames}/${page.collectionGames} ranked'
                          '${page.provisional ? ' · Provisional' : ''}'),
                    const Text(
                        'Planning only. No removal is authorized; cloud, '
                        'restore, saves, sync and identities must be checked again '
                        'at execution.'),
                    if (widget.platformId != null)
                      TextButton(
                          onPressed: _running || _retentionLoading
                              ? null
                              : _loadRetention,
                          child: const Text('Refresh retention review')),
                    const SizedBox(height: 12),
                    if (DriveRuntime.supportsStandaloneAdoption(
                            widget.artifact.displayName,
                            widget.supportedExtensions) &&
                        _adopted == null) ...[
                      const Text(
                          'Verify and adopt repeats the current byte check and '
                          'records this existing file as a managed R-Shop installation. '
                          'No file is deleted. Migration still requires ranking, '
                          'restore and save/sync checks.'),
                      const SizedBox(height: 12),
                    ],
                    Text(
                        'Reads the complete cloud file (${GameMetadata.formatFileSize(widget.artifact.sizeBytes ?? 0)}) and streams cryptographic checks. '
                        'No ROM copy is saved. Does not adopt or delete local files.'),
                    const SizedBox(height: 12),
                    if (_saved case final saved?
                        when _result == null && !_running) ...[
                      Text('Past byte match: ${saved.observedAt.toLocal()}\n'
                          'Source version then: ${saved.artifact.version}\n'
                          'Local/cloud bytes are not rechecked now. This saved observation '
                          'does not authorize adoption or removal.'),
                      const SizedBox(height: 12),
                    ],
                    if (_savedReadFailed && _result == null && !_running)
                      const Text(
                          'Saved observation unavailable. No past verification is claimed.'),
                    if (_running) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(_closeRequested
                          ? 'Cancelling and closing reads…'
                          : _adopting
                              ? 'Verifying existing file before adoption…'
                              : 'Comparing full local and current cloud bytes…'),
                    ],
                    if (_issue != null && !_running)
                      Text('Not verified: $_issue. Files preserved.'),
                    if (_result case final result?) ...[
                      const Text('Current byte match verified.'),
                      const Text(
                          'Byte observation saved privately for restart-safe review.'),
                      Text('Source version: ${result.artifact.version}\n'
                          'Observed: ${result.observedAt.toLocal()}\n'
                          'SHA-256: ${result.checksums['sha256']}'),
                      const SizedBox(height: 8),
                      const Text(
                          'This observation does not prove a usable emulator restore '
                          'or authorize removal. Migration must check ranking, saves, '
                          'sync policy and identities again at execution.'),
                    ],
                    if (_adopted case final installation?) ...[
                      const Text('Existing file adopted.'),
                      Text('Source version: ${installation.artifact.version}\n'
                          'SHA-256: ${installation.verifiedChecksums['sha256']}'),
                      const Text(
                          'No file was deleted. Ownership is recorded privately; '
                          'future removal revalidates exact local bytes. This is not '
                          'a completed Top-25 migration or emulator-restore proof.'),
                    ],
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
                    child: const Text('Verify and adopt')),
              if (!_running && _adopted == null)
                FilledButton(
                    autofocus: _result == null,
                    onPressed: _verify,
                    child: const Text('Verify bytes')),
            ],
          ),
        ),
      );
}
