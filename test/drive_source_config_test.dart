import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/provider_config.dart';
import 'package:g_shop/models/config/source.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/services/config_parser.dart';
import 'package:g_shop/services/source_resolver.dart';

void main() {
  const drive = DriveSourceConfig(
    accountId: 'account-123',
    rootFolderId: 'folder-root-456',
    serverClientId: 'public-client.apps.googleusercontent.com',
  );

  group('DriveSourceConfig', () {
    test('round-trips only stable non-token configuration', () {
      final decoded = DriveSourceConfig.fromJson(drive.toJson());

      expect(decoded.accountId, 'account-123');
      expect(decoded.rootFolderId, 'folder-root-456');
      expect(
        decoded.serverClientId,
        'public-client.apps.googleusercontent.com',
      );
      expect(
        drive.toJson().keys,
        unorderedEquals(['account_id', 'root_folder_id', 'server_client_id']),
      );
      expect(jsonEncode(drive.toJson()), isNot(contains('access_token')));
      expect(jsonEncode(drive.toJson()), isNot(contains('bearer')));
    });

    test('reports blank identity fields as unconfigured', () {
      expect(drive.isConfigured, isTrue);
      expect(
        const DriveSourceConfig(
          accountId: '',
          rootFolderId: 'folder',
          serverClientId: 'client',
        ).isConfigured,
        isFalse,
      );
      expect(
        const DriveSourceConfig(
          accountId: 'account',
          rootFolderId: '',
          serverClientId: 'client',
        ).isConfigured,
        isFalse,
      );
      expect(
        const DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'folder',
          serverClientId: '',
        ).isConfigured,
        isFalse,
      );
    });
  });

  group('Drive source and provider persistence', () {
    test('appends enum values without changing existing indices', () {
      expect(SourceType.romm.index, 0);
      expect(SourceType.smb.index, 1);
      expect(SourceType.ftp.index, 2);
      expect(SourceType.web.index, 3);
      expect(SourceType.local.index, 4);
      expect(SourceType.drive.index, 5);

      expect(ProviderType.web.index, 0);
      expect(ProviderType.smb.index, 1);
      expect(ProviderType.ftp.index, 2);
      expect(ProviderType.romm.index, 3);
      expect(ProviderType.drive.index, 4);
    });

    test('source round-trip nests Drive config and never persists auth', () {
      const source = Source(
        id: 'drive-source',
        name: 'My Drive',
        type: SourceType.drive,
        drive: drive,
        auth: AuthConfig(
          user: 'must-not-persist',
          clientToken: 'must-not-persist',
        ),
      );

      final json = source.toJson();
      final decoded = Source.fromJson(json);

      expect(json['drive'], drive.toJson());
      expect(json, isNot(contains('auth')));
      expect(decoded.drive?.accountId, drive.accountId);
      expect(decoded.auth, isNull);
      expect(source.toJsonWithoutAuth(), json);
    });

    test('provider round-trip preserves mapped folder and source identity', () {
      const provider = ProviderConfig(
        type: ProviderType.drive,
        priority: 7,
        path: 'mapped-console-folder-id',
        drive: drive,
        sourceId: 'drive-source',
        managedBySource: true,
        auth: AuthConfig(clientToken: 'must-not-persist'),
      );

      final json = provider.toJson();
      final decoded = ProviderConfig.fromJson(json);

      expect(json['drive'], drive.toJson());
      expect(json['path'], 'mapped-console-folder-id');
      expect(json['source_id'], 'drive-source');
      expect(json, isNot(contains('auth')));
      expect(decoded.drive?.rootFolderId, drive.rootFolderId);
      expect(decoded.path, 'mapped-console-folder-id');
      expect(decoded.auth, isNull);
      expect(provider.toJsonWithoutAuth(), json);
      expect(provider.needsAuth, isFalse);
    });

    test('findMatchIn requires exact source, account and root identities', () {
      const target = ProviderConfig(
        type: ProviderType.drive,
        priority: 1,
        sourceId: 'source-a',
        path: 'system-folder-a',
        drive: drive,
      );
      const exact = ProviderConfig(
        type: ProviderType.drive,
        priority: 99,
        sourceId: 'source-a',
        path: 'different-system-folder-is-not-source-identity',
        drive: DriveSourceConfig(
          accountId: 'account-123',
          rootFolderId: 'folder-root-456',
          serverClientId: 'rotated-public-client.apps.googleusercontent.com',
        ),
      );

      expect(target.findMatchIn([exact]), same(exact));
      expect(
        target.findMatchIn([
          exact.copyWith(sourceId: 'source-b'),
        ]),
        isNull,
      );
      expect(
        target.findMatchIn([
          exact.copyWith(
            drive: const DriveSourceConfig(
              accountId: 'other-account',
              rootFolderId: 'folder-root-456',
              serverClientId: 'client',
            ),
          ),
        ]),
        isNull,
      );
      expect(
        target.findMatchIn([
          exact.copyWith(
            drive: const DriveSourceConfig(
              accountId: 'account-123',
              rootFolderId: 'other-root',
              serverClientId: 'client',
            ),
          ),
        ]),
        isNull,
      );
    });
  });

  group('Drive source resolution and migration compatibility', () {
    test('manual mapping resolves to a source-owned Drive provider', () {
      const system = SystemConfig(
        id: 'snes',
        name: 'SNES',
        targetFolder: '/roms/snes',
        providers: [],
        manualMappings: [
          SystemSourceMapping(
            sourceId: 'drive-source',
            remotePath: 'observed-snes-folder-id',
          ),
        ],
      );
      const source = Source(
        id: 'drive-source',
        name: 'My Drive',
        type: SourceType.drive,
        drive: drive,
      );

      final provider = SourceResolver.providersFor(system, [source]).single;

      expect(provider.type, ProviderType.drive);
      expect(provider.sourceId, source.id);
      expect(provider.drive?.accountId, drive.accountId);
      expect(provider.drive?.rootFolderId, drive.rootFolderId);
      expect(provider.path, 'observed-snes-folder-id');
      expect(provider.auth, isNull);
    });

    test('mixed migrated legacy and Drive config round-trips without loss', () {
      final legacy = AppConfig.fromJson({
        'version': 2,
        'systems': [
          {
            'id': 'snes',
            'name': 'SNES',
            'target_folder': '/roms/snes',
            'providers': [
              {
                'type': 'web',
                'priority': 20,
                'url': 'https://legacy.example/roms',
              },
            ],
          },
        ],
      });
      final legacySystem = legacy.systems.single;
      final driveProvider = const ProviderConfig(
        type: ProviderType.drive,
        priority: 10,
        path: 'observed-snes-folder-id',
        drive: drive,
        managedBySource: true,
        sourceId: 'drive-source',
      );
      final mixed = legacy.copyWith(
        sources: [
          ...legacy.sources,
          const Source(
            id: 'drive-source',
            name: 'My Drive',
            type: SourceType.drive,
            drive: drive,
          ),
        ],
        systems: [
          legacySystem.copyWith(
            providers: [...legacySystem.providers, driveProvider],
            manualMappings: [
              ...legacySystem.manualMappings,
              const SystemSourceMapping(
                sourceId: 'drive-source',
                remotePath: 'observed-snes-folder-id',
              ),
            ],
          ),
        ],
      );

      final decoded = AppConfig.fromJson(
        jsonDecode(jsonEncode(mixed.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.sources, hasLength(2));
      expect(decoded.sources.first.type, SourceType.web);
      expect(decoded.sources.last.type, SourceType.drive);
      expect(decoded.sources.last.drive?.accountId, drive.accountId);
      expect(decoded.systems.single.providers, hasLength(2));
      final decodedDriveProvider = decoded.systems.single.providers
          .singleWhere((provider) => provider.type == ProviderType.drive);
      expect(decodedDriveProvider.type, ProviderType.drive);
      expect(
        decodedDriveProvider.path,
        'observed-snes-folder-id',
      );
      expect(
          decoded.systems.single.manualMappings.last.sourceId, 'drive-source');
    });

    test('config parser rejects Drive providers without exact source identity',
        () {
      final json = jsonEncode({
        'version': AppConfig.currentVersion,
        'sources': [
          {
            'id': 'drive-source',
            'name': 'My Drive',
            'type': 'drive',
            'drive': drive.toJson(),
          },
        ],
        'systems': [
          {
            'id': 'snes',
            'name': 'SNES',
            'target_folder': '/roms/snes',
            'providers': [
              {
                'type': 'drive',
                'priority': 1,
                'path': 'observed-snes-folder-id',
                'drive': drive.toJson(),
              },
            ],
          },
        ],
      });

      expect(
        () => ConfigParser.parse(json),
        throwsA(
          isA<ConfigParseException>().having(
            (e) => e.message,
            'message',
            contains('source_id'),
          ),
        ),
      );
    });
  });
}
