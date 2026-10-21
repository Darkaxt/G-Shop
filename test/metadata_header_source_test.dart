import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/config/app_config.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/source.dart';
import 'package:g_shop/models/config/system_config.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/providers/metadata_providers.dart';

void main() {
  final artifact = RemoteArtifact(
      id: RemoteArtifactId(
          providerId: 'drive',
          sourceId: 'source',
          accountId: 'account',
          providerFileId: 'file'),
      displayName: 'Fixture.chd',
      displayPath: 'Fixture.chd');
  const source = Source(
      id: 'source',
      name: 'Fixture',
      type: SourceType.drive,
      drive: DriveSourceConfig(
          accountId: 'account',
          rootFolderId: 'root',
          serverClientId: 'public-client'));
  const system = SystemConfig(
      id: 'psp',
      name: 'PSP',
      targetFolder: '/roms/psp',
      providers: [],
      manualMappings: [
        SystemSourceMapping(sourceId: 'source', remotePath: 'psp-folder')
      ]);
  test(
      'metadata header uses only the enabled exact platform/account/source mapping',
      () {
    AppConfig config(
            {List<Source> sources = const [source],
            List<SystemConfig> systems = const [system]}) =>
        AppConfig(sources: sources, systems: systems);
    final selected = metadataHeaderSource(config(), artifact, 'psp');
    expect(selected!.path, 'psp-folder');
    expect(selected.drive!.rootFolderId, 'root');
    expect(metadataHeaderSource(config(), artifact, 'ps2'), isNull);
    expect(
        metadataHeaderSource(config(sources: [source.copyWith(enabled: false)]),
            artifact, 'psp'),
        isNull);
    expect(metadataHeaderSource(config(sources: []), artifact, 'psp'), isNull);
    expect(
        metadataHeaderSource(
            config(sources: [source, source]), artifact, 'psp'),
        isNull);
    expect(
        metadataHeaderSource(
            config(systems: [system, system]), artifact, 'psp'),
        isNull);
    expect(
        metadataHeaderSource(
            config(systems: [system.copyWith(enabledSourceIds: [])]),
            artifact,
            'psp'),
        isNull);
    final foreign = RemoteArtifact.fromJson({
      ...artifact.toJson(),
      'id': {...artifact.id.toJson(), 'accountId': 'foreign'}
    });
    expect(metadataHeaderSource(config(), foreign, 'psp'), isNull);
  });
}
