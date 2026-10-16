import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/game_item.dart';
import '../../models/system_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/game_providers.dart';
import '../../providers/save_backup_providers.dart';
import '../../services/owned_emulator_launcher.dart';
import '../settings/save_backup_settings_screen.dart';

/// Both detail surfaces use the same save/conflict/companion handoff path.
Future<void> openManagedGame(
    WidgetRef ref,
    BuildContext context,
    OwnedEmulatorLauncher launcher,
    GameItem game,
    SystemModel system,
    String target,
    {bool withoutCompanion = false,
    Future<void> Function()? beforeHandoff}) async {
  final metadata = await ref.read(
      gameMetadataProvider((filename: game.selectionKey, systemSlug: system.id))
          .future);
  if (!context.mounted) throw PlatformException(code: 'cancelled');
  final editionId = metadata?.editionId;
  final companion = withoutCompanion || editionId == null
      ? null
      : ref.read(storageServiceProvider).getCompanion(editionId);
  await launcher.open(game, system, target, companionComponent: companion,
      prepareSave: () async {
    final artifact = game.remoteArtifact?.id;
    if (artifact != null) {
      final saves = await ref.read(automaticSaveBackupsProvider.future);
      await saves.prepareLaunch(
          artifactId: artifact,
          editionId: editionId,
          reviewDeviceBackups: (job) async {
            if (!context.mounted) throw PlatformException(code: 'cancelled');
            await SaveBackupGamePanel.reviewOtherDevices(context, job);
          },
          reviewPcsxSaves: () =>
              launcher.reviewRetroArchPcsxSaves(game, system, target),
          reviewRetroArchSave: (route) =>
              launcher.reviewRetroArchBatterySave(game, system, target, route));
    }
    if (!context.mounted) throw PlatformException(code: 'cancelled');
    await beforeHandoff?.call();
  });
}
