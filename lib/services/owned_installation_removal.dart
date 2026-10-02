import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/owned_removal_record.dart';
import '../models/transfer_record.dart';
import 'installation_index.dart';
import 'installation_paths.dart';
import 'owned_storage.dart';
import 'transfer_journal.dart';

/// Explicit manifest-only removal; no cloud API or recursive filesystem delete.
/// A private quarantine move, streaming verification and unlink each have prior
/// durable intents. Recovery never repeats a completed download or adopts a
/// public namesake. App locks do not claim to lock out external writers.
class OwnedInstallationRemoval {
  final TransferJournal journal;
  final OwnedStorage storage;
  OwnedInstallationRemoval(this.journal, {this.storage = const OwnedStorage()});

  Future<void> remove(InstalledArtifact installation) =>
      InstallationMutations.run(
          p.join(installation.destinationRoot, installation.relativePath),
          () async {
        final transfer = await journal.transfer(installation.transferId);
        if (transfer == null) throw const OwnedStorageException('changed');
        await InstallationIndex(journal, storage: storage)
            .requireInstallation(transfer, installation);
        final plan = await storage.prepare(installation.destinationRoot);
        final random = Random.secure();
        final id =
            'removal-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        final intent = await journal.beginRemoval(transfer, installation,
            id: id, quarantinePath: plan.stagePath(id));
        await _continue(intent);
      });

  Future<void> recover(String id) async {
    final saved = await journal.removal(id);
    if (saved == null) throw const OwnedStorageException('not_found');
    await InstallationMutations.run(
        p.join(saved.installation.destinationRoot,
            saved.installation.relativePath), () async {
      final current = (await journal.removal(id))!;
      if (current.phase == OwnedRemovalPhase.completed) return;
      if (current.issue != null) throw OwnedStorageException(current.issue!);
      await _continue(current);
    });
  }

  Future<void> _continue(OwnedRemovalRecord saved) async {
    var record = saved;
    final manifest = record.installation;
    final expected = manifest.fileIdentity;
    final root = manifest.destinationRoot;
    final relative = manifest.relativePath;
    final stage = record.quarantinePath;
    try {
      if (record.phase == OwnedRemovalPhase.intent) {
        final moved = await storage.quarantine(
            destinationRoot: root,
            relativePath: relative,
            stagePath: stage,
            expectedIdentity: expected);
        if (!moved.matches(expected)) {
          throw const OwnedStorageException('changed');
        }
        record =
            await journal.advanceRemoval(record, OwnedRemovalPhase.quarantined);
      }
      // Verify again on recovery, including a deletion-intent crash window.
      // Only a prior deletion intent permits an absent quarantine replay.
      final actual = await storage.inspect(
          destinationRoot: root, relativePath: relative, stagePath: stage);
      if (actual != null) {
        if (!actual.matches(expected)) {
          throw const OwnedStorageException('changed');
        }
        final session = await storage.openQuarantine(
            destinationRoot: root,
            relativePath: relative,
            stagePath: stage,
            expectedIdentity: expected);
        try {
          if (!session.openedIdentity.matches(expected)) {
            throw const OwnedStorageException('changed');
          }
          final digest =
              await sha256.bind(session.bytes(manifest.sizeBytes)).single;
          if (digest.toString() !=
                  manifest.verifiedChecksums['sha256']?.toLowerCase() ||
              !(await session.checkpoint()).matches(expected)) {
            throw const OwnedStorageException('changed');
          }
        } finally {
          // Do not persist deletion intent until the read handle really closes.
          await session.close();
        }
      } else if (record.phase != OwnedRemovalPhase.deleting) {
        throw const OwnedStorageException('changed');
      }
      if (record.phase == OwnedRemovalPhase.quarantined) {
        record =
            await journal.advanceRemoval(record, OwnedRemovalPhase.deleting);
      }
      await storage.retireQuarantine(
          destinationRoot: root,
          relativePath: relative,
          stagePath: stage,
          expectedIdentity: expected);
      await journal.finishRemoval(record);
    } on OwnedStorageException catch (error) {
      if (error.code == 'changed') {
        // Preserve conflicting bytes. Restoration is strictly no-clobber and
        // may be unsupported; the durable issue retains ownership either way.
        await journal.removalIssue(record, 'changed');
        final quarantined = await storage.inspect(
            destinationRoot: root, relativePath: relative, stagePath: stage);
        if (quarantined != null) {
          try {
            await storage.restoreQuarantine(
                destinationRoot: root,
                relativePath: relative,
                stagePath: stage,
                expectedIdentity: quarantined);
          } on OwnedStorageException {
            // Kept privately, never silently overwritten or deleted.
          }
        }
      }
      rethrow;
    }
  }
}
