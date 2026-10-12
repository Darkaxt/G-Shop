import 'dart:convert';

/// A card's role comes from the installed core configuration. Shared cards are
/// resources used by many games, not another member of one game's private save.
class PcsxSaveCard {
  final int slot;
  final String mode;
  final String? name;
  const PcsxSaveCard._(this.slot, this.mode, this.name);
  bool get isShared => mode == 'shared';
  bool get needsDiscSerial => mode == 'serial' && name == null;
}

class PcsxSaveLayout {
  final String directory;
  final List<PcsxSaveCard> cards;
  const PcsxSaveLayout._(this.directory, this.cards);

  Map<String, dynamic> toJson() => {
        'directory': directory,
        'cards': [
          for (final card in cards)
            {'slot': card.slot, 'mode': card.mode, 'name': card.name}
        ],
      };

  bool containsSelection(PcsxSaveLayout selected, PcsxSaveCard card) =>
      directory == selected.directory &&
      cards.any((current) =>
          current.slot == card.slot &&
          current.mode == card.mode &&
          current.name == card.name);

  /// Stable across the initiating ROM, distinct for different card slots and
  /// configured directories. This is not a fabricated catalogue game identity.
  String sharedResourceKey(PcsxSaveCard card) {
    if (!cards.contains(card) || !card.isShared) {
      throw ArgumentError('Not a shared card in this layout');
    }
    return jsonEncode(
        ['com.retroarch.aarch64', 'pcsx_rearmed', directory, card.slot]);
  }

  static PcsxSaveLayout decode(Map<String, dynamic>? raw) {
    if (raw == null ||
        raw.length != 2 ||
        raw['directory'] is! String ||
        raw['cards'] is! List) {
      throw const FormatException('Invalid PlayStation save mapping');
    }
    final directory = raw['directory'] as String;
    if (directory.length > 4096 ||
        !RegExp(r'^/storage/(emulated/0|[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4})/.+$')
            .hasMatch(directory) ||
        directory.split('/').skip(1).any((part) =>
            part.isEmpty ||
            part == '.' ||
            part == '..' ||
            RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(part)) ||
        (directory.split('/').any((part) => part.toLowerCase() == 'android') &&
            !directory.startsWith(
                '/storage/emulated/0/Android/data/com.retroarch.aarch64/files/'))) {
      throw const FormatException('Invalid PlayStation save folder');
    }
    final rows = raw['cards'] as List;
    if (rows.length > 2) throw const FormatException('Invalid memory cards');
    final cards = <PcsxSaveCard>[];
    var previous = 0;
    for (final row in rows) {
      if (row is! Map ||
          row.length != 3 ||
          !row.keys.toSet().containsAll({'slot', 'mode', 'name'}) ||
          row['slot'] is! int ||
          row['mode'] is! String ||
          !(row['name'] == null || row['name'] is String)) {
        throw const FormatException('Invalid memory card');
      }
      final slot = row['slot'] as int;
      final mode = row['mode'] as String;
      final name = row['name'] as String?;
      if (slot <= previous ||
          slot > 2 ||
          !(slot == 1 ? {'libretro', 'serial', 'shared'} : {'serial', 'shared'})
              .contains(mode) ||
          (mode == 'serial' ? name != null : name == null) ||
          (mode == 'shared' && name != 'pcsx-card$slot.mcd') ||
          (mode == 'libretro' &&
              (name!.length < 5 ||
                  name.length > 255 ||
                  !name.endsWith('.srm') ||
                  RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(name)))) {
        throw const FormatException('Invalid memory card association');
      }
      previous = slot;
      cards.add(PcsxSaveCard._(slot, mode, name));
    }
    return PcsxSaveLayout._(directory, List.unmodifiable(cards));
  }
}
