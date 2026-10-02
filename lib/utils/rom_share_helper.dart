import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../models/game_item.dart';
import '../models/system_model.dart';
import '../services/rom_manager.dart';
import '../services/installation_index.dart';
import '../models/transfer_record.dart';

/// Prefix for temporary ZIP files created for sharing.
const _sharePrefix = 'rshop_share_';

class RomShareHelper {
  /// Prepares ROM files for sharing via the system share sheet.
  ///
  /// For single-file ROMs, returns the file directly.
  /// For multi-file ROMs in subfolders, creates a ZIP and returns that.
  static Future<List<XFile>> prepareShareFiles({
    required GameItem game,
    required SystemModel system,
    required String targetFolder,
    InstallationIndex? installations,
  }) async {
    if (game.remoteArtifact != null) {
      final installed = await RomManager(installations: installations)
          .requireInstalledArtifact(game, targetFolder);
      if (installed.dependencies.isNotEmpty) {
        return _prepareOwnedBundle(
            installed, installations ?? InstallationIndex.application());
      }
    }
    final result = await RomManager.resolveSharePath(game, system, targetFolder,
        installations: installations);
    if (result == null) {
      throw StateError('Game is not installed');
    }

    if (!result.isDirectory) {
      return [XFile(result.path, mimeType: 'application/octet-stream')];
    }

    // Multi-file ROM: zip the subfolder
    final tempDir = await getTemporaryDirectory();
    final gameName = p.basename(result.path);
    final zipName = '$_sharePrefix$gameName.zip';
    final zipPath = '${tempDir.path}/$zipName';

    // Clean previous share ZIP for the same game
    final existing = File(zipPath);
    if (await existing.exists()) {
      await existing.delete();
    }

    await compute(_createZip, _ZipParams(result.path, zipPath));

    return [XFile(zipPath, mimeType: 'application/zip')];
  }

  /// ZIP only exact manifest members copied from pinned descriptors. Never zip
  /// the public bundle folder: it may contain saves or unrelated user files.
  static Future<List<XFile>> _prepareOwnedBundle(
      InstalledArtifact installed, InstallationIndex index) async {
    final temp = await getTemporaryDirectory();
    final copies = await Directory(temp.path).createTemp('rshop_bundle_');
    final zipPath = '${temp.path}/$_sharePrefix${p.basename(copies.path)}.zip';
    var success = false;
    try {
      final namespace = installed.relativePath.split('/').first;
      for (final member in [installed, ...installed.dependencies]) {
        final record = (await index.journal.transfer(member.transferId))!;
        final relative = member.relativePath.substring(namespace.length + 1);
        final output = File(p.join(copies.path, relative));
        await output.parent.create(recursive: true);
        final session = await index.storage.open(
            destinationRoot: member.destinationRoot,
            relativePath: member.relativePath,
            stagePath: record.stagePath,
            expectedIdentity: member.fileIdentity,
            durableOffset: member.sizeBytes,
            published: true);
        RandomAccessFile? sink;
        try {
          final openedSink = await output.open(mode: FileMode.write);
          sink = openedSink;
          final digest = await sha256
              .bind(session.bytes(member.sizeBytes).asyncMap((chunk) async {
                await openedSink.writeFrom(chunk);
                return chunk;
              }))
              .single;
          await openedSink.flush();
          if (digest.toString() != member.verifiedChecksums['sha256'] ||
              !(await session.checkpoint()).matches(member.fileIdentity)) {
            throw StateError('Bundle member changed during sharing');
          }
        } finally {
          try {
            await sink?.close();
          } finally {
            await session.close();
          }
        }
      }
      final rootRecord = (await index.journal.transfer(installed.transferId))!;
      await index.requireInstallation(rootRecord, installed);
      await compute(_createZip, _ZipParams(copies.path, zipPath));
      success = true;
      return [XFile(zipPath, mimeType: 'application/zip')];
    } finally {
      await copies.delete(recursive: true);
      if (!success && await File(zipPath).exists()) {
        await File(zipPath).delete();
      }
    }
  }

  /// Deletes leftover share ZIP files from the temp directory.
  static Future<void> cleanShareTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      await for (final entity in dir.list()) {
        if (entity is File &&
            p.basename(entity.path).startsWith(_sharePrefix)) {
          await entity.delete();
        }
      }
    } catch (e) {
      debugPrint('RomShareHelper: cleanup failed: $e');
    }
  }
}

class _ZipParams {
  final String directoryPath;
  final String outputPath;
  const _ZipParams(this.directoryPath, this.outputPath);
}

/// Runs in an isolate to avoid blocking the UI.
void _createZip(_ZipParams params) {
  final encoder = ZipFileEncoder();
  encoder.zipDirectory(
    Directory(params.directoryPath),
    filename: params.outputPath,
    level: ZipFileEncoder.STORE,
  );
}
