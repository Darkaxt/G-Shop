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
            record.bundleOwner != null ||
            manifest == null ||
            record.lifecycle != TransferLifecycle.completed) {
          continue;
        }
        try {
          if (await journal.hasCommittedReplacement(manifest.id)) continue;
          await requireInstallation(record, manifest);
          installed[path] = manifest;
        } on OwnedStorageException {
          // Missing, changed, redirected or inaccessible managed files must not
          // silently reappear as unmanaged local games.
        }
      }
    }
    final observed = verifyInstalled
        ? await _observedCopies(scope, excluded: targets)
        : (aliases: <String, JournaledByteObservation>{}, current: <String>{});
    final copies = <String, JournaledByteObservation>{};
    final aliases = <String, RemoteArtifact>{};
    for (final entry in observed.aliases.entries) {
      aliases[entry.key] = entry.value.observation.artifact;
      // _observedCopies retains missing paths as historical aliases only.
      if (observed.current.contains(entry.key)) copies[entry.key] = entry.value;
    }
    return InstallationSnapshot._(
        targets, published, installed, copies, aliases);
  }

  Future<({Map<String, JournaledByteObservation> aliases, Set<String> current})>
      _observedCopies(String root,
          {Set<String>? excluded, String? artifactKey}) async {
    final reserved = excluded ?? <String>{};
    if (excluded == null) {
      await for (final target in journal.reservedTargets()) {
        final path = _path(p.join(target.root, target.relativePath));
        if (installationPathsOverlap(root, path)) reserved.add(path);
      }
    }
    final claims = InstallationPathClaims(reserved);
    final candidates = <String, List<JournaledByteObservation>>{};
    for (final recordedRoot in await journal.byteObservationRoots()) {
      if (!installationPathsOverlap(root, recordedRoot)) continue;
      final selectedPaths = <String>{};
      if (artifactKey != null) {
        await for (final saved in journal.byteObservationsInRoot(recordedRoot,
            artifactKey: artifactKey)) {
          selectedPaths.add(saved.observation.relativePath);
        }
      }
      final streams = artifactKey == null
          ? [journal.byteObservationsInRoot(recordedRoot)]
          : [
              for (final path in selectedPaths)
                journal.byteObservationsInRoot(recordedRoot, relativePath: path)
            ];
      for (final stream in streams) {
        await for (final saved in stream) {
          final observation = saved.observation;
          final path = _path(p.join(recordedRoot, observation.relativePath));
          if (!installationPathsOverlap(root, path) || claims.overlaps(path)) {
            continue;
          }
          if (await journal.targetOwner(
                  destinationRoot: recordedRoot,
                  relativePath: observation.relativePath) !=
              null) {
            continue;
          }
          candidates.putIfAbsent(path, () => []).add(saved);
        }
      }
    }
    final result = <String, JournaledByteObservation>{};
    final current = <String>{};
    for (final entry in candidates.entries) {
      final matching = <JournaledByteObservation>[];
      var present = false;
      for (final saved in entry.value) {
        final observation = saved.observation;
        try {
          final actual = await storage.inspectExisting(
              destinationRoot: observation.destinationRoot,
              relativePath: observation.relativePath);
          if (actual == null || actual.matches(observation.localIdentity)) {
            matching.add(saved);
            present = actual != null;
          }
        } on OwnedStorageException {
          // Inaccessible or redirected is not evidence of a usable or absent copy.
        }
      }
      if (matching.length != 1) continue;
      result[entry.key] = matching.single;
      if (present) current.add(entry.key);
    }
    return (aliases: result, current: current);
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
            record.bundleOwner != null ||
            !InstallationSnapshot.sameContent(record.artifact, artifact)) {
          continue;
        }
        try {
          if (row.installation == null ||
              await journal.hasCommittedReplacement(row.installation!.id)) {
            continue;
          }
          await requireInstallation(record, row.installation);
          return path;
        } on OwnedStorageException {
          // A broken location cannot borrow a namesake; another explicitly
          // committed location of the same artifact may still be usable.
        }
      }
    }
    final copy = await resolveLocalCopy(artifact, root);
    return copy == null
        ? null
        : _path(p.join(
            copy.observation.destinationRoot, copy.observation.relativePath));
  }

  /// Current read-only evidence, never an installed/removable manifest.
  Future<JournaledByteObservation?> resolveLocalCopy(
      RemoteArtifact artifact, String root) async {
    final observations =
        await _observedCopies(root, artifactKey: artifact.id.key);
    for (final entry in observations.aliases.entries) {
      if (observations.current.contains(entry.key) &&
          InstallationSnapshot.sameContent(
              entry.value.observation.artifact, artifact)) {
        return entry.value;
      }
    }
    return null;
  }

  Future<void> requireInstallation(
      TransferRecord record, InstalledArtifact? manifest,
      {String? bundleOwner}) async {
    const equality = DeepCollectionEquality();
    if (['.zip', '.7z', '.rar']
            .any(record.relativePath.toLowerCase().endsWith) &&
        !TransferRecord.supportsArchiveMapping(
            record.relativePath, record.archivePlatformId)) {
      throw const OwnedStorageException('unsupported_archive');
    }
    if (record.lifecycle != TransferLifecycle.completed ||
        (record.bundleOwner != null && record.bundleOwner != bundleOwner) ||
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
    if (record.bundleMembers.isNotEmpty) {
      List<InstalledArtifact> members;
      try {
        members = await journal.bundleInstallations(record);
      } on StateError {
        throw const OwnedStorageException('changed');
      }
      if (!equality.equals(
          [for (final member in manifest.dependencies) member.toJson()],
          [for (final member in members) member.toJson()])) {
        throw const OwnedStorageException('changed');
      }
      for (final member in members) {
        await requireInstallation(
            (await journal.transfer(member.transferId))!, member,
            bundleOwner: record.id);
      }
    } else if (manifest.dependencies.isNotEmpty) {
      throw const OwnedStorageException('changed');
    }
  }
}

class InstallationSnapshot {
  final InstallationPathClaims _targets;
  final InstallationPathClaims _published;
  final InstallationPathClaims _copies;
  final Map<String, List<MapEntry<String, InstalledArtifact>>> _byArtifact;
  final Map<String, List<MapEntry<String, InstalledArtifact>>> _byFoldedPath;
  final Map<String, InstalledArtifact> installed;

  /// Current verified read-only copies, deliberately NOT installed ownership.
  final Map<String, JournaledByteObservation> localCopies;

  /// Stable cache identities for matching or missing historical copies only.
  /// A changed/inaccessible local path cannot supply an alias.
  final Map<String, RemoteArtifact> legacyAliases;
  InstallationSnapshot._(
      Set<String> targets,
      Set<String> published,
      Map<String, InstalledArtifact> installed,
      Map<String, JournaledByteObservation> localCopies,
      Map<String, RemoteArtifact> legacyAliases)
      : _targets = InstallationPathClaims(targets),
        _published = InstallationPathClaims(published),
        _copies = InstallationPathClaims(localCopies.keys),
        _byArtifact =
            groupBy(installed.entries, (entry) => entry.value.artifact.id.key),
        _byFoldedPath =
            groupBy(installed.entries, (entry) => entry.key.toLowerCase()),
        installed = Map.unmodifiable(installed),
        localCopies = Map.unmodifiable(localCopies),
        legacyAliases = Map.unmodifiable(legacyAliases);

  /// Managed paths never fall back to filename identity. A folder enclosing a
  /// managed member is not safe for legacy recursive sharing/removal either.
  bool allowsLegacy(String path) =>
      !_published.overlaps(path) && !_copies.overlaps(path);
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
    for (final entry in localCopies.entries) {
      if (sameContent(entry.value.observation.artifact, artifact)) {
        return entry.key;
      }
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
          else if (localCopies[_path(p.join(root, game.filename))]
              case final copy?)
            game.copyWith(remoteArtifact: copy.observation.artifact)
          else if (allowsLegacy(p.join(root, game.filename)))
            game,
      ];
}

String _path(String value) => installationPath(value);
