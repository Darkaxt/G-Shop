import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../services/socket_media_import.dart';
import 'socket_media_model.dart';

/// Independent local imports, never replacing the cartridge resource bundle.
class ConsoleModel {
  final String systemId;
  final Directory directory;
  final String generation;
  ConsoleModel._(this.systemId, this.directory, this.generation);

  static Future<ConsoleModel?> find(String systemId,
      {Directory? modelsDirectory}) async {
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(systemId)) {
      throw const FormatException('Invalid console model system');
    }
    if (modelsDirectory == null && !Platform.isAndroid) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final dir = Directory('${root.path}/consoles/$systemId');
    final manifest = File('${dir.path}/model.json');
    if (!await manifest.exists()) return null;
    if (await manifest.length() > 1024 * 1024) {
      throw const FormatException('Console manifest exceeds import size');
    }
    return ConsoleModel._(
        systemId, dir, sha256.convert(await manifest.readAsBytes()).toString());
  }

  Future<SocketMediaModel> load() async {
    final manifest = await File('${directory.path}/model.json').readAsBytes();
    if (manifest.length > 1024 * 1024 ||
        sha256.convert(manifest).toString() != generation) {
      throw const FormatException('Console import changed during selection');
    }
    final data = jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
    if (data['system'] != systemId ||
        data['motionKind'] != 'hardware' ||
        data['sourceWidth'] is! num ||
        !(data['sourceWidth'] as num).isFinite ||
        (data['sourceWidth'] as num) <= 0 ||
        data['bounds'] is! List ||
        (data['bounds'] as List).length != 3 ||
        (data['bounds'] as List)
            .any((v) => v is! num || !v.isFinite || v <= 0)) {
      throw const FormatException(
          'Invalid console model dimensions or identity');
    }
    final receipts = (data['textureFiles'] as Map).cast<String, String>();
    if (receipts.isEmpty || receipts.length > 64) {
      throw const FormatException('Invalid console texture inventory');
    }
    for (final entry in receipts.entries) {
      SocketMediaDirectoryBundle.checkName(entry.key);
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value)) {
        throw const FormatException('Invalid console texture checksum');
      }
    }
    for (final surface in data['surfaces'] as List) {
      for (final name in (surface['material']['textures'] as Map).values) {
        if (!receipts.containsKey(name)) {
          throw const FormatException('Console texture lacks a checksum');
        }
      }
    }
    final file = File('${directory.path}/model.mesh');
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('Console mesh exceeds import size');
    }
    return SocketMediaModel.privateHardware(
        data, ByteData.sublistView(await file.readAsBytes()),
        textureBundle: _ConsoleTextures(directory, receipts));
  }
}

class _ConsoleTextures extends SocketMediaDirectoryBundle {
  final Map<String, String> receipts;
  _ConsoleTextures(super.directory, this.receipts);
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith(SocketMediaModel.assetRoot)) {
      throw const FormatException('Invalid console texture namespace');
    }
    final name = key.substring(SocketMediaModel.assetRoot.length);
    SocketMediaDirectoryBundle.checkName(name);
    if (!receipts.containsKey(name) ||
        await File('${directory.path}/$name').length() > 20 * 1024 * 1024) {
      throw const FormatException('Invalid console texture file');
    }
    final bytes = await super.load(key);
    if (sha256
            .convert(bytes.buffer
                .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))
            .toString() !=
        receipts[name]) {
      throw const FormatException('Console texture checksum mismatch');
    }
    return bytes;
  }
}
