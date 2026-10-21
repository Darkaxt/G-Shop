import 'dart:convert';
import 'dart:io';
import 'console_model.dart';

/// Private, explicit archive-to-reference-art bindings. A reference carton is
/// not proof of an owned cartridge's colour, screw revision or printing.
class NesBoxEdition {
  final String id, label, manifestSha256;
  const NesBoxEdition(this.id, this.label, this.manifestSha256);
  Future<ConsoleModel?> load({Directory? modelsDirectory}) =>
      ConsoleModel.findNesBox(id,
          manifestSha256: manifestSha256, modelsDirectory: modelsDirectory);
}

class NesMediaCatalogue {
  final Map<String, NesBoxEdition> editions;
  final Map<String, List<String>> bindings;
  const NesMediaCatalogue._(this.editions, this.bindings);

  List<NesBoxEdition> forArchive(String filename) =>
      [for (final id in bindings[filename] ?? const <String>[]) editions[id]!];

  static Future<NesMediaCatalogue?> load({Directory? modelsDirectory}) async {
    if (modelsDirectory == null && !Platform.isAndroid) return null;
    final root =
        modelsDirectory ?? Directory('/storage/emulated/0/RShop/models');
    final file = File('${root.path}/boxes/nes/catalogue.json');
    if (!await file.exists()) return null;
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('NES catalogue exceeds import size');
    }
    return parse(jsonDecode(await file.readAsString()));
  }

  static NesMediaCatalogue parse(dynamic data) {
    if (data is! Map ||
        data['schemaVersion'] != 1 ||
        data['system'] != 'nes' ||
        data['editions'] is! List ||
        data['bindings'] is! Map ||
        (data['editions'] as List).length > 1024 ||
        (data['bindings'] as Map).length > 20000) {
      throw const FormatException('Invalid NES reference catalogue');
    }
    final editions = <String, NesBoxEdition>{};
    for (final entry in data['editions']) {
      if (entry is! Map ||
          entry['id'] is! String ||
          !RegExp(r'^nes-[a-f0-9]{12}$').hasMatch(entry['id']) ||
          editions.containsKey(entry['id']) ||
          entry['label'] is! String ||
          (entry['label'] as String).isEmpty ||
          (entry['label'] as String).length > 180 ||
          entry['manifestSha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry['manifestSha256'])) {
        throw const FormatException('Invalid NES carton edition');
      }
      editions[entry['id']] =
          NesBoxEdition(entry['id'], entry['label'], entry['manifestSha256']);
    }
    final bindings = <String, List<String>>{};
    for (final entry in (data['bindings'] as Map).entries) {
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          (entry.key as String).length > 500 ||
          (entry.key as String).contains(RegExp(r'[/\\]')) ||
          entry.value is! List ||
          (entry.value as List).isEmpty ||
          (entry.value as List).length > 32) {
        throw const FormatException('Invalid NES archive binding');
      }
      final ids = <String>[];
      for (final id in entry.value) {
        if (id is! String || !editions.containsKey(id) || ids.contains(id)) {
          throw const FormatException('Unknown or duplicate NES reference');
        }
        ids.add(id);
      }
      bindings[entry.key] = List.unmodifiable(ids);
    }
    return NesMediaCatalogue._(
        Map.unmodifiable(editions), Map.unmodifiable(bindings));
  }
}
