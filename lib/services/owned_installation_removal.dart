import 'dart:math';
import 'dart:convert';

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
  // Bounded deterministic namespace even with full SHA-256 transfer IDs.
  // Tuple encoding keeps the parent/member ownership association unambiguous.
  static String _memberRemovalId(String parent, String member) =>
      'bundle-removal-${sha256.convert(utf8.encode(jsonEncode([
            parent,
            member
          ])))}';
  final TransferJournal journal;
  final OwnedStorage storage;
  OwnedInstallationRemoval(this.journal, {this.storage = const OwnedStorage()});

  static String _scope(
      InstalledArtifact installation, List<InstalledArtifact> group) {
    if(group.isEmpty)return p.join(installation.destinationRoot,installation.relativePath);
    final paths = [
      for (final root in [installation, ...group])
        for (final member in [root, ...root.dependencies])
          p.join(member.destinationRoot, member.relativePath)
    ];
    var scope = paths.first;
    for (final path in paths.skip(1)) {
      while (scope != path && !p.isWithin(scope, path)) {
        scope = p.dirname(scope);
      }
    }
    return scope;
  }

  Future<void> remove(InstalledArtifact installation,
          {String? replacementTransferId,
          String? bundleRemovalId,
          Future<void> Function()? beforeRemoval,
          bool policyDriven = false,
          List<InstalledArtifact> groupMembers = const []}) =>
      InstallationMutations.run(
          _scope(installation, groupMembers),
          () => _remove(installation,
              replacementTransferId: replacementTransferId,
              bundleRemovalId: bundleRemovalId,
              beforeRemoval: beforeRemoval,
              policyDriven: policyDriven,
              groupMembers: groupMembers,scopeHeld:groupMembers.isNotEmpty));

  Future<void> _remove(InstalledArtifact installation,
      {String? replacementTransferId,
      String? bundleRemovalId,
      String? groupRemovalId,
      Future<void> Function()? beforeRemoval,
      bool policyDriven = false,
      List<InstalledArtifact> groupMembers = const [],bool scopeHeld=false}) async {
    final transfer = await journal.transfer(installation.transferId);
    if (transfer == null) throw const OwnedStorageException('changed');
    await InstallationIndex(journal, storage: storage).requireInstallation(
        transfer, installation,
        bundleOwner: bundleRemovalId == null ? null : transfer.bundleOwner);
    final plan = await storage.prepare(installation.destinationRoot);
    if (!plan.sameMountHint) {
      throw const OwnedStorageException('cross_volume');
    }
    // Policy-driven callers perform current recovery/eligibility checks
    // inside the existing target mutation, before creating any remove intent.
    await beforeRemoval?.call();
    final random = Random.secure();
    final parentRemoval = bundleRemovalId ?? groupRemovalId;
    final id = parentRemoval != null
        ? _memberRemovalId(parentRemoval, transfer.id)
        : replacementTransferId == null
            ? 'removal-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}'
            : 'replacement-$replacementTransferId';
    final intent = await journal.beginRemoval(transfer, installation,
        id: id,
        quarantinePath: plan.stagePath(id),
        replacementTransferId: replacementTransferId,
        bundleRemovalId: bundleRemovalId,
        policyDriven: policyDriven,
        groupRemovalId: groupRemovalId,
        groupMembers: groupMembers);
    await _continue(intent,scopeHeld:scopeHeld);
    if ((await journal.removal(id))!.phase == OwnedRemovalPhase.retained) {
      throw const OwnedStorageException('cross_volume');
    }
  }

  Future<void> recover(String id,
      {Future<void> Function()? beforeRemoval}) async {
    final saved = await journal.removal(id);
    if (saved == null) throw const OwnedStorageException('not_found');
    await InstallationMutations.run(
        _scope(saved.installation, saved.groupMembers), () async {
      final current = (await journal.removal(id))!;
      if (current.isTerminal) return;
      if (current.issue != null) throw OwnedStorageException(current.issue!);
      await beforeRemoval?.call();
      await _continue(current,scopeHeld:current.groupMembers.isNotEmpty);
    });
  }

  Future<void> _continue(OwnedRemovalRecord saved,{bool scopeHeld=false}) async {
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
      for (final member in manifest.dependencies) {
        final memberRemovalId = _memberRemovalId(record.id, member.transferId);
        final prior = await journal.removal(memberRemovalId);
        if (prior == null) {
          if(scopeHeld) {
            await _remove(member,bundleRemovalId:record.id,policyDriven:record.policyDriven,scopeHeld:true);
          } else {
            await remove(member,bundleRemovalId:record.id,policyDriven:record.policyDriven);
          }
        } else {
          if (prior.issue != null) throw OwnedStorageException(prior.issue!);
          if (!prior.isTerminal) {
            if(scopeHeld) { await _continue(prior,scopeHeld:true); }
            else { await recover(prior.id); }
          }
          if ((await journal.removal(memberRemovalId))!.phase !=
              OwnedRemovalPhase.completed) {
            throw const OwnedStorageException('bundle_removal_pending');
          }
        }
      }
      for (final member in record.groupMembers) {
        final id = _memberRemovalId(record.id, member.transferId);
        final prior = await journal.removal(id);
        if (prior == null) {
          await _remove(member,
              groupRemovalId: record.id, policyDriven: record.policyDriven,scopeHeld:true);
        } else if (!prior.isTerminal) {
          if (prior.issue != null) throw OwnedStorageException(prior.issue!);
          await _continue(prior,scopeHeld:true);
        }
        if ((await journal.removal(id))!.phase != OwnedRemovalPhase.completed) {
          throw const OwnedStorageException('bundle_removal_pending');
        }
      }
      await storage.retireQuarantine(
          destinationRoot: root,
          relativePath: relative,
          stagePath: stage,
          expectedIdentity: expected);
      await journal.finishRemoval(record);
    } on OwnedStorageException catch (error) {
      if (error.code == 'cross_volume' &&
          record.phase == OwnedRemovalPhase.intent) {
        // EXDEV cannot move an entry. Still inspect both namespaces before
        // ending a legacy pending intent; ambiguity retains the recovery gate.
        final private = await storage.inspect(
            destinationRoot: root, relativePath: relative, stagePath: stage);
        final public = await storage.inspect(
            destinationRoot: root,
            relativePath: relative,
            stagePath: stage,
            published: true);
        if (private == null && public != null && public.matches(expected)) {
          await journal.retainUnmovedRemoval(record);
          return;
        }
      }
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
