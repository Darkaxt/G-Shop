import 'dart:convert';
import 'package:flutter/services.dart';

class EmulatorRegistration {
  final String packageName, family, name;
  const EmulatorRegistration(this.packageName, this.family, this.name);
  Map<String, String> toJson() =>
      {'package': packageName, 'family': family, 'name': name};
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
          entry.length != 3 ||
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
      result[package] = EmulatorRegistration(package, family, name);
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
