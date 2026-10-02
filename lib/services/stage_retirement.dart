import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

import '../models/transfer_record.dart';
import 'installation_index.dart';
import 'installation_paths.dart';
import 'owned_storage.dart';
import 'transfer_journal.dart';

/// Replays only a committed copy's PRIVATE-stage cleanup. No source credentials,
/// network requests, public unlink, or download-state rollback are involved.
Future<TransferRecord> retireCommittedStage(
    TransferJournal journal, OwnedStorage storage, TransferRecord record,
    {bool resourcesClosed = true}) async {
  if (record.lifecycle != TransferLifecycle.completed ||
      record.publication?.method != PublicationMethod.copy ||
      record.stageRetired) {
    return record;
  }
  try {
    return await InstallationMutations.run(
        p.join(record.destinationRoot, record.relativePath), () async {
      final current = await journal.transfer(record.id);
      if (current == null) throw StateError('Retirement transfer disappeared');
      if (current.stageRetired) return current;
      final installation = await journal.installationForTarget(
          destinationRoot: current.destinationRoot,
          relativePath: current.relativePath);
      String? issue;
      try {
        await InstallationIndex(journal, storage: storage)
            .requireInstallation(current, installation, bundleOwner: current.bundleOwner);
        if (resourcesClosed) {
          await storage.retireStage(current);
        } else {
          issue = 'close_unconfirmed';
        }
      } on OwnedStorageException catch (error) {
        // Keep the installed outcome and explicit pending cleanup separately.
        // Startup recovery or explicit resume retries without any ROM bytes.
        issue = error.code;
      }
      return journal.stageRetirementResult(current, issue: issue);
    });
  } catch (_) {
    // Installation already committed before this independent maintenance step.
    // In particular, a failed acknowledgement after unlink must not demote it
    // into a failed download or cause a new payload request. Leave the durable
    // pending intent unchanged for startup replay. Do not invent a persisted
    // cleanup result when the journal itself could not acknowledge one.
    debugPrint('Stage retirement: postcommit maintenance remains pending');
    return record;
  }
}
