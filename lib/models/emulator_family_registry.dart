import 'dart:convert';
import 'package:flutter/services.dart';
import 'save_root_configuration.dart';

class EmulatorSavePreset {
  final String name, platform, _mapping;
  const EmulatorSavePreset._(this.name, this.platform, this._mapping);

  factory EmulatorSavePreset.decode(Map row, String package) {
    if (row.length != 3 ||
        row['name'] is! String ||
        row['platform'] is! String ||
        row['mapping'] is! Map ||
        (row['name'] as String).trim().isEmpty ||
        (row['name'] as String).length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(row['name']) ||
        !RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(row['platform']) ||
        (row['mapping'] as Map).containsKey('schema') ||
        (row['mapping'] as Map).containsKey('emulator')) {
      throw const FormatException('Invalid save-location preset');
    }
    final preset = EmulatorSavePreset._(
        row['name'], row['platform'], jsonEncode(row['mapping']));
    preset.resolve(package, 'Mapping.rom');
    return preset;
  }

  SaveRootConfiguration resolve(String package, String romName) =>
      SaveRootConfiguration.decode({
        ...Map<String, dynamic>.from(
            jsonDecode(_mapping.replaceAll('{package}', package)) as Map),
        'schema': 1,
        'emulator': package,
      }, romName: romName);

  Map<String, Object> toJson() =>
      {'name': name, 'platform': platform, 'mapping': jsonDecode(_mapping)};
}

class EmulatorRegistration {
  final String packageName, family, name;
  final List<EmulatorSavePreset> saveRoots;
  const EmulatorRegistration(this.packageName, this.family, this.name,
      {this.saveRoots = const []});
  Map<String, Object> toJson() => {
        'package': packageName,
        'family': family,
        'name': name,
        if (saveRoots.isNotEmpty)
          'saveRoots': saveRoots.map((p) => p.toJson()).toList(),
      };
}

/// Registration/classification only. Never grants file access or changes the
/// exact package, core, version or save-history binding of an existing job.
class EmulatorFamilyRegistry {
  static const assetPath = 'assets/config/emulator_families.json';
  static const maxBytes = 65536;
  static const familyNames = <String, String>{
    'retroarch': 'RetroArch',
    'ppsspp': 'PPSSPP',
    'dolphin': 'Dolphin',
    'azahar': 'Azahar / Citra',
    'melonds': 'melonDS',
    'dusk': 'Dusk',
    'kenjinx': 'KenjiNX / Ryujinx',
    'eden': 'Eden / Yuzu',
    'flycast': 'Flycast',
    'neostation': 'NeoStation',
    'pcsx2': 'PCSX2 / NetherSX2',
    'cemu': 'Cemu',
    'launcher': 'Launcher',
    'rom-engine': 'ROM-derived engine',
    'custom': 'Custom emulator',
  };
  final Map<String, EmulatorRegistration> packages;
  EmulatorFamilyRegistry._(Map<String, EmulatorRegistration> entries)
      : packages = Map.unmodifiable(entries);

  factory EmulatorFamilyRegistry.decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('Emulator configuration is too large');
    }
    final row = jsonDecode(text);
    if (row is! Map ||
        row.length != 2 ||
        row['schema'] != 1 ||
        row['packages'] is! List) {
      throw const FormatException('Invalid emulator configuration');
    }
    final entries = row['packages'] as List;
    if (entries.isEmpty || entries.length > 64) {
      throw const FormatException('Use between 1 and 64 package registrations');
    }
    final result = <String, EmulatorRegistration>{};
    for (final entry in entries) {
      if (entry is! Map ||
          entry.keys.toSet().difference(
              {'package', 'family', 'name', 'saveRoots'}).isNotEmpty ||
          entry['package'] is! String ||
          entry['family'] is! String ||
          entry['name'] is! String) {
        throw const FormatException(
            'Each package needs package, family and name');
      }
      final package = entry['package'] as String;
      final family = entry['family'] as String;
      final name = entry['name'] as String;
      if (package.length > 255 ||
          !RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')
              .hasMatch(package) ||
          result.containsKey(package) ||
          !familyNames.containsKey(family) ||
          name.trim() != name ||
          name.isEmpty ||
          name.length > 80 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
        throw const FormatException(
            'Invalid or duplicate emulator registration');
      }
      final roots = entry['saveRoots'] ?? <Object>[];
      if (roots is! List || roots.length > 8 || roots.any((p) => p is! Map)) {
        throw const FormatException('Invalid save-location presets');
      }
      final presets = roots
          .map((p) => EmulatorSavePreset.decode(p as Map, package))
          .toList();
      if (presets.map((p) => '${p.platform}:${p.name}').toSet().length !=
          presets.length) {
        throw const FormatException('Duplicate save-location preset');
      }
      result[package] = EmulatorRegistration(package, family, name,
          saveRoots: List.unmodifiable(presets));
    }
    return EmulatorFamilyRegistry._(result);
  }
  String encode() => const JsonEncoder.withIndent('  ').convert({
        'schema': 1,
        'packages': packages.values.map((p) => p.toJson()).toList(),
      });
  static Future<EmulatorFamilyRegistry> load({
    AssetBundle? bundle,
  }) async {
    return EmulatorFamilyRegistry.decode(
        await (bundle ?? rootBundle).loadString(assetPath));
  }
}
