import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:retro_eshop/core/input/app_intents.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/services/library_query.dart';
import 'package:retro_eshop/providers/rom_status_providers.dart';
import 'package:retro_eshop/features/game_detail/widgets/drive_recovery_review_dialog.dart';

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
  for (final rank in [25, 26]) {
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
          rankedGames: 26,
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
              ? 'Keep · canonical rank 25 (Top 25)'
              : 'Outside sample · canonical rank 26'),
          findsOneWidget);
      expect(find.textContaining('Provisional'), findsNothing);
      expect(find.textContaining('Planning only'), findsOneWidget);
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
    expect(
        find.textContaining('Preserve · ranking incomplete'), findsOneWidget);
    expect(find.textContaining('26/27 ranked · Provisional'), findsOneWidget);
    expect(find.textContaining('Planning only'), findsOneWidget);
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
    expect(find.textContaining('No file is deleted'), findsOneWidget);
    await tester.tap(find.text('Verify and adopt'));
    await tester.pump();
    expect(runtime.adoptionCancellation, isNotNull);
    expect(runtime.cancellation, isNull);
    expect(find.text('Existing file adopted.'), findsNothing);
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
    expect(find.text('Existing file adopted.'), findsOneWidget);
    expect(find.text('Verify and adopt'), findsNothing);
    expect(find.textContaining('No file was deleted'), findsOneWidget);
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
    expect(find.textContaining('Past byte match'), findsOneWidget);
    expect(find.textContaining('not rechecked now'), findsOneWidget);
    expect(find.text('Current byte match verified.'), findsNothing);
    expect(runtime.savedReads, 1);
    expect(runtime.cancellation, isNull);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DriveRecoveryReviewDialog)));
    expect(container.read(romChangeSignalProvider), 0,
        reason:
            'Reading a historical observation does not change availability');
    await tester.tap(find.text('Verify bytes'));
    await tester.pump();
    expect(container.read(romChangeSignalProvider), 0,
        reason: 'Do not refresh before the actual verification has drained');
    runtime.result.complete(runtime.saved!);
    await tester.pumpAndSettle();
    expect(find.text('Current byte match verified.'), findsOneWidget);
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
    expect(find.textContaining('Does not adopt'), findsOneWidget);
    // The dialog, not the underlying details route, owns controller intents.
    Actions.invoke(
        tester.element(find.text('Verify bytes')), const ConfirmIntent());
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
