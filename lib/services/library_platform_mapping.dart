import '../models/system_model.dart';

enum PlatformMappingStatus { supported, unsupported, unknown }

class PlatformMappingResult {
  final String folderName;
  final String? requestedPlatformId;
  final PlatformMappingStatus status;
  final bool isOverride;

  const PlatformMappingResult({
    required this.folderName,
    required this.requestedPlatformId,
    required this.status,
    required this.isOverride,
  });

  /// Only an actual G-Shop system may become an active mapping.
  String? get activePlatformId =>
      status == PlatformMappingStatus.supported ? requestedPlatformId : null;
}

/// Exact, testable folder aliases without substring or filename inference.
class LibraryPlatformMapping {
  LibraryPlatformMapping._();

  static final Set<String> _supportedIds = {
    for (final system in SystemModel.supportedSystems) system.id,
  };

  static final Map<String, String> _aliases = {
    // These names and identifiers are explicitly declared by the app catalog.
    for (final system in SystemModel.supportedSystems) ...{
      _normalize(system.id): system.id,
      _normalize(system.name): system.id,
      if (system.libretroId.isNotEmpty)
        _normalize(system.libretroId): system.id,
      _normalize('${system.manufacturer} ${system.name}'): system.id,
    },
    // Additional established folder aliases for the supported manufacturers.
    'famicom': 'nes',
    'nintendofamicom': 'nes',
    'superfamicom': 'snes',
    'nintendosuperfamicom': 'snes',
    'supernes': 'snes',
    'supernintendoentertainmentsystem': 'snes',
    'gamecube': 'gc',
    'gcn': 'gc',
    'gameboy': 'gb',
    'gameboycolor': 'gbc',
    'gameboyadvance': 'gba',
    'ds': 'nds',
    '3ds': 'n3ds',
    'familycomputerdisksystem': 'fds',
    'gameandwatch': 'gameandwatch',
    'ps': 'psx',
    'ps1': 'psx',
    'playstation1': 'psx',
    'sonyplaystation1': 'psx',
    'psvita': 'psvita',
    'genesis': 'megadrive',
    'segagenesis': 'megadrive',
    'md': 'megadrive',
    'megacd': 'segacd',
    'segamegacd': 'segacd',
    'sms': 'mastersystem',
    'gg': 'gamegear',
    '32x': 'sega32x',
    'dc': 'dreamcast',
    'msdos': 'dos',
    'microsoftmsdos': 'dos',
    // Known absent platforms remain visible as unsupported, never active.
    'xbox': 'xbox',
    'microsoftxbox': 'xbox',
    'xbox360': 'xbox360',
    'microsoftxbox360': 'xbox360',
    'xboxone': 'xboxone',
    'microsoftxboxone': 'xboxone',
    'xboxseries': 'xboxseries',
    'xboxseriesx': 'xboxseries',
    'xboxseriess': 'xboxseries',
    'ps4': 'ps4',
    'playstation4': 'ps4',
    'sonyplaystation4': 'ps4',
    'ps5': 'ps5',
    'playstation5': 'ps5',
    'sonyplaystation5': 'ps5',
    'switch2': 'switch2',
    'nintendoswitch2': 'switch2',
  };

  /// [overridePlatformId] is a user-assigned canonical system slug. The caller
  /// persists it against the exact source/account/folder ID, never a shared
  /// folder-name key. A stale or unsupported assignment is reported without
  /// falling back to an alias that would silently replace the user's choice.
  static PlatformMappingResult resolve(
    String folderName, {
    String? overridePlatformId,
  }) {
    final requested = overridePlatformId ?? _aliases[_normalize(folderName)];
    final status = requested == null
        ? PlatformMappingStatus.unknown
        : _supportedIds.contains(requested)
            ? PlatformMappingStatus.supported
            : PlatformMappingStatus.unsupported;
    return PlatformMappingResult(
      folderName: folderName,
      requestedPlatformId: requested,
      status: status,
      isOverride: overridePlatformId != null,
    );
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
}
