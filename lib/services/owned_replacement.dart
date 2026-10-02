import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/owned_removal_record.dart';
import '../models/transfer_record.dart';
import 'installation_index.dart';
import 'installation_paths.dart';
import 'owned_installation_removal.dart';
import 'owned_storage.dart';
import 'transfer_journal.dart';

/// Post-commit retirement only. Distinct-path publication keeps the old file
/// intact through transfer, verification, cancellation and publication crashes.
/// A failed cleanup never changes the new installation's completed state.
Future<String?> retireReplacedInstallation(
        TransferJournal journal, OwnedStorage storage, TransferRecord record) =>
    InstallationMutations.run(
        p.join(record.destinationRoot, record.relativePath),
        () => _retire(journal, storage, record));

Future<String?> _retire(TransferJournal journal, OwnedStorage storage,
    TransferRecord record) async {
  final old = record.replacesInstallation;
  if (old == null || record.lifecycle != TransferLifecycle.completed) {
    return null;
  }
  try {
    if (await journal.replacementPhase(record.id) == 'retired') return null;
    if (record.publication?.method == PublicationMethod.copy &&
        !record.stageRetired) {
      throw const OwnedStorageException('replacement_stage_pending');
    }
    final current = await journal.installationForTarget(
        destinationRoot: record.destinationRoot,
        relativePath: record.relativePath);
    await InstallationIndex(journal, storage: storage)
        .requireInstallation(record, current);
    final session = await storage.open(
        destinationRoot: record.destinationRoot,
        relativePath: record.relativePath,
        stagePath: record.stagePath,
        expectedIdentity: current!.fileIdentity,
        durableOffset: current.sizeBytes,
        published: true);
    try {
      final digest = await sha256.bind(session.bytes(current.sizeBytes)).single;
      if (digest.toString() != current.verifiedChecksums['sha256'] ||
          !(await session.checkpoint()).matches(current.fileIdentity)) {
        throw const OwnedStorageException('changed');
      }
    } finally {
      await session.close();
    }
    final remover = OwnedInstallationRemoval(journal, storage: storage);
    final removalId = 'replacement-${record.id}';
    final intent = await journal.removal(removalId);
    if (intent == null) {
      await remover.remove(old, replacementTransferId: record.id);
    } else {
      await remover.recover(removalId);
      if ((await journal.removal(removalId))!.phase !=
          OwnedRemovalPhase.completed) {
        throw const OwnedStorageException('cross_volume');
      }
    }
    await journal.finishReplacement(record);
    return null;
  } catch (error) {
    final issue =
        error is OwnedStorageException ? error.code : 'replacement_pending';
    // Durable, bounded diagnostics; no timer retry and no false failed download.
    try {
      await journal.recordReplacementIssue(record, issue);
    } catch (_) {
      // The original durable claim still requires recovery; cleanup cannot turn
      // an already committed installation into a failed network transfer.
    }
    return issue;
  }
}
