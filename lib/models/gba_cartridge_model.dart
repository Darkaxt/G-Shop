import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../services/socket_media_import.dart';
import '../utils/game_metadata.dart';
import 'library_identity.dart';
import 'socket_media_model.dart';

/// The standard-shape hollow cartridge is a private import, never a Socket
/// resource replacement. The board is illustrative, not per-game electronics.
class GbaCartridgeModel {
  static String? styleFor(String filename, Iterable<String> tags) {
    final normalized = EditionIdentity.normalizeContentTags(tags);
    if (normalized.length != 1 || !normalized.contains('official')) return null;
    final title = GameMetadata.cleanTitle(filename.split(RegExp(r'[/\\]')).last)
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll(RegExp('[^a-z0-9]'), '');
    // Exact commercial titles only. Never strip a hack's suffix or borrow its
    // base-game identity. Nonstandard moulds remain on their existing path.
    if ({
      'boktaithesunisinyourhand',
      'boktai2solarboydjango',
      'shinbokuranotaiyougyakushuunosabata',
      'wariowaretwisted',
      'mawarumadeinwario',
      'yoshitopsyturvy',
      'yoshisuniversalgravitation',
      'drilldozer',
      'screwbreaker'
    }.contains(title)) return null;
    const colors = {
      'pokemonrubyversion': 'red',
      'pokemonruby': 'red',
      'pokemonsapphireversion': 'blue',
      'pokemonsapphire': 'blue',
      'pokemonemeraldversion': 'green',
      'pokemonemerald': 'green',
      'pokemonfireredversion': 'cloudy-red',
      'pokemonfirered': 'cloudy-red',
      'pokemonleafgreenversion': 'cloudy-green',
      'pokemonleafgreen': 'cloudy-green',
    };
    return colors[title] ?? 'gray';
  }

  static Future<SocketMediaModel?> load(String style,
      {Directory? modelsDirectory}) async {
    if (!{'gray', 'red', 'blue', 'green', 'cloudy-red', 'cloudy-green'}
        .contains(style)) {
      throw const FormatException('Invalid GBA cartridge style');
    }
    if (modelsDirectory == null && !Platform.isAndroid) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final directory = Directory('${root.path}/cartridges/gba');
    final manifest = File('${directory.path}/model.json');
    if (!await manifest.exists()) return null;
    final file = File('${directory.path}/model.mesh');
    if (await manifest.length() > 1024 * 1024 ||
        await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('Cartridge import exceeds size');
    }
    final data =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    if (data['system'] != 'gba' || data['motionKind'] != 'drop') {
      throw const FormatException('Invalid cartridge system');
    }
    final bounds = data['bounds'];
    if (bounds is! List ||
        bounds.length != 3 ||
        bounds.any((v) => v is! num || !v.isFinite || v <= 0) ||
        data['sourceWidth'] is! num ||
        (data['sourceWidth'] as num) <= 0 ||
        !(data['sourceWidth'] as num).isFinite ||
        data['labelAspect'] is! num ||
        !(data['labelAspect'] as num).isFinite ||
        (data['labelAspect'] as num) <= 0) {
      throw const FormatException('Invalid cartridge dimensions');
    }
    final bytes = ByteData.sublistView(await file.readAsBytes());
    // Verify the untouched conversion before applying selected material values.
    SocketMediaModel.privateCartridge(data, bytes);
    final profiles = data['profiles'] as Map;
    final profile = profiles[style] as Map;
    final color = (profile['color'] as List).cast<num>();
    if (color.length != 4 ||
        color.any((v) => !v.isFinite || v < 0 || v > 1) ||
        color[3] != 1) {
      throw const FormatException('Invalid cartridge color');
    }
    for (final key in [
      'roughness',
      'metallic',
      'transmission',
      'ior',
      'thickness'
    ]) {
      final value = profile[key];
      if (value is! num ||
          !value.isFinite ||
          value < (key == 'ior' ? 1 : 0) ||
          value > (key == 'ior' ? 3 : 1)) {
        throw const FormatException('Invalid cartridge optical material');
      }
    }
    final receipts = (data['textureFiles'] as Map).cast<String, String>();
    if (receipts.isEmpty || receipts.length > 32) {
      throw const FormatException('Invalid cartridge textures');
    }
    for (final entry in receipts.entries) {
      SocketMediaDirectoryBundle.checkName(entry.key);
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value)) {
        throw const FormatException('Invalid cartridge texture checksum');
      }
    }
    for (final surface in data['surfaces'] as List) {
      final material = surface['material'] as Map;
      for (final name in (material['textures'] as Map).values) {
        if (!receipts.containsKey(name))
          throw const FormatException('Texture without receipt');
      }
      if (surface['shellMaterial'] == true) {
        material['color'] = color;
        final optical = Map<String, dynamic>.from(profile)..remove('color');
        optical['sourceTransmission'] = optical['transmission'];
        // The owner's source is almost optical glass. Retail dyed cartridge
        // plastic is translucent: retain a solid diffuse housing and its own
        // colour, with a weaker view of the separately textured green PCB.
        optical['transmission'] = (optical['transmission'] as num) == 0
            ? 0.0
            : style.startsWith('cloudy-')
                ? .24
                : .42;
        optical['roughness'] = (optical['roughness'] as num).clamp(.32, 1.0);
        (material['sourceProperties'] as Map).addAll(optical);
      }
    }
    data['name'] = 'gba-hollow-pcb-$style';
    data['cartridgeStyle'] = style;
    return SocketMediaModel.privateCartridge(data, bytes,
        textureBundle: _CartridgeTextures(directory, receipts));
  }
}

class _CartridgeTextures extends SocketMediaDirectoryBundle {
  final Map<String, String> receipts;
  _CartridgeTextures(super.directory, this.receipts);
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith(SocketMediaModel.assetRoot))
      throw const FormatException('Invalid texture namespace');
    final name = key.substring(SocketMediaModel.assetRoot.length);
    SocketMediaDirectoryBundle.checkName(name);
    if (!receipts.containsKey(name) ||
        await File('${directory.path}/$name').length() > 20 * 1024 * 1024) {
      throw const FormatException('Invalid cartridge texture file');
    }
    final data = await super.load(key);
    if (sha256
            .convert(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))
            .toString() !=
        receipts[name]) {
      throw const FormatException('Cartridge texture checksum mismatch');
    }
    return data;
  }
}
