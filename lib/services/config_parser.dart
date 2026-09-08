import 'dart:convert';
import 'dart:io';

import '../models/config/app_config.dart';
import '../models/config/provider_config.dart';
import '../models/config/source.dart';

class ConfigParseException implements Exception {
  final String message;
  const ConfigParseException(this.message);

  @override
  String toString() => 'ConfigParseException: $message';
}

class ConfigParser {
  ConfigParser._();

  static AppConfig parse(String jsonString) {
    final Object decoded;
    try {
      decoded = json.decode(jsonString);
    } catch (e) {
      throw const ConfigParseException('Invalid JSON');
    }

    final AppConfig config;
    try {
      config = AppConfig.fromJson(decoded as Map<String, dynamic>);
    } catch (e) {
      throw ConfigParseException('Failed to parse config: $e');
    }

    _validate(config);
    return config;
  }

  static Future<AppConfig> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ConfigParseException('Config file not found: $filePath');
    }
    final contents = await file.readAsString();
    return parse(contents);
  }

  static void _validate(AppConfig config) {
    final seenIds = <String>{};
    final seenSourceIds = <String>{};

    for (final system in config.systems) {
      if (system.id.isEmpty) {
        throw const ConfigParseException('System ID must not be empty');
      }
      if (system.name.isEmpty) {
        throw const ConfigParseException('System name must not be empty');
      }
      if (system.targetFolder.isEmpty) {
        throw const ConfigParseException(
            'System target_folder must not be empty');
      }
      if (system.targetFolder.contains('..')) {
        throw ConfigParseException(
            'System target_folder must not contain "..": "${system.id}"');
      }
      if (!seenIds.add(system.id)) {
        throw ConfigParseException('Duplicate system ID: "${system.id}"');
      }

      for (final provider in system.providers) {
        _validateProvider(provider, system.id);
      }
    }

    for (final source in config.sources) {
      if (source.id.trim().isEmpty) {
        throw const ConfigParseException('Source ID must not be empty');
      }
      if (!seenSourceIds.add(source.id)) {
        throw ConfigParseException('Duplicate source ID: "${source.id}"');
      }
      if (source.type == SourceType.drive &&
          (source.drive == null || !source.drive!.isConfigured)) {
        throw ConfigParseException(
          'Drive source "${source.id}" requires account_id, root_folder_id, and server_client_id',
        );
      }
    }
  }

  static void _validateProvider(ProviderConfig provider, String systemId) {
    switch (provider.type) {
      case ProviderType.web:
        if (provider.url == null || provider.url!.isEmpty) {
          throw ConfigParseException(
              'WEB provider for "$systemId" requires a url');
        }
      case ProviderType.smb:
        if (provider.host == null || provider.host!.isEmpty) {
          throw ConfigParseException(
              'SMB provider for "$systemId" requires a host');
        }
        if (provider.share == null || provider.share!.isEmpty) {
          throw ConfigParseException(
              'SMB provider for "$systemId" requires a share');
        }
      case ProviderType.ftp:
        if (provider.host == null || provider.host!.isEmpty) {
          throw ConfigParseException(
              'FTP provider for "$systemId" requires a host');
        }
      case ProviderType.romm:
        if (provider.url == null || provider.url!.isEmpty) {
          throw ConfigParseException(
              'ROMM provider for "$systemId" requires a url');
        }
        if (provider.platformId == null) {
          throw ConfigParseException(
              'ROMM provider for "$systemId" requires a platformId');
        }
      case ProviderType.drive:
        if (provider.sourceId == null || provider.sourceId!.trim().isEmpty) {
          throw ConfigParseException(
              'DRIVE provider for "$systemId" requires a source_id');
        }
        if (provider.drive == null || !provider.drive!.isConfigured) {
          throw ConfigParseException(
              'DRIVE provider for "$systemId" requires complete drive configuration');
        }
        if (provider.path == null || provider.path!.trim().isEmpty) {
          throw ConfigParseException(
              'DRIVE provider for "$systemId" requires a mapped folder ID');
        }
    }
  }
}
