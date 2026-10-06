import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/core/input/app_intents.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';
import 'package:retro_eshop/services/drive/drive_media.dart';
import 'package:retro_eshop/features/game_detail/widgets/drive_recovery_review_dialog.dart';

class _Runtime extends DriveRuntime {
  final result = Completer<DriveLocalCloudObservation>();
  CancelToken? cancellation;
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

void main() {
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
    await tester.pumpWidget(MaterialApp(
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
    expect(find.byType(DriveRecoveryReviewDialog), findsOneWidget);
    runtime.result.completeError(
        const DriveTransferException(DriveTransferIssue.cancelled));
    await tester.pumpAndSettle();
    expect(find.byType(DriveRecoveryReviewDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
