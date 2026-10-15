import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A collection-root-relative reference, never an absolute device path or URL.
class PatchRelativePath {
  final String value;
  PatchRelativePath(this.value) {
    if (value.isEmpty ||
        value.startsWith('/') ||
        RegExp(r'[\\:\x00-\x1f]').hasMatch(value) ||
        value.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw const FormatException('unsafe_patch_reference');
    }
  }
  List<String> get segments => value.split('/');
  PatchRelativePath child(String relative) =>
      PatchRelativePath('$value/${PatchRelativePath(relative).value}');
}

enum PatchFormat { ips, ips32, ups, bps, aps, ppf, xdelta, dps, ebp }

PatchFormat? patchFormat(String filename) =>
    switch (p.posix.extension(filename).toLowerCase()) {
      '.ips' => PatchFormat.ips,
      '.ips32' => PatchFormat.ips32,
      '.ups' => PatchFormat.ups,
      '.bps' => PatchFormat.bps,
      '.aps' => PatchFormat.aps,
      '.ppf' => PatchFormat.ppf,
      '.xdelta' || '.xdelta3' || '.xd' || '.vcdiff' => PatchFormat.xdelta,
      '.dps' => PatchFormat.dps,
      '.ebp' => PatchFormat.ebp,
      _ => null,
    };

class IndexedPatchBase {
  final PatchRelativePath relativePath;
  final PatchRelativePath? archiveMember;
  final int sizeBytes;
  final Map<String, String> checksums;
  IndexedPatchBase({
    required this.relativePath,
    this.archiveMember,
    required this.sizeBytes,
    required Map<String, String> checksums,
  }) : checksums = _hashes(checksums) {
    if (sizeBytes <= 0 ||
        !this.checksums.keys.any(const {'sha256', 'sha1', 'md5'}.contains)) {
      throw const FormatException('missing_base_fingerprint');
    }
  }
  factory IndexedPatchBase.fromJson(Map<String, dynamic> json) =>
      IndexedPatchBase(
        relativePath: PatchRelativePath(_text(json, 'rom_root_relative_path')),
        archiveMember: json['archive_member'] == null
            ? null
            : PatchRelativePath(_text(json, 'archive_member')),
        sizeBytes: _size(json['member_size']),
        checksums: _hashes(json['member_hashes']),
      );
  Map<String, dynamic> toJson() => {
        'rom_root_relative_path': relativePath.value,
        if (archiveMember != null) 'archive_member': archiveMember!.value,
        'member_size': sizeBytes,
        'member_hashes': checksums,
      };

  /// Location and archive-member naming are not content identity.
  Map<String, dynamic> get content => {
        'size': sizeBytes,
        'hashes': checksums,
      };
}

class IndexedPatchPayload {
  final String relativePath;
  final int sizeBytes;
  final String sha256;
  final PatchFormat format;
  IndexedPatchPayload(
      {required String relativePath,
      required this.sizeBytes,
      required String sha256,
      required this.format})
      : relativePath = PatchRelativePath(relativePath).value,
        sha256 = _digest(sha256, 64) {
    if (sizeBytes <= 0) throw const FormatException('invalid_patch_size');
  }
}

class IndexedRomPatch {
  final String source;
  final String section;
  final String sourceId;
  final String title;
  final String version;
  final String description;
  final String? language;
  final String? sourceUrl;
  final List<IndexedPatchBase> bases;
  final List<IndexedPatchPayload> payloads;
  final List<String> unsupportedFiles;
  IndexedRomPatch(
      {required this.source,
      required this.section,
      required this.sourceId,
      required this.title,
      required this.version,
      required this.description,
      this.language,
      this.sourceUrl,
      required List<IndexedPatchBase> bases,
      required List<IndexedPatchPayload> payloads,
      required List<String> unsupportedFiles})
      : bases = List.unmodifiable(bases),
        payloads = List.unmodifiable(payloads),
        unsupportedFiles = List.unmodifiable(unsupportedFiles);
  String get id => jsonEncode([source, section, sourceId]);
  String? get unavailableReason => bases.isEmpty
      ? 'no_verified_base_reference'
      : payloads.isEmpty
          ? 'no_supported_patch_payload'
          : null;
}

/// Schema-2 producer data is consumed without modifying its unknown fields.
/// Both current package layouts share source/section/id, never display titles.
class PatchSourceIndex {
  final List<IndexedRomPatch> patches;
  PatchSourceIndex._(List<IndexedRomPatch> patches)
      : patches = List.unmodifiable(patches);
  factory PatchSourceIndex.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 2) {
      throw const FormatException('unsupported_patch_index_schema');
    }
    final source = _text(json, 'source');
    final sections = _map(json['sections']);
    final packages = _list(json['payloads']).map(_map).toList();
    final patches = <IndexedRomPatch>[];
    final ids = <String>{};
    for (final section in const ['hacks', 'translations']) {
      for (final value in _list(sections[section])) {
        final entry = _map(value);
        final id = _text(entry, 'source_id');
        if (!ids.add('$section:$id')) {
          throw const FormatException('duplicate_patch_identity');
        }
        final fields = _map(entry['source_fields']);
        final payloads = <IndexedPatchPayload>[];
        final unsupported = <String>[];
        final paths = <String>{};
        for (final package in packages.where((item) =>
            item['section'] == section && item['source_id'].toString() == id)) {
          if (package['role'] == 'external_readme') continue;
          final extraction = _map(package['extraction'] ?? const {});
          if (extraction['status'] != 'extracted') continue;
          final folder =
              PatchRelativePath(_text(package, 'patch_folder_relative_path'));
          for (final value in _list(extraction['files'])) {
            final file = _map(value);
            final relative = _text(file, 'relative_path');
            final path = folder.child(relative).value;
            if (!paths.add(path)) {
              throw const FormatException('duplicate_patch_payload');
            }
            final format = patchFormat(relative);
            if (format == null) {
              // Readmes are auxiliary, installers and unknown binaries stay
              // explainable but are never executable/selectable patch engines.
              if (!const {
                '.txt',
                '.md',
                '.html',
                '.htm',
                '.pdf',
                '.png',
                '.jpg',
                '.jpeg',
                '.gif',
                '.rtf',
                '.nfo'
              }.contains(p.posix.extension(relative).toLowerCase())) {
                unsupported.add(path);
              }
              continue;
            }
            payloads.add(IndexedPatchPayload(
                relativePath: path,
                sizeBytes: _size(file['size']),
                sha256: _text(file, 'sha256'),
                format: format));
          }
        }
        patches.add(IndexedRomPatch(
            source: source,
            section: section,
            sourceId: id,
            title: (fields['hacktitle'] ??
                    fields['title'] ??
                    fields['transname'] ??
                    '$section $id')
                .toString(),
            version: (fields['version'] ?? fields['patchver'] ?? '').toString(),
            description: (fields['description'] ?? '').toString(),
            language: fields['language']?.toString(),
            sourceUrl: entry['source_url']?.toString(),
            bases: _list(entry['rom_files'])
                .map((base) => IndexedPatchBase.fromJson(_map(base)))
                .toList(),
            payloads: payloads,
            unsupportedFiles: unsupported));
      }
    }
    return PatchSourceIndex._(patches);
  }
}

class PatchRecipeStep {
  final String source;
  final String section;
  final String sourceId;
  final String version;
  final PatchFormat format;
  final String patchSha256;
  final Map<String, dynamic> options;
  PatchRecipeStep(
      {required this.source,
      required this.section,
      required this.sourceId,
      required this.version,
      required this.format,
      required String patchSha256,
      Map<String, dynamic> options = const {}})
      : patchSha256 = _digest(patchSha256, 64),
        options = Map.unmodifiable(options);
  factory PatchRecipeStep.fromPatch(
          IndexedRomPatch patch, IndexedPatchPayload payload) =>
      PatchRecipeStep(
          source: patch.source,
          section: patch.section,
          sourceId: patch.sourceId,
          version: patch.version,
          format: payload.format,
          patchSha256: payload.sha256);
  factory PatchRecipeStep.fromJson(Map<String, dynamic> json) =>
      PatchRecipeStep(
          source: _text(json, 'source'),
          section: _text(json, 'section'),
          sourceId: _text(json, 'sourceId'),
          version: (json['version'] ?? '').toString(),
          format: PatchFormat.values.byName(_text(json, 'format')),
          patchSha256: _text(json, 'sha256'),
          options: _map(json['options'] ?? const {}));
  Map<String, dynamic> toJson() => {
        'source': source,
        'section': section,
        'sourceId': sourceId,
        'version': version,
        'format': format.name,
        'sha256': patchSha256,
        'options': options,
      };
}

class PatchRecipe {
  final String platformId;
  final IndexedPatchBase base;
  final List<PatchRecipeStep> steps;
  final String engineRevision;
  final List<String> preprocessing;
  PatchRecipe(
      {required this.platformId,
      required this.base,
      required List<PatchRecipeStep> steps,
      required this.engineRevision,
      List<String> preprocessing = const []})
      : steps = List.unmodifiable(steps),
        preprocessing = List.unmodifiable(preprocessing) {
    if (platformId.isEmpty || engineRevision.isEmpty || steps.isEmpty) {
      throw const FormatException('incomplete_patch_recipe');
    }
  }
  String get id => sha256
      .convert(utf8.encode(jsonEncode(_canonical({
        'schema': 1,
        'platform': platformId,
        'base': base.content,
        'steps': steps.map((step) => step.toJson()).toList(),
        'engine': {'name': 'UniPatcher', 'revision': engineRevision},
        'preprocessing': preprocessing,
      }))))
      .toString();
  Map<String, dynamic> toJson() => {
        'schema': 1,
        'platform': platformId,
        'base': base.toJson(),
        'steps': steps.map((step) => step.toJson()).toList(),
        'engineRevision': engineRevision,
        'preprocessing': preprocessing,
      };
  factory PatchRecipe.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('unsupported_patch_recipe_schema');
    }
    return PatchRecipe(
        platformId: _text(json, 'platform'),
        base: IndexedPatchBase.fromJson(_map(json['base'])),
        steps: _list(json['steps'])
            .map((step) => PatchRecipeStep.fromJson(_map(step)))
            .toList(),
        engineRevision: _text(json, 'engineRevision'),
        preprocessing: _list(json['preprocessing']).cast<String>());
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('invalid_patch_index_object');
  return value.cast<String, dynamic>();
}

List<dynamic> _list(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('invalid_patch_index_list');
  return value;
}

String _text(Map<String, dynamic> value, String key) {
  final text = value[key]?.toString();
  if (text == null || text.isEmpty) {
    throw const FormatException('missing_patch_index_field');
  }
  return text;
}

int _size(Object? value) {
  if (value is! int || value <= 0) {
    throw const FormatException('invalid_patch_size');
  }
  return value;
}

String _digest(String value, int length) {
  if (!RegExp('^[0-9a-fA-F]{$length}\$').hasMatch(value)) {
    throw const FormatException('invalid_patch_fingerprint');
  }
  return value.toLowerCase();
}

Map<String, String> _hashes(Object? value) {
  final hashes = _map(value);
  const lengths = {'sha256': 64, 'sha1': 40, 'md5': 32, 'crc32': 8};
  return Map.unmodifiable({
    for (final entry in hashes.entries)
      if (lengths.containsKey(entry.key))
        entry.key: _digest(entry.value.toString(), lengths[entry.key]!),
  });
}

Object? _canonical(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
