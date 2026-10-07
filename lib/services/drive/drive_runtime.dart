import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../models/config/drive_source_config.dart';
import '../../models/config/provider_config.dart';
import '../../models/config/source.dart';
import '../../models/library_identity.dart';
import '../../models/local_cloud_byte_observation.dart';
import '../../models/owned_removal_record.dart';
import '../../models/transfer_record.dart';
import '../database_service.dart';
import '../installation_index.dart';
import '../installation_paths.dart';
import '../owned_storage.dart';
import '../owned_installation_removal.dart';
import '../transfer_journal.dart';
import '../stage_retirement.dart';
import '../owned_replacement.dart';
import '../metadata/metadata_provider.dart';
import 'drive_api.dart';
import 'drive_authorization.dart';
import 'drive_catalogue.dart';
import 'drive_download_boundary.dart';
import 'drive_media.dart';
import 'drive_transfer_engine.dart';
import 'drive_verification.dart';
import 'drive_bundle.dart';
import 'google_drive_sign_in.dart';

export '../../models/local_cloud_byte_observation.dart';

/// Bounded diagnostics for one offline maintenance pass, never artifact data.
class StageRetirementRecoveryReport {
  final int examined;
  final int retired;
  final int pending;
  final int skippedActive;
  final bool stopped;
  final Map<String, int> issues;
  StageRetirementRecoveryReport(
      {this.examined = 0,
      this.retired = 0,
      this.pending = 0,
      this.skippedActive = 0,
      this.stopped = false,
      Map<String, int> issues = const {}})
      : issues = Map.unmodifiable(issues);
}

typedef OwnedRemovalRecoveryReport = ({
  int examined,
  int removed,
  int pending,
  int skippedActive,
  bool stopped,
  Map<String, int> issues,
});

/// Process-wide native account lane and source-scoped refresh/transfer jobs. No token
/// resides in provider configs or download items. Background calls never consent.
class DriveRuntime {
  static final instance = DriveRuntime();
  DriveCatalogue? _catalogue;
  DriveCatalogue get catalogue =>
      _catalogue ??= DriveCatalogue(DatabaseService().database);
  TransferJournal? _journal;
  TransferJournal get journal =>
      _journal ??= TransferJournal(DatabaseService().database);
  final OwnedStorage _storage;
  final DriveAuthorization Function(String) _createAuthorization;
  final DriveApi Function(DriveAuthorization, String) _createApi;
  final DriveMediaApi Function(DriveAuthorization, String) _createMediaApi;
  DriveAuthorization? _authorization;
  String? _clientId;
  final _apis = <String, DriveApi>{};
  final _mediaApis = <String, DriveMediaApi>{};
  final _startingTransfers = <String>{};
  final _reservations = <String, Future<TransferRecord>>{};
  final _transfers = <String, DriveTransferOperation>{};
  final _transferResults = <String, Future<void>>{};
  final _refreshes = <String, Future<void>>{};
  final _refreshCancellation = <String, CancelToken>{};
  final _bundlePlans = <CancelToken, Future<TransferRecord>>{};
  final _metadataHeaders = <CancelToken, Future<Uint8List>>{};
  final _metadataArchives = <CancelToken, Future<MetadataRomIdentifier?>>{};
  final _recoveryReviews = <CancelToken, Future<DriveLocalCloudObservation>>{};
  bool _disconnecting = false;
  int _laneGeneration = 0;

  DriveRuntime(
      {DriveCatalogue? catalogue,
      TransferJournal? journal,
      OwnedStorage? storage,
      DriveApi Function(DriveAuthorization, String)? createApi,
      DriveMediaApi Function(DriveAuthorization, String)? createMediaApi,
      DriveAuthorization Function(String)? createAuthorization})
      : _catalogue = catalogue,
        _journal = journal,
        _storage = storage ?? const OwnedStorage(),
        _createApi = createApi ??
            ((authorization, account) =>
                DriveApi(authorization: authorization, accountId: account)),
        _createMediaApi = createMediaApi ??
            ((authorization, account) => DriveMediaApi(
                authorization: authorization, accountId: account)),
        _createAuthorization = createAuthorization ??
            ((id) => DriveAuthorization(GoogleDriveSignIn(serverClientId: id)));

  /// Durable exact-file reservation for the normal queue. This creates no ROM
  /// bytes and performs no online requests. A repeated intent finds the same
  /// journal record, including after a crash before queue preferences were saved.
  Future<TransferRecord> reserveTransfer({
    required ProviderConfig config,
    required RemoteArtifact artifact,
    required String destinationRoot,
    required String relativePath,
    String? archivePlatformId,
  }) async {
    _requireConnectedLane();
    _requireArtifactSource(config, artifact);
    DriveVerification(artifact);
    if (relativePath != artifact.displayName ||
        relativePath.isEmpty ||
        relativePath == '.' ||
        relativePath == '..' ||
        RegExp(r'[\\/\x00-\x1f<>:"|?*]').hasMatch(relativePath)) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
    final id = sha256
        .convert(utf8.encode(jsonEncode([
          artifact.id.key,
          artifact.version,
          destinationRoot,
          relativePath
        ])))
        .toString();
    final existing = _reservations[id];
    if (existing != null) {
      final record = await existing;
      _requireReservationSnapshot(record, artifact);
      if (record.archivePlatformId != archivePlatformId) throw const OwnedStorageException('changed');
      return record;
    }
    final generation = _laneGeneration;
    final reservation = () async {
      final plan = await _storage.prepare(destinationRoot);
      _requireConnectedLane();
      if (generation != _laneGeneration) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.cancelled);
      }
      if (plan.destinationRoot != destinationRoot) {
        throw const OwnedStorageException('changed');
      }
      final existing = await journal.transfer(id);
      if (existing != null) {
        _requireReservationSnapshot(existing, artifact);
        if (existing.archivePlatformId != archivePlatformId) throw const OwnedStorageException('changed');
        final expectedPath = existing.replacesInstallation == null
            ? relativePath
            : _replacementPath(relativePath, id);
        if (existing.destinationRoot != destinationRoot ||
            existing.relativePath != expectedPath ||
            existing.stagePath != plan.stagePath(id)) {
          throw const OwnedStorageException('changed');
        }
        return existing;
      }
      InstalledArtifact? previous;
      final index = InstallationIndex(journal, storage: _storage);
      await for (final row in journal.targetsInRoot(destinationRoot,
          artifactKey: artifact.id.key)) {
        final installed = row.installation;
        if (installed == null ||
            row.transfer.lifecycle != TransferLifecycle.completed ||
            row.transfer.bundleOwner != null ||
            await journal.hasCommittedReplacement(installed.id)) {
          continue;
        }
        await index.requireInstallation(row.transfer, installed);
        if (InstallationSnapshot.sameContent(installed.artifact, artifact)) {
          if (row.transfer.archivePlatformId != archivePlatformId) throw const OwnedStorageException('changed');
          return row.transfer;
        }
        if (previous != null) {
          throw const OwnedStorageException('replacement_pending');
        }
        previous = installed;
      }
      final target =
          previous == null ? relativePath : _replacementPath(relativePath, id);
      return journal.create(TransferRecord(
          id: id,
          artifact: artifact,
          destinationRoot: destinationRoot,
          relativePath: target,
          archivePlatformId: archivePlatformId,
          replacesInstallation: previous,
          stagePath: plan.stagePath(id)));
    }();
    _reservations[id] = reservation;
    try {
      return await reservation;
    } finally {
      if (identical(_reservations[id], reservation)) _reservations.remove(id);
    }
  }

  static String _replacementPath(String name, String id) =>
      '${String.fromCharCodes(p.basenameWithoutExtension(name).runes.take(32))}.rshop-$id${p.extension(name)}';

  Future<TransferRecord> reserveBundle(
      {required ProviderConfig config,
      required RemoteArtifact artifact,
      required String destinationRoot,
      required Set<String> supportedExtensions,
      required CancelToken cancellation,
      String? transferId}) async {
    _requireConnectedLane();
    _requireArtifactSource(config, artifact);
    if (!BundleReferences.isManifest(artifact.displayName)) {
      throw const BundleLayoutException('unsupported_layout');
    }
    if (artifact.displayName != p.posix.basename(artifact.displayName)) {
      throw const BundleLayoutException('unsafe_path');
    }
    final operation = _reserveBundle(config, artifact, destinationRoot,
        supportedExtensions, cancellation, transferId);
    _bundlePlans[cancellation] = operation;
    try {
      return await operation;
    } finally {
      _bundlePlans.remove(cancellation);
    }
  }

  Future<TransferRecord> _reserveBundle(
      ProviderConfig config,
      RemoteArtifact artifact,
      String root,
      Set<String> extensions,
      CancelToken cancellation,
      String? savedId) async {
    void check() {
      _requireConnectedLane();
      if (cancellation.isCancelled) {
        throw const DriveTransferException(DriveTransferIssue.cancelled);
      }
    }

    check();
    if (savedId != null) {
      final existing = await journal.transfer(savedId);
      if (existing == null ||
          existing.bundleMembers.isEmpty ||
          existing.destinationRoot != root) {
        throw const OwnedStorageException('changed');
      }
      _requireReservationSnapshot(existing, artifact);
      return existing;
    }
    final drive = config.drive!;
    final generation = await catalogue.activeGeneration(
        sourceId: config.sourceId!,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId);
    if (generation == null) {
      throw const DriveCatalogueException('refreshRequired');
    }
    final graph = <({RemoteArtifact artifact, String path})>[];
    final paths = <String, RemoteArtifact>{};
    final visiting = <String>{};
    var headerBytes = 0;
    Future<void> visit(RemoteArtifact current, String path) async {
      check();
      DriveVerification(current);
      if (!paths.containsKey(path.toLowerCase()) &&
          paths.length >= BundleReferences.maxMembers + 1) {
        throw const BundleLayoutException('unsupported_layout');
      }
      if (paths[path.toLowerCase()] case final prior?) {
        if (!const DeepCollectionEquality()
                .equals(prior.toJson(), current.toJson()) ||
            visiting.contains(current.id.key)) {
          throw const BundleLayoutException('ambiguous_or_cyclic');
        }
        return;
      }
      paths[path.toLowerCase()] = current;
      if (BundleReferences.isManifest(current.displayName)) {
        if (!visiting.add(current.id.key)) {
          throw const BundleLayoutException('ambiguous_or_cyclic');
        }
        if (current.sizeBytes! > BundleReferences.maxHeaderBytes ||
            headerBytes + current.sizeBytes! >
                4 * BundleReferences.maxHeaderBytes) {
          throw const BundleLayoutException('unsupported_layout');
        }
        headerBytes += current.sizeBytes!;
        final boundary = DriveDownloadBoundary(
            config: config,
            artifact: current,
            catalogue: catalogue,
            api: apiFor(drive));
        await boundary.revalidate(cancellation: cancellation);
        check();
        final media = _mediaApis.putIfAbsent(
            drive.accountId,
            () => _createMediaApi(
                authorizationFor(drive.serverClientId), drive.accountId));
        final response =
            await media.open(current, offset: 0, cancelToken: cancellation);
        final bytes = BytesBuilder(copy: false);
        await DriveVerification(current).verifyBytes(
            response.bytes.map((chunk) {
          bytes.add(chunk);
          return chunk;
        }), cancellation: cancellation);
        await boundary.revalidate(cancellation: cancellation);
        for (final reference
            in BundleReferences.parse(current.displayName, bytes.takeBytes())) {
          check();
          final entry = await catalogue.requireRelativeBinary(
              sourceId: config.sourceId!,
              accountId: drive.accountId,
              rootFolderId: drive.rootFolderId,
              parentId: current.parentId!,
              segments: reference.split('/'),
              generation: generation);
          final child = entry.file.artifact(
              sourceId: config.sourceId!,
              accountId: drive.accountId,
              displayPath: entry.displayPath);
          if (!BundleReferences.isManifest(child.displayName) &&
              !extensions.contains(
                  p.posix.extension(child.displayName).toLowerCase())) {
            throw const BundleLayoutException('unsupported_member_format');
          }
          await visit(
              child,
              BundleReferences.safePath(
                  p.posix.join(p.posix.dirname(path), reference)));
        }
        visiting.remove(current.id.key);
      }
      graph.add((artifact: current, path: path));
    }

    await visit(artifact, BundleReferences.safePath(artifact.displayName));
    check();
    final id = sha256
        .convert(utf8.encode(jsonEncode([
          artifact.id.key,
          root,
          for (final member in graph) [member.path, member.artifact.toJson()]
        ])))
        .toString();
    final current = await journal.transfer(id);
    if (current != null) return current;
    final namespace = 'rshop-bundle-$id';
    final plan = await _storage.prepare(root);
    if (plan.destinationRoot != root) {
      throw const OwnedStorageException('changed');
    }
    check();
    InstalledArtifact? previous;
    await for (final row
        in journal.targetsInRoot(root, artifactKey: artifact.id.key)) {
      if (row.transfer.bundleOwner != null ||
          row.installation == null ||
          row.transfer.lifecycle != TransferLifecycle.completed ||
          await journal.hasCommittedReplacement(row.installation!.id)) {
        continue;
      }
      await InstallationIndex(journal, storage: _storage)
          .requireInstallation(row.transfer, row.installation);
      if (previous != null) {
        throw const OwnedStorageException('replacement_pending');
      }
      previous = row.installation;
    }
    final members = [
      for (final member in graph.take(graph.length - 1))
        TransferBundleMember(
            transferId: sha256
                .convert(utf8.encode('$id\u0000${member.path}'))
                .toString(),
            artifact: member.artifact,
            relativePath: '$namespace/${member.path}')
    ];
    return journal.create(TransferRecord(
        id: id,
        artifact: artifact,
        destinationRoot: root,
        relativePath: '$namespace/${artifact.displayName}',
        stagePath: plan.stagePath(id),
        bundleMembers: members,
        replacesInstallation: previous));
  }

  Future<TransferRecord> reserveBundleMember(
      TransferRecord parent, TransferBundleMember member) async {
    _requireConnectedLane();
    final old = await journal.transfer(member.transferId);
    if (old != null) return old;
    final plan = await _storage.prepare(parent.destinationRoot);
    _requireConnectedLane();
    return journal.create(TransferRecord(
        id: member.transferId,
        artifact: member.artifact,
        destinationRoot: parent.destinationRoot,
        relativePath: member.relativePath,
        stagePath: plan.stagePath(member.transferId),
        bundleOwner: parent.id));
  }

  static void _requireReservationSnapshot(
      TransferRecord record, RemoteArtifact artifact) {
    if (!const DeepCollectionEquality()
        .equals(record.artifact.toJson(), artifact.toJson())) {
      throw const DriveTransferException(DriveTransferIssue.sourceChanged);
    }
  }

  static void _requireArtifactSource(
      ProviderConfig config, RemoteArtifact artifact) {
    if (config.type != ProviderType.drive ||
        config.drive?.isConfigured != true ||
        config.sourceId?.isNotEmpty != true ||
        config.path?.isNotEmpty != true ||
        artifact.id.providerId != 'drive' ||
        artifact.id.sourceId != config.sourceId ||
        artifact.id.accountId != config.drive!.accountId) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
  }

  /// Explicit one-file recovery review, including unmanaged namesakes. Uses
  /// pinned read-only native IO and current rooted Drive boundaries. No transfer
  /// reservation, publication, installation claim, or namespace mutation occurs.
  Future<DriveLocalCloudObservation> verifyLocalCloudBytes({
    required ProviderConfig config,
    required RemoteArtifact artifact,
    required String destinationRoot,
    required String relativePath,
    required CancelToken cancellation,
  }) => _compareLocalCloudBytes(config: config, artifact: artifact,
      destinationRoot: destinationRoot, relativePath: relativePath,
      cancellation: cancellation);

  /// Explicitly adopts one standalone file, never a saved observation, bundle,
  /// unsupported archive or title-based namesake. Ownership does not authorize migration.
  static String? _archiveMapping(String filename, Set<String> extensions) {
    final ext = p.posix.extension(filename).toLowerCase();
    final mapped = extensions.map((e) => e.toLowerCase()).toSet();
    if (ext == '.zip' && mapped.length == 1 && mapped.contains('.gg')) {
      return 'gamegear';
    }
    if (ext == '.7z' && mapped.length == 1 && mapped.contains('.gb')) {
      return 'gb';
    }
    if (ext == '.7z' && mapped.length == 1 && mapped.contains('.gbc')) {
      return 'gbc';
    }
    if (ext == '.7z' && mapped.length == 1 && mapped.contains('.gba')) {
      return 'gba';
    }
    if ((ext == '.7z' || ext == '.zip') && mapped.length == 3 &&
        mapped.containsAll(const {'.z64', '.n64', '.v64'})) {
      return 'n64';
    }
    return null;
  }

  static bool supportsStandaloneAdoption(String filename, Set<String> extensions) {
    final extension = p.posix.extension(filename).toLowerCase();
    if (_archiveMapping(filename, extensions) != null) return true;
    return extensions.map((e) => e.toLowerCase()).contains(extension) &&
        !BundleReferences.isManifest(filename) &&
        !{'.zip', '.7z', '.rar', '.gz', '.gdi'}.contains(extension);
  }

  Future<InstalledArtifact> adoptLocalCloudBytes({
    required ProviderConfig config,
    required RemoteArtifact artifact,
    required String destinationRoot,
    required String relativePath,
    required Set<String> supportedExtensions,
    required CancelToken cancellation,
  }) async {
    if (!supportsStandaloneAdoption(artifact.displayName, supportedExtensions)) {
      throw const BundleLayoutException('unsupported_member_format');
    }
    late InstalledArtifact installation;
    await InstallationMutations.run(p.join(destinationRoot, relativePath), () async {
      final claims = await InstallationIndex(journal, storage: _storage)
          .scan(destinationRoot, verifyInstalled: false);
      if (claims.protects(p.join(destinationRoot, relativePath))) {
        throw StateError('Adoption target already has an owner');
      }
      await _compareLocalCloudBytes(config: config, artifact: artifact,
          destinationRoot: destinationRoot, relativePath: relativePath,
          cancellation: cancellation,
          archivePlatformId: _archiveMapping(artifact.displayName, supportedExtensions),
          onVerified: (observation, stagePath, check) async {
            await DriveDownloadBoundary(config: config, artifact: artifact,
                catalogue: catalogue, api: apiFor(config.drive!))
                .revalidate(cancellation: cancellation);
            // Close acknowledgement can itself be asynchronous. Recheck after it
            // rather than treating the earlier descriptor observation as current.
            final current = await _storage.inspect(destinationRoot: destinationRoot,
                relativePath: relativePath, stagePath: stagePath, published: true);
            if (current == null || !observation.localIdentity.matches(current)) {
              throw const OwnedStorageException('changed');
            }
            check();
            final random = Random.secure();
            final id = 'adoption-${List.generate(16, (_) => random.nextInt(256)
                .toRadixString(16).padLeft(2, '0')).join()}';
            installation = await journal.adoptVerifiedFile(observation, id: id,
                stagePath: stagePath, checkCancellation: check,
                archivePlatformId: _archiveMapping(artifact.displayName, supportedExtensions));
          });
    });
    return installation;
  }

  Future<DriveLocalCloudObservation> _compareLocalCloudBytes({
    required ProviderConfig config,
    required RemoteArtifact artifact,
    required String destinationRoot,
    required String relativePath,
    required CancelToken cancellation,
    Future<void> Function(DriveLocalCloudObservation, String, void Function())? onVerified,
    String? archivePlatformId,
  }) async {
    _requireConnectedLane();
    _requireArtifactSource(config, artifact);
    final verification = DriveVerification(artifact);
    if (_recoveryReviews.isNotEmpty ||
        relativePath != artifact.displayName ||
        relativePath.isEmpty ||
        relativePath == '.' ||
        relativePath == '..' ||
        RegExp(r'[\\/\x00-\x1f<>:"|?*]').hasMatch(relativePath)) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
    void checkCancellation() {
      if (cancellation.isCancelled) {
        throw const DriveTransferException(DriveTransferIssue.cancelled);
      }
    }

    final operation = () async {
      checkCancellation();
      final plan = await _storage.prepare(destinationRoot);
      if (plan.destinationRoot != destinationRoot) {
        throw const OwnedStorageException('changed');
      }
      final stagePath = plan.stagePath('recovery-review');
      final identity = await _storage.inspect(
          destinationRoot: destinationRoot,
          relativePath: relativePath,
          stagePath: stagePath,
          published: true);
      if (identity == null) throw const OwnedStorageException('not_found');
      if (identity.sizeBytes != artifact.sizeBytes) {
        throw const DriveTransferException(DriveTransferIssue.truncated);
      }
      checkCancellation();
      final session = await _storage.open(
          destinationRoot: destinationRoot,
          relativePath: relativePath,
          stagePath: stagePath,
          durableOffset: identity.sizeBytes,
          expectedIdentity: identity,
          published: true);
      late DriveLocalCloudObservation observation;
      try {
        final local = await verification.verifyBytes(
            session.bytes(identity.sizeBytes),
            cancellation: cancellation);
        final boundary = DriveDownloadBoundary(
            config: config,
            artifact: artifact,
            catalogue: catalogue,
            api: apiFor(config.drive!));
        await boundary.revalidate(cancellation: cancellation);
        final media = _mediaApis.putIfAbsent(
            config.drive!.accountId,
            () => _createMediaApi(
                authorizationFor(config.drive!.serverClientId),
                config.drive!.accountId));
        final response =
            await media.open(artifact, offset: 0, cancelToken: cancellation);
        final cloud = await verification.verifyBytes(response.bytes,
            cancellation: cancellation);
        await boundary.revalidate(cancellation: cancellation);
        // Stat alone cannot detect coarse-timestamp/same-size overwrites.
        final finalLocal = await verification.verifyBytes(
            session.bytes(identity.sizeBytes),
            cancellation: cancellation);
        if (archivePlatformId != null) {
          if (archivePlatformId == 'gamegear') {
            await session.validateGameGearZip();
          } else if (const {'gb', 'gbc', 'gba'}.contains(archivePlatformId)) {
            await session.validateGameBoySevenZip(archivePlatformId);
          } else {
            await session.validateN64Archive(relativePath);
          }
          checkCancellation();
        }
        final current = await _storage.inspect(
            destinationRoot: destinationRoot,
            relativePath: relativePath,
            stagePath: stagePath,
            published: true);
        if (cloud['sha256'] != local['sha256'] ||
            finalLocal['sha256'] != cloud['sha256'] ||
            !identity.matches(await session.checkpoint()) ||
            current == null ||
            !identity.matches(current)) {
          throw const OwnedStorageException('changed');
        }
        checkCancellation();
        observation = DriveLocalCloudObservation(
            artifact: artifact,
            destinationRoot: destinationRoot,
            relativePath: relativePath,
            localIdentity: identity,
            sizeBytes: identity.sizeBytes,
            checksums: cloud,
            observedAt: DateTime.now().toUtc());
      } finally {
        await session.close();
      }
      checkCancellation();
      await journal.saveByteObservation(observation);
      checkCancellation();
      await onVerified?.call(observation, stagePath, checkCancellation);
      // An adoption commit that won the cancellation race remains truthful.
      return observation;
    }();
    _recoveryReviews[cancellation] = operation;
    try {
      return await operation;
    } finally {
      _recoveryReviews.remove(cancellation);
    }
  }

  /// Reading a saved observation is local-only and does not require sign-in.
  Future<DriveLocalCloudObservation?> savedLocalCloudObservation({
    required RemoteArtifact artifact,
    required String destinationRoot,
    required String relativePath,
  }) =>
      journal.latestByteObservation(
          artifactId: artifact.id,
          destinationRoot: destinationRoot,
          relativePath: relativePath);

  /// Read only the supported CHD header, within the existing account/source lane.
  /// This is metadata evidence, not verification or installation of ROM bytes.
  Future<Uint8List> readMetadataHeader(
      {required ProviderConfig config,
      required RemoteArtifact artifact,
      required CancelToken cancellation}) async {
    _requireConnectedLane();
    _requireArtifactSource(config, artifact);
    if (!artifact.displayName.toLowerCase().endsWith('.chd') ||
        (artifact.sizeBytes ?? 0) < 140 ||
        _metadataHeaders.containsKey(cancellation)) {
      throw const DriveTransferException(DriveTransferIssue.invalidSource);
    }
    final operation = () async {
      final api = apiFor(config.drive!);
      final boundary = DriveDownloadBoundary(
          config: config, artifact: artifact, catalogue: catalogue, api: api);
      await boundary.revalidate(cancellation: cancellation);
      final media = _mediaApis.putIfAbsent(
          config.drive!.accountId,
          () => _createMediaApi(authorizationFor(config.drive!.serverClientId),
              config.drive!.accountId));
      final response = await media.open(artifact,
          offset: 0, endInclusive: 139, cancelToken: cancellation);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.bytes) {
        if (cancellation.isCancelled) {
          throw const DriveTransferException(DriveTransferIssue.cancelled);
        }
        bytes.add(chunk);
      }
      await boundary.revalidate(cancellation: cancellation);
      return bytes.takeBytes();
    }();
    _metadataHeaders[cancellation] = operation;
    try {
      return await operation;
    } finally {
      _metadataHeaders.remove(cancellation);
    }
  }

  /// Metadata only: no media request, staging, extraction or ownership change.
  Future<MetadataRomIdentifier?> readMetadataArchive(
      {required ProviderConfig config,
      required RemoteArtifact artifact,
      required String platformId,
      required String destinationRoot,
      required CancelToken cancellation}) async {
    _requireConnectedLane();
    _requireArtifactSource(config, artifact);
    final name = artifact.displayName;
    final extension = p.extension(name).toLowerCase();
    if (!(platformId == 'n64' && {'.7z', '.zip'}.contains(extension) ||
            platformId == 'gamegear' && extension == '.zip' ||
            {'gb', 'gbc', 'gba'}.contains(platformId) && extension == '.7z') ||
        name.contains(RegExp(r'[/\\:\x00-\x1f\x7f]')) ||
        name.startsWith('.') ||
        (artifact.sizeBytes ?? 0) <= 0 ||
        artifact.sizeBytes! >
            (platformId == 'gba'
                        ? 32
                        : {'gb', 'gbc'}.contains(platformId)
                            ? 16
                            : 128) *
                    1024 *
                    1024 +
                3 * 65536 ||
        _metadataArchives.containsKey(cancellation)) {
      return null;
    }
    final verification = DriveVerification(artifact);
    void checkCancellation() {
      if (cancellation.isCancelled) {
        throw const DriveTransferException(DriveTransferIssue.cancelled);
      }
    }

    final operation = () async {
      checkCancellation();
      final boundary = DriveDownloadBoundary(
          config: config,
          artifact: artifact,
          catalogue: catalogue,
          api: apiFor(config.drive!));
      await boundary.revalidate(cancellation: cancellation);
      Map<String, Object?> observation;
      // Absent/unsupported local files are ordinary title-discovery outcomes;
      // do not request cloud ROM bodies to compensate for missing local bytes.
      try {
        observation = await _storage.readArchiveIdentifier(
            destinationRoot: destinationRoot,
            relativePath: name,
            platformId: platformId);
      } on OwnedStorageException catch (error) {
        if ({
          'not_found',
          'access_denied',
          'unsupported_archive',
          'unsupported',
          'changed',
          'invalid_arguments'
        }.contains(error.code)) {
          return null;
        }
        rethrow;
      }
      checkCancellation();
      final container =
          (observation['container'] as Map).cast<String, Object?>();
      if (container['sizeBytes'] != artifact.sizeBytes ||
          verification.checksums.entries
              .any((e) => container[e.key] != e.value)) {
        return null;
      }
      final raw = MetadataRomIdentifier.fromJson(
          (observation['raw'] as Map).cast<String, dynamic>());
      final allowed = switch (platformId) {
        'n64' => {'.z64', '.n64', '.v64'},
        'gb' => {'.gb'},
        'gbc' => {'.gb', '.gbc'},
        'gba' => {'.gba'},
        _ => {'.gg'},
      };
      if (raw.kind != RomIdentifierKind.rawRom ||
          raw.sizeBytes <= 0 ||
          raw.sizeBytes >
              (platformId == 'n64'
                      ? 128
                      : platformId == 'gba'
                          ? 32
                          : 16) *
                  1024 *
                  1024 ||
          raw.filename.startsWith('.') ||
          raw.filename.contains(RegExp(r'[/\\:\x00-\x1f\x7f]')) ||
          !allowed.contains(p.extension(raw.filename).toLowerCase()) ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(raw.md5 ?? '') ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(raw.sha1 ?? '') ||
          RegExp(r'^0+$').hasMatch(raw.md5!) ||
          RegExp(r'^0+$').hasMatch(raw.sha1!)) {
        throw const DriveTransferException(DriveTransferIssue.invalidResponse);
      }
      await boundary.revalidate(cancellation: cancellation);
      checkCancellation();
      return raw;
    }();
    _metadataArchives[cancellation] = operation;
    try {
      return await operation;
    } finally {
      _metadataArchives.remove(cancellation);
    }
  }

  /// Offline revalidation of an already committed exact installation. A saved
  /// completed bit is not proof that another app has left its bytes in place.
  Future<void> requireInstalledTransfer(TransferRecord record,
      {String? bundleOwner}) async {
    final installation = await journal.installationForTarget(
        destinationRoot: record.destinationRoot,
        relativePath: record.relativePath);
    await InstallationIndex(journal, storage: _storage)
        .requireInstallation(record, installation, bundleOwner: bundleOwner);
    if (record.archivePlatformId != null) {
      final session = await _storage.open(destinationRoot: record.destinationRoot,
          relativePath: record.relativePath, stagePath: record.stagePath,
          durableOffset: record.durableOffset, expectedIdentity: installation!.fileIdentity,
          published: true);
      try {
        if (record.archivePlatformId == 'gamegear') {
          await session.validateGameGearZip();
        } else if (const {'gb', 'gbc', 'gba'}.contains(record.archivePlatformId)) {
          await session.validateGameBoySevenZip(record.archivePlatformId!);
        } else {
          await session.validateN64Archive(record.relativePath);
        }
      } finally { await session.close(); }
    }
  }

  Future<TransferRecord> finishRetainedStage(TransferRecord record) =>
      retireCommittedStage(journal, _storage, record);

  Future<String?> finishReplacement(TransferRecord record) =>
      retireReplacedInstallation(journal, _storage, record);

  Future<void> recoverPendingReplacements(
      {bool Function()? shouldContinue}) async {
    await for (final record
        in journal.pendingReplacements(shouldContinue: shouldContinue)) {
      if (!(shouldContinue?.call() ?? true)) return;
      if (_startingTransfers.contains(record.id) ||
          _transfers.containsKey(record.id)) {
        continue;
      }
      await finishReplacement(record);
    }
  }

  /// Explicit removal intents survive queue loss and account sign-out. One
  /// offline pass resumes them; conflicts remain for review, never busy retries.
  /// Shutdown stops between intents and joins the current namespace mutation.
  Future<OwnedRemovalRecoveryReport> recoverPendingRemovals(
      {bool Function()? shouldContinue}) async {
    var examined = 0, removed = 0, pending = 0, skippedActive = 0;
    var stopped = false;
    final issues = <String, int>{};
    void addIssue(String code) =>
        issues.update(code, (count) => count + 1, ifAbsent: () => 1);
    bool canContinue() {
      if (shouldContinue?.call() ?? true) return true;
      stopped = true;
      return false;
    }

    StreamIterator<OwnedRemovalRecord>? records;
    if (canContinue()) {
      try {
        records = StreamIterator(
            journal.pendingRemovals(shouldContinue: canContinue));
        final remover = OwnedInstallationRemoval(journal, storage: _storage);
        while (canContinue() && await records.moveNext()) {
          if (!canContinue()) break;
          final record = records.current;
          examined++;
          if (_startingTransfers.contains(record.installation.transferId) ||
              _transfers.containsKey(record.installation.transferId)) {
            skippedActive++;
            continue;
          }
          try {
            await remover.recover(record.id);
            removed++;
          } on OwnedStorageException catch (error) {
            pending++;
            // The native adapter exposes only its bounded machine-code enum.
            addIssue(error.code);
          } catch (_) {
            pending++;
            addIssue('removal_pending');
          }
        }
      } catch (_) {
        addIssue('journal_unavailable');
      } finally {
        try {
          await records?.cancel();
        } catch (_) {
          addIssue('journal_unavailable');
        }
      }
    }
    return (
      examined: examined,
      removed: removed,
      pending: pending,
      skippedActive: skippedActive,
      stopped: stopped,
      issues: Map<String, int>.unmodifiable(issues)
    );
  }

  /// One offline pass over durable cleanup intents, including installs whose
  /// completed queue rows were not persisted. Live operations own their inline
  /// cleanup; the shared helper serializes every other attempt by target path.
  Future<StageRetirementRecoveryReport> recoverPendingStageRetirements(
      {bool Function()? shouldContinue}) async {
    var examined = 0;
    var retired = 0;
    var pending = 0;
    var skippedActive = 0;
    var stopped = false;
    final issues = <String, int>{};
    void addIssue(String? issue) {
      const known = {
        'invalid_arguments',
        'collision',
        'not_found',
        'unsupported',
        'cross_volume',
        'out_of_space',
        'access_denied',
        'changed',
        'closed',
        'io_error',
        'close_unconfirmed',
        'retirement_pending',
        'journal_unavailable',
      };
      final code = known.contains(issue) ? issue! : 'retirement_pending';
      issues.update(code, (count) => count + 1, ifAbsent: () => 1);
    }

    bool canContinue() {
      if (shouldContinue?.call() ?? true) return true;
      stopped = true;
      return false;
    }

    StreamIterator<TransferRecord>? records;
    if (canContinue()) {
      try {
        records = StreamIterator(
            journal.pendingStageRetirements(shouldContinue: canContinue));
        while (canContinue() && await records.moveNext()) {
          if (!canContinue()) break;
          final record = records.current;
          examined++;
          if (_startingTransfers.contains(record.id) ||
              _transfers.containsKey(record.id)) {
            skippedActive++;
            continue;
          }
          try {
            final result = await finishRetainedStage(record);
            if (result.stageRetired) {
              retired++;
            } else {
              pending++;
              addIssue(result.stageRetirementIssue ?? 'retirement_pending');
            }
          } catch (_) {
            // Cleanup cannot alter the already committed installation outcome.
            pending++;
            addIssue('retirement_pending');
          }
        }
      } catch (_) {
        addIssue('journal_unavailable');
      } finally {
        try {
          await records?.cancel();
        } catch (_) {
          addIssue('journal_unavailable');
        }
      }
    }
    return StageRetirementRecoveryReport(
        examined: examined,
        retired: retired,
        pending: pending,
        skippedActive: skippedActive,
        stopped: stopped,
        issues: issues);
  }

  /// Starts only an already reserved exact transfer. The normal queue remains
  /// responsible for choosing when to invoke this API; it does not enqueue files.
  Future<DriveTransferOperation> startTransfer({
    required ProviderConfig config,
    required String transferId,
    void Function(TransferRecord)? onCheckpoint,
  }) async {
    _requireConnectedLane();
    final drive = config.drive;
    if (config.type != ProviderType.drive ||
        drive == null ||
        !drive.isConfigured ||
        config.sourceId?.isNotEmpty != true ||
        config.path?.isNotEmpty != true) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    if (_transfers.containsKey(transferId) ||
        !_startingTransfers.add(transferId)) {
      throw StateError('Transfer already active');
    }
    final generation = _laneGeneration;
    try {
      final record = await journal.transfer(transferId);
      _requireConnectedLane();
      if (generation != _laneGeneration) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.cancelled);
      }
      if (record == null) throw StateError('Unknown transfer');
      if (record.artifact.id.providerId != 'drive' ||
          record.artifact.id.sourceId != config.sourceId ||
          record.artifact.id.accountId != drive.accountId) {
        throw const DriveTransferException(DriveTransferIssue.invalidSource);
      }
      final api = apiFor(drive);
      final media = _mediaApis.putIfAbsent(
          drive.accountId,
          () => _createMediaApi(
              authorizationFor(drive.serverClientId), drive.accountId));
      final engine = DriveTransferEngine(
          journal: journal,
          storage: _storage,
          revalidate: (artifact, cancellation) => DriveDownloadBoundary(
                  config: config,
                  artifact: artifact,
                  catalogue: catalogue,
                  api: api)
              .revalidate(cancellation: cancellation),
          openMedia: (artifact, offset, cancellation) =>
              media.open(artifact, offset: offset, cancelToken: cancellation));
      // No await separates this last gate from registration. A disconnect can
      // neither overlook this operation nor let a pending old-lane load start.
      _requireConnectedLane();
      final operation = engine.start(transferId, onCheckpoint: onCheckpoint);
      _transfers[transferId] = operation;
      void settled() {
        if (identical(_transfers[transferId], operation)) {
          _transfers.remove(transferId);
          _transferResults.remove(transferId);
        }
      }

      // Observe errors immediately, even when a caller waits on result later.
      // The original result retains its outcome; this future is the drain join.
      _transferResults[transferId] = operation.result.then<void>(
          (_) => settled(),
          onError: (Object _, StackTrace __) => settled());
      return operation;
    } finally {
      _startingTransfers.remove(transferId);
    }
  }

  DriveAuthorization authorizationFor(String serverClientId) {
    _requireConnectedLane();
    if (serverClientId.trim().isEmpty) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    if (_clientId != null && _clientId != serverClientId) {
      // GoogleSignIn is a native singleton. Do not create competing authorization
      // lanes with different OAuth projects; changing the project needs relaunch.
      throw const DriveCatalogueException('oauthClientChangedRestartRequired');
    }
    _clientId = serverClientId;
    return _authorization ??= _createAuthorization(serverClientId);
  }

  DriveApi apiFor(DriveSourceConfig config) {
    if (!config.isConfigured) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    final authorization = authorizationFor(config.serverClientId);
    return _apis.putIfAbsent(
        config.accountId, () => _createApi(authorization, config.accountId));
  }

  Future<void> refreshSource(Source source, {CancelToken? cancelToken}) {
    if (source.type != SourceType.drive || source.drive == null) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    return refreshConfig(
        ProviderConfig(
            type: ProviderType.drive,
            priority: source.priority,
            sourceId: source.id,
            drive: source.drive),
        cancelToken: cancelToken);
  }

  Future<void> refreshConfig(ProviderConfig config,
      {CancelToken? cancelToken}) async {
    _requireConnectedLane();
    final drive = config.drive;
    if (drive == null ||
        !drive.isConfigured ||
        config.sourceId?.isNotEmpty != true) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    final scope = DriveCatalogue.scopeKey(
        config.sourceId!, drive.accountId, drive.rootFolderId);
    final existing = _refreshes[scope];
    if (existing != null) {
      await existing;
      return;
    }
    final cancellation = cancelToken ?? CancelToken();
    final operation = catalogue.refresh(
        sourceId: config.sourceId!,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId,
        api: apiFor(drive),
        cancelToken: cancellation);
    _refreshes[scope] = operation;
    _refreshCancellation[scope] = cancellation;
    try {
      await operation;
    } finally {
      if (identical(_refreshes[scope], operation)) {
        _refreshes.remove(scope);
        _refreshCancellation.remove(scope);
      }
    }
  }

  void _requireConnectedLane() {
    if (_disconnecting) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.cancelled);
    }
  }

  /// The native account session is app-wide, so disconnect drains every source's
  /// owned refresh and transfer. Settings, catalogue, stage bytes and installed
  /// manifests are retained. Transport teardown follows actual resource drain.
  Future<void> disconnect({bool revoke = false}) async {
    _requireConnectedLane();
    _disconnecting = true;
    _laneGeneration++;
    try {
      for (final cancellation in _refreshCancellation.values) {
        cancellation.cancel();
      }
      final plans = _bundlePlans.values.toList();
      final headers = _metadataHeaders.values.toList();
      final archives = _metadataArchives.values.toList();
      final reviews = _recoveryReviews.values.toList();
      for (final cancellation in _recoveryReviews.keys.toList()) {
        cancellation.cancel();
      }
      for (final cancellation in _metadataHeaders.keys.toList()) {
        cancellation.cancel();
      }
      for (final cancellation in _metadataArchives.keys.toList()) {
        cancellation.cancel();
      }
      for (final cancellation in _bundlePlans.keys.toList()) {
        cancellation.cancel();
      }
      final transfers = _transferResults.values.toList();
      for (final transfer in _transfers.values.toList()) {
        transfer.pause();
      }
      // signOut invalidates outstanding grants synchronously. Attach all error
      // handlers immediately and await actual native/refresh completion, not a timer.
      await Future.wait<void>([
        if (_authorization != null) _authorization!.signOut(revoke: revoke),
        for (final refresh in _refreshes.values.toList())
          refresh.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        ...transfers,
        for (final plan in plans)
          plan.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        for (final header in headers)
          header.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        for (final archive in archives)
          archive.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        for (final review in reviews)
          review.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ]);
    } finally {
      for (final api in _apis.values) {
        api.close();
      }
      _apis.clear();
      for (final media in _mediaApis.values) {
        media.close();
      }
      _mediaApis.clear();
      _disconnecting = false;
    }
  }

  Future<List<DriveFile>> folders(Source source) async {
    final drive = source.drive;
    if (drive == null || !drive.isConfigured) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    final generation = await catalogue.activeGeneration(
        sourceId: source.id,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId);
    if (generation == null) {
      throw const DriveCatalogueException('refreshRequired');
    }
    final result = <DriveFile>[
      await catalogue.requireFolder(
          sourceId: source.id,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId,
          folderId: drive.rootFolderId,
          generation: generation)
    ];
    var offset = 0;
    while (true) {
      final page = await catalogue.entries(
          sourceId: source.id,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId,
          folderId: drive.rootFolderId,
          generation: generation,
          limit: 500,
          offset: offset);
      result.addAll(page.where((e) => e.file.isFolder).map((e) => e.file));
      if (page.length < 500) break;
      offset += page.length;
    }
    return result;
  }

  /// Source-level exclusion report from the published snapshot only. Unsupported
  /// records stay inspectable without traversing shortcuts or exporting documents.
  Future<Map<String, int>> unsupportedCounts(Source source) async {
    final drive = source.drive;
    if (drive == null || !drive.isConfigured) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    final generation = await catalogue.activeGeneration(
        sourceId: source.id,
        accountId: drive.accountId,
        rootFolderId: drive.rootFolderId);
    if (generation == null) {
      throw const DriveCatalogueException('refreshRequired');
    }
    final counts = <String, int>{};
    var offset = 0;
    while (true) {
      final page = await catalogue.entries(
          sourceId: source.id,
          accountId: drive.accountId,
          rootFolderId: drive.rootFolderId,
          folderId: drive.rootFolderId,
          generation: generation,
          limit: 500,
          offset: offset);
      for (final entry in page) {
        final reason = entry.file.unsupportedReason;
        if (reason != null) {
          counts.update(reason, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      if (page.length < 500) break;
      offset += page.length;
    }
    return Map.unmodifiable(counts);
  }
}
