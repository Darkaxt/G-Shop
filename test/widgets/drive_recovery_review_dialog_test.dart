import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:g_shop/core/input/app_intents.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/transfer_record.dart';
import 'package:g_shop/services/drive/drive_runtime.dart';
import 'package:g_shop/services/drive/drive_media.dart';
import 'package:g_shop/services/library_query.dart';
import 'package:g_shop/providers/rom_status_providers.dart';
import 'package:g_shop/features/game_detail/widgets/drive_recovery_review_dialog.dart';

class _Runtime extends DriveRuntime {
  final result = Completer<DriveLocalCloudObservation>();
  final adoption = Completer<InstalledArtifact>();
  CancelToken? adoptionCancellation;
  CancelToken? cancellation;
  DriveLocalCloudObservation? saved;
  int savedReads = 0;
  @override
  Future<InstalledArtifact> adoptLocalCloudBytes(
      {required ProviderConfig config,
      required RemoteArtifact artifact,
      required String destinationRoot,
      required String relativePath,
      required Set<String> supportedExtensions,
      required CancelToken cancellation}) {
    adoptionCancellation = cancellation;
    return adoption.future;
  }

  @override
  Future<DriveLocalCloudObservation?> savedLocalCloudObservation({
    required RemoteArtifact artifact,
    required String destinationRoot,
    required String relativePath,
  }) async {
    savedReads++;
    return saved;
  }

  @override
  Future<DriveLocalCloudObservation> verifyLocalCloudBytes(
      {required ProviderConfig config,
      required RemoteArtifact artifact,
      required String destinationRoot,
      required String relativePath,
      required CancelToken cancellation}) {
    this.cancellation = cancellation;
    return result.future;
  }
}

class _RetentionQuery extends LibraryQuery {
  final LibraryRetentionPage result;
  RemoteArtifact? requestedArtifact;
  String? requestedPlatform;
  _RetentionQuery(this.result) : super(Completer<Database>().future);
  @override
  Future<LibraryRetentionPage> retentionForArtifact(
      {required String platformId,
      required RemoteArtifact artifact,
      assessedBases}) async {
    requestedArtifact = artifact;
    requestedPlatform = platformId;
    return result;
  }
}

Widget _testApp({required Widget home}) =>
    ProviderScope(child: MaterialApp(home: home));

void main() {
  for (final issue in [
    DriveTransferIssue.checksumMismatch,
    DriveTransferIssue.unavailable,
    DriveTransferIssue.cancelled
  ]) {
    testWidgets(
        'comparison explains $issue without exposing a raw error as the message',
        (tester) async {
      final runtime = _Runtime();
      final artifact = RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: 'source',
              accountId: 'account',
              providerFileId: 'file'),
          displayName: 'fixture.chd',
          displayPath: 'fixture.chd',
          sizeBytes: 5);
      await tester.pumpWidget(_testApp(
          home: DriveRecoveryReviewDialog(
              config:
                  const ProviderConfig(type: ProviderType.drive, priority: 1),
              artifact: artifact,
              destinationRoot: '/roms',
              runtime: runtime)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compare files'));
      await tester.pump();
      runtime.result.completeError(DriveTransferException(issue));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your files have not been changed'),
          findsOneWidget);
      expect(find.textContaining('Error code:'), findsNothing);
      expect(find.text('Add to G-Shop'), findsNothing);
      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();
      expect(find.text('Error code: ${issue.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final rank in <int?>[25, 26, null]) {
    testWidgets('complete retention review reports rank $rank without deletion',
        (tester) async {
      final runtime = _Runtime();
      final artifact = RemoteArtifact(
          id: RemoteArtifactId(
              providerId: 'drive',
              sourceId: 'source',
              accountId: 'account',
              providerFileId: 'file'),
          displayName: 'fixture.chd',
          displayPath: 'fixture.chd',
          version: '1');
      final query = _RetentionQuery(LibraryRetentionPage(
          platformId: 'psx',
          members: [
            LibraryRetentionMember(
                editionId: 'edition',
                gameId: 'game',
                groupKey: 'group',
                cacheRowId: 1,
                canonicalRank: rank)
          ],
          collectionGames: 26,
          rankedGames: rank == null ? 25 : 26,
          totalMembers: 26,
          unboundArtifacts: 0));
      await tester.pumpWidget(_testApp(
          home: DriveRecoveryReviewDialog(
              config:
                  const ProviderConfig(type: ProviderType.drive, priority: 1),
              artifact: artifact,
              destinationRoot: '/roms',
              platformId: 'psx',
              libraryQuery: query,
              runtime: runtime)));
      await tester.pumpAndSettle();
      expect(
          find.text(rank == 25
              ? 'Keep offline · #25 in this console’s Top 25'
              : rank == null
                  ? 'Not in the offline sample · no reliable rating yet'
                  : 'Not in the offline sample · ranked #26'),
          findsOneWidget);
      expect(find.textContaining('Results may change'),
          rank == null ? findsOneWidget : findsNothing);
      expect(find.textContaining('does not delete files'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(runtime.cancellation, isNull);
      expect(runtime.adoptionCancellation, isNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'recovery review shows exact provisional retention without network work',
      (tester) async {
    final runtime = _Runtime();
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'file'),
        displayName: 'fixture.chd',
        displayPath: 'fixture.chd',
        version: '1');
    final query = _RetentionQuery(LibraryRetentionPage(
        platformId: 'psx',
        members: [
          const LibraryRetentionMember(
              editionId: 'edition',
              gameId: 'game',
              groupKey: 'group',
              cacheRowId: 1,
              canonicalRank: 26)
        ],
        collectionGames: 27,
        rankedGames: 26,
        totalMembers: 27,
        unboundArtifacts: 0));
    await tester.pumpWidget(_testApp(
        home: DriveRecoveryReviewDialog(
            config: const ProviderConfig(type: ProviderType.drive, priority: 1),
            artifact: artifact,
            destinationRoot: '/roms',
            platformId: 'psx',
            libraryQuery: query,
            runtime: runtime)));
    await tester.pumpAndSettle();
    expect(query.requestedArtifact, same(artifact));
    expect(query.requestedPlatform, 'psx');
    expect(find.text('Not in the offline sample · ranked #26'), findsOneWidget);
    expect(find.textContaining('26 of 27 games have ranking scores'),
        findsOneWidget);
    expect(find.textContaining('Results may change'), findsOneWidget);
    expect(find.textContaining('does not delete files'), findsOneWidget);
    expect(runtime.cancellation, isNull);
    expect(runtime.adoptionCancellation, isNull);
    expect(find.text('Remove'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'adoption is a distinct explicit action with no automatic removal',
      (tester) async {
    final runtime = _Runtime();
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'file'),
        displayName: 'fixture.rvz',
        displayPath: 'fixture.rvz',
        version: '1',
        sizeBytes: 5,
        canDownload: true,
        providerChecksums: const {'md5': '7cfdd07889b3295d6a550914ab35e068'});
    await tester.pumpWidget(_testApp(
        home: DriveRecoveryReviewDialog(
            config: const ProviderConfig(type: ProviderType.drive, priority: 1),
            artifact: artifact,
            destinationRoot: '/roms',
            supportedExtensions: {'.rvz'},
            runtime: runtime)));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DriveRecoveryReviewDialog)));
    expect(runtime.adoptionCancellation, isNull);
    expect(runtime.cancellation, isNull);
    expect(find.textContaining('Nothing is deleted'), findsOneWidget);
    await tester.tap(find.text('Add to G-Shop'));
    await tester.pump();
    expect(runtime.adoptionCancellation, isNotNull);
    expect(runtime.cancellation, isNull);
    expect(
        find.text('Your existing download was added to G-Shop.'), findsNothing);
    final identity = NativeFileIdentity(
        volumeId: 'volume',
        fileId: 'inode',
        sizeBytes: 5,
        modifiedAt: DateTime.utc(2026, 10, 6));
    runtime.adoption.complete(InstalledArtifact(
        id: 'installation-one',
        transferId: 'adoption-one',
        artifact: artifact,
        destinationRoot: '/roms',
        relativePath: 'fixture.rvz',
        sizeBytes: 5,
        verifiedChecksums: {
          'md5': '7cfdd07889b3295d6a550914ab35e068',
          'sha256': 'a' * 64
        },
        fileIdentity: identity));
    await tester.pumpAndSettle();
    expect(find.text('Your existing download was added to G-Shop.'),
        findsOneWidget);
    expect(find.text('Add to G-Shop'), findsNothing);
    expect(find.textContaining('Nothing was deleted'), findsOneWidget);
    expect(container.read(romChangeSignalProvider), 1,
        reason:
            'An ownership commit must refresh the shared installation index');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'historical review stays read-only and new verification refreshes availability',
      (tester) async {
    final runtime = _Runtime();
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'file'),
        displayName: 'fixture.chd',
        displayPath: 'fixture.chd',
        sizeBytes: 5,
        version: '1',
        canDownload: true,
        providerChecksums: const {'md5': '7cfdd07889b3295d6a550914ab35e068'});
    runtime.saved = DriveLocalCloudObservation(
        artifact: artifact,
        destinationRoot: '/roms',
        relativePath: 'fixture.chd',
        sizeBytes: 5,
        localIdentity: NativeFileIdentity(
            volumeId: 'volume',
            fileId: 'file',
            sizeBytes: 5,
            modifiedAt: DateTime.utc(2026, 10, 6)),
        checksums: {
          'md5': '7cfdd07889b3295d6a550914ab35e068',
          'sha256': 'a' * 64
        },
        observedAt: DateTime.utc(2026, 10, 6));
    await tester.pumpWidget(_testApp(
        home: DriveRecoveryReviewDialog(
            config: const ProviderConfig(type: ProviderType.drive, priority: 1),
            artifact: artifact,
            destinationRoot: '/roms',
            runtime: runtime)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Last successful comparison'), findsOneWidget);
    expect(find.textContaining('not been checked again'), findsOneWidget);
    expect(find.text('Your local copy matches Google Drive.'), findsNothing);
    expect(runtime.savedReads, 1);
    expect(runtime.cancellation, isNull);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DriveRecoveryReviewDialog)));
    expect(container.read(romChangeSignalProvider), 0,
        reason:
            'Reading a historical observation does not change availability');
    await tester.tap(find.text('Compare files'));
    await tester.pump();
    expect(container.read(romChangeSignalProvider), 0,
        reason: 'Do not refresh before the actual verification has drained');
    runtime.result.complete(runtime.saved!);
    await tester.pumpAndSettle();
    expect(find.text('Your local copy matches Google Drive.'), findsOneWidget);
    expect(find.textContaining('SHA-256:'), findsNothing,
        reason:
            'Hashes belong in collapsed technical details, not the main result');
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SHA-256:'), findsOneWidget);
    expect(container.read(romChangeSignalProvider), 1,
        reason: 'A byte-only journal update has no filesystem event; '
            'it must invalidate the shared installation projection explicitly');
    expect(runtime.adoptionCancellation, isNull);
  });
  testWidgets('review is explicit and cancel waits for actual operation drain',
      (tester) async {
    final runtime = _Runtime();
    final artifact = RemoteArtifact(
        id: RemoteArtifactId(
            providerId: 'drive',
            sourceId: 'source',
            accountId: 'account',
            providerFileId: 'file'),
        displayName: 'fixture.chd',
        displayPath: 'fixture.chd',
        sizeBytes: 5);
    await tester.pumpWidget(_testApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => DriveRecoveryReviewDialog(
                        config: const ProviderConfig(
                            type: ProviderType.drive, priority: 1),
                        artifact: artifact,
                        destinationRoot: '/roms',
                        runtime: runtime)),
                child: const Text('Review')))));
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DriveRecoveryReviewDialog)));
    expect(runtime.cancellation, isNull);
    expect(find.textContaining('does not save another copy'), findsOneWidget);
    // The dialog, not the underlying details route, owns controller intents.
    Actions.invoke(
        tester.element(find.text('Compare files')), const ConfirmIntent());
    await tester.pump();
    expect(runtime.cancellation, isNotNull);
    Actions.invoke(tester.element(find.text('Cancel')), const BackIntent());
    await tester.pump();
    expect(runtime.cancellation!.isCancelled, isTrue);
    expect(container.read(romChangeSignalProvider), 0);
    expect(find.byType(DriveRecoveryReviewDialog), findsOneWidget);
    runtime.result.completeError(
        const DriveTransferException(DriveTransferIssue.cancelled));
    await tester.pumpAndSettle();
    expect(find.byType(DriveRecoveryReviewDialog), findsNothing);
    expect(container.read(romChangeSignalProvider), 1,
        reason:
            'A cancelled operation must drain before refreshing journal truth');
    expect(tester.takeException(), isNull);
  });
}
