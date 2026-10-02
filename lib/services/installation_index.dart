import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import '../models/game_item.dart';
import '../models/library_identity.dart';
import '../models/transfer_record.dart';
import 'database_service.dart';
import 'installation_paths.dart';
import 'owned_storage.dart';
import 'transfer_journal.dart';

/// Offline installation truth, independent of source authorization and queue UI.
/// Call after directory enumeration and again before handing a path to a consumer.
class InstallationIndex {
  final TransferJournal journal;
  final OwnedStorage storage;
  InstallationIndex(this.journal, {this.storage = const OwnedStorage()});

  static InstallationIndex application() =>
      InstallationIndex(TransferJournal(DatabaseService().database));

  /// Legacy filesystem consumers must not reach a managed target through an
  /// unrecorded symlink/junction alias. Native exact reads enforce this in *at IO.
  static bool isRedirectedPath(String path) {
    var current = _path(path);
    while (true) {
      if (FileSystemEntity.isLinkSync(current)) return true;
      final parent = p.dirname(current);
      if (parent == current) return false;
      current = parent;
    }
  }

  Future<InstallationSnapshot> scan(String root,
      {bool verifyInstalled = true}) async {
    final scope = _path(root);
    final targets = <String>{};
    final published = <String>{};
    final installed = <String, InstalledArtifact>{};
    for (final recordedRoot in await journal.destinationRoots()) {
      final candidate = _path(recordedRoot);
      if (!installationPathsOverlap(scope, candidate)) continue;
      await for (final row in journal.targetsInRoot(recordedRoot)) {
        final record = row.transfer;
        final path = _path(p.join(record.destinationRoot, record.relativePath));
        if (!installationPathsOverlap(scope, path)) continue;
        targets.add(path);
        // Intent precedes the public create/rename, including the crash window
        // before the first receipt. Queue/lifecycle labels are not ownership.
        if (record.publication == null) continue;
        published.add(path);
        final manifest = row.installation;
        if (!verifyInstalled ||
            manifest == null ||
            record.lifecycle != TransferLifecycle.completed) {
          continue;
        }
        try {
          await requireInstallation(record, manifest);
          installed[path] = manifest;
        } on OwnedStorageException {
          // Missing, changed, redirected or inaccessible managed files must not
          // silently reappear as unmanaged local games.
        }
      }
    }
    return InstallationSnapshot._(targets, published, installed);
  }

  /// A consumer request checks only matching artifact manifests. It never stats
  /// every installed ROM or requires a currently connected source/account.
  Future<String?> resolveArtifact(RemoteArtifact artifact, String root) async {
    for (final recordedRoot in await journal.destinationRoots()) {
      if (!installationPathsOverlap(root, recordedRoot)) continue;
      await for (final row in journal.targetsInRoot(recordedRoot,
          artifactKey: artifact.id.key)) {
        final record = row.transfer;
        final path = _path(p.join(record.destinationRoot, record.relativePath));
        if (!installationPathsOverlap(root, path) ||
            record.lifecycle != TransferLifecycle.completed ||
            !InstallationSnapshot.sameContent(record.artifact, artifact)) {
          continue;
        }
        try {
          await requireInstallation(record, row.installation);
          return path;
        } on OwnedStorageException {
          // A broken location cannot borrow a namesake; another explicitly
          // committed location of the same artifact may still be usable.
        }
      }
    }
    return null;
  }

  Future<void> requireInstallation(
      TransferRecord record, InstalledArtifact? manifest) async {
    const equality = DeepCollectionEquality();
    if (record.lifecycle != TransferLifecycle.completed ||
        manifest == null ||
        manifest.transferId != record.id ||
        manifest.destinationRoot != record.destinationRoot ||
        manifest.relativePath != record.relativePath ||
        record.publication?.confirmed != true ||
        await journal.hasPendingRemoval(record.id) ||
        record.publication?.destinationIdentity == null ||
        !manifest.fileIdentity
            .matches(record.publication!.destinationIdentity!) ||
        !equality.equals(
            manifest.artifact.toJson(), record.artifact.toJson()) ||
        !equality.equals(
            manifest.verifiedChecksums, record.verifiedChecksums)) {
      throw const OwnedStorageException('changed');
    }
    final actual = await storage.inspect(
        destinationRoot: record.destinationRoot,
        relativePath: record.relativePath,
        stagePath: record.stagePath,
        published: true);
    if (actual == null || !actual.matches(manifest.fileIdentity)) {
      throw const OwnedStorageException('changed');
    }
  }
}

class InstallationSnapshot {
  final InstallationPathClaims _targets;
  final InstallationPathClaims _published;
  final Map<String, List<MapEntry<String, InstalledArtifact>>> _byArtifact;
  final Map<String, List<MapEntry<String, InstalledArtifact>>> _byFoldedPath;
  final Map<String, InstalledArtifact> installed;
  InstallationSnapshot._(Set<String> targets, Set<String> published,
      Map<String, InstalledArtifact> installed)
      : _targets = InstallationPathClaims(targets),
        _published = InstallationPathClaims(published),
        _byArtifact =
            groupBy(installed.entries, (entry) => entry.value.artifact.id.key),
        _byFoldedPath =
            groupBy(installed.entries, (entry) => entry.key.toLowerCase()),
        installed = Map.unmodifiable(installed);

  /// Managed paths never fall back to filename identity. A folder enclosing a
  /// managed member is not safe for legacy recursive sharing/removal either.
  bool allowsLegacy(String path) => !_published.overlaps(path);
  bool protects(String path) => _targets.overlaps(path);

  InstalledArtifact? atPath(String path) {
    final normalized = _path(path);
    final exact = installed[normalized];
    if (exact != null) return exact;
    for (final candidate in _byFoldedPath[normalized.toLowerCase()] ??
        const <MapEntry<String, InstalledArtifact>>[]) {
      // Equal folded full paths have equal depth; overlap proves filesystem
      // identity rather than conflating distinct case-sensitive files.
      if (installationPathsOverlap(candidate.key, normalized)) {
        return candidate.value;
      }
    }
    return null;
  }

  String? resolve(RemoteArtifact artifact) {
    for (final entry in _byArtifact[artifact.id.key] ??
        const <MapEntry<String, InstalledArtifact>>[]) {
      if (sameContent(entry.value.artifact, artifact)) return entry.key;
    }
    return null;
  }

  /// A Drive rename/move does not invalidate the locally committed bytes.
  /// Account/source/file, version, size and provider digests must still agree.
  static bool sameContent(RemoteArtifact a, RemoteArtifact b) =>
      a.id.key == b.id.key &&
      a.version == b.version &&
      a.sizeBytes == b.sizeBytes &&
      const DeepCollectionEquality()
          .equals(a.providerChecksums, b.providerChecksums);

  List<GameItem> filterLocal(List<GameItem> games, String root) => [
        for (final game in games)
          if (atPath(p.join(root, game.filename)) case final manifest?)
            game.copyWith(remoteArtifact: manifest.artifact)
          else if (allowsLegacy(p.join(root, game.filename)))
            game,
      ];
}

String _path(String value) => installationPath(value);
