import 'dart:convert';

import 'patch_catalogue.dart';

/// Public patch instructions and a historical verified result, never a device's
/// installation receipt. Paths are published collection-relative references.
class PortablePatchRecipe {
  static const maxBytes = 256 * 1024;
  final PatchRecipe recipe;
  final String sourceGameId, gameTitle, title;
  final PatchRelativePath gameIndexPath;
  final int? outputSize;
  final String? outputSha256;

  PortablePatchRecipe({
    required this.recipe,
    required this.sourceGameId,
    required this.gameTitle,
    required this.gameIndexPath,
    required this.title,
    this.outputSize,
    this.outputSha256,
  }) {
    for (final value in [sourceGameId, gameTitle, title]) {
      if (value.isEmpty ||
          value.length > 512 ||
          RegExp(r'[\x00-\x1f]').hasMatch(value)) {
        throw const FormatException('invalid_portable_patch_text');
      }
    }
    if ((outputSize == null) != (outputSha256 == null) ||
        (outputSize != null && outputSize! <= 0) ||
        (outputSha256 != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(outputSha256!))) {
      throw const FormatException('invalid_portable_patch_output');
    }
    _checkRecipe(recipe.toJson());
  }

  factory PortablePatchRecipe.fromBuild(Map<String, dynamic> row) {
    final output =
        row['state'] == 'ready' ? row['outputArtifact'] as Map? : null;
    return PortablePatchRecipe(
        recipe: PatchRecipe.fromJson(
            (row['recipe'] as Map).cast<String, dynamic>()),
        sourceGameId: row['sourceGameId'] as String,
        gameTitle: row['gameTitle'] as String,
        gameIndexPath: PatchRelativePath(row['gameIndexPath'] as String),
        title: row['title'] as String,
        outputSize: output?['sizeBytes'] as int?,
        outputSha256:
            (output?['providerChecksums'] as Map?)?['sha256'] as String?);
  }

  Map<String, dynamic> toJson() => {
        'schema': 'rshop.patch-recipe',
        'version': 1,
        'recipeId': recipe.id,
        'recipe': recipe.toJson(),
        'sourceGameId': sourceGameId,
        'gameTitle': gameTitle,
        'gameIndexPath': gameIndexPath.value,
        'title': title,
        if (outputSize != null) 'outputSize': outputSize,
        if (outputSha256 != null) 'outputSha256': outputSha256,
      };

  String encode() => jsonEncode(toJson());

  factory PortablePatchRecipe.decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('portable_patch_too_large');
    }
    try {
      final json = (jsonDecode(text) as Map).cast<String, dynamic>();
      _keys(json, const {
        'schema',
        'version',
        'recipeId',
        'recipe',
        'sourceGameId',
        'gameTitle',
        'gameIndexPath',
        'title',
        'outputSize',
        'outputSha256'
      });
      if (json['schema'] != 'rshop.patch-recipe' || json['version'] != 1) {
        throw const FormatException('unsupported_portable_patch_schema');
      }
      final raw = (json['recipe'] as Map).cast<String, dynamic>();
      _checkRecipe(raw);
      final recipe = PatchRecipe.fromJson(raw);
      if (json['recipeId'] != recipe.id) {
        throw const FormatException('portable_patch_identity_mismatch');
      }
      return PortablePatchRecipe(
          recipe: recipe,
          sourceGameId: json['sourceGameId'] as String,
          gameTitle: json['gameTitle'] as String,
          gameIndexPath: PatchRelativePath(json['gameIndexPath'] as String),
          title: json['title'] as String,
          outputSize: json['outputSize'] as int?,
          outputSha256: json['outputSha256'] as String?);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('invalid_portable_patch_recipe');
    }
  }

  static void _keys(Map json, Set<String> allowed) {
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('unexpected_portable_patch_field');
    }
  }

  static void _checkRecipe(Map<String, dynamic> json) {
    _keys(json, const {
      'schema',
      'platform',
      'base',
      'steps',
      'engineRevision',
      'preprocessing'
    });
    final base = json['base'] as Map;
    _keys(base, const {
      'rom_root_relative_path',
      'archive_member',
      'member_size',
      'member_hashes'
    });
    _keys(
        base['member_hashes'] as Map, const {'sha256', 'sha1', 'md5', 'crc32'});
    final steps = json['steps'] as List;
    if (steps.isEmpty || steps.length > 16) {
      throw const FormatException('invalid_portable_patch_steps');
    }
    for (final step in steps.cast<Map>()) {
      _keys(step, const {
        'source',
        'section',
        'sourceId',
        'version',
        'format',
        'sha256',
        'options'
      });
      if ((step['options'] as Map?)?.isNotEmpty ?? false) {
        throw const FormatException('unsupported_portable_patch_options');
      }
    }
    final preprocessing = json['preprocessing'] as List? ?? const [];
    if (preprocessing.isNotEmpty &&
        !(preprocessing.length == 1 &&
            preprocessing.single == 'ebp-canonical-base' &&
            steps.length == 1 &&
            (steps.single as Map)['format'] == 'ebp')) {
      throw const FormatException('unsupported_portable_patch_preparation');
    }
  }
}
