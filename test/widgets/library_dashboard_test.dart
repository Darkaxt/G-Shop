import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/library/widgets/library_dashboard.dart';
import 'package:retro_eshop/features/library/widgets/library_entry.dart';
import 'package:retro_eshop/l10n/app_localizations.dart';
import 'package:retro_eshop/models/config/provider_config.dart';
import 'package:retro_eshop/models/library_identity.dart';
import 'package:retro_eshop/providers/installed_files_provider.dart';

void main() {
  LibraryEntry entry(String id, {int? bytes, String slug = 'psx'}) =>
      LibraryEntry(
          filename: 'Same name.chd',
          displayName: 'Same name',
          cardTitle: 'Same name',
          url: '',
          systemSlug: slug,
          providerConfig: const ProviderConfig(
              type: ProviderType.drive, priority: 1, sourceId: 'source'),
          remoteArtifact: RemoteArtifact(
              id: RemoteArtifactId(
                  providerId: 'drive',
                  sourceId: 'source',
                  accountId: 'account',
                  providerFileId: id),
              displayName: 'Same name.chd',
              displayPath: 'Same name.chd',
              sizeBytes: bytes,
              canDownload: true));

  test('cached console sizes deduplicate exact files, never similar titles',
      () {
    final known = entry('a', bytes: 1024);
    final zero = entry('b', bytes: 0);
    final unknown = entry('c');
    final denied = LibraryEntry(
        filename: 'Denied.chd',
        displayName: 'Denied',
        cardTitle: 'Denied',
        url: '',
        systemSlug: 'psx',
        providerConfig: known.providerConfig,
        remoteArtifact: RemoteArtifact.fromJson({
          ...entry('d', bytes: 2048).remoteArtifact!.toJson(),
          'canDownload': false
        }));
    final other = entry('a', bytes: 1024, slug: 'ps2');
    final summaries = LibraryConsoleSummary.fromEntries(
        [known, known, zero, unknown, denied, other],
        isInstalled: (e) => e == known,
        favorites: {unknown.selectionKey},
        installation:
            InstalledFilesState(managedBytesBySystem: {'psx': 512}));
    final psx = summaries.firstWhere((s) => s.slug == 'psx');
    expect(psx.entries, 4);
    expect(psx.installed, 1);
    expect(psx.favorites, 1);
    expect(psx.downloadable, 3);
    expect(psx.sourceBytes, 3072);
    expect(psx.knownSourceSizes, 3);
    expect(psx.unknownSourceSizes, 1);
    expect(psx.managedBytes, 512);
    expect(summaries.firstWhere((s) => s.slug == 'ps2').managedBytes, isNull);
    expect(libraryStorageSize(1024), '1.0 KiB');
    expect(libraryStorageSize(0), '0 B');
  });

  testWidgets(
      'localized dashboard cards distinguish unknown from zero at large text',
      (tester) async {
    tester.view.physicalSize = const Size(640, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final locale in L.supportedLocales) {
      for (final known in [false, true]) {
        await tester.pumpWidget(MaterialApp(
            locale: locale,
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: Scaffold(
                    body: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                            width: 350,
                            child: LibraryConsoleCard(
                                summary: LibraryConsoleSummary(
                                    slug: 'ps2',
                                    entries: 9000,
                                    installed: 25,
                                    downloadable: 8900,
                                    favorites: 10,
                                    sourceBytes: 0,
                                    knownSourceSizes: known ? 1 : 0,
                                    unknownSourceSizes: known ? 0 : 1,
                                    managedBytes: known ? 0 : null),
                                selected: true,
                                onTap: () {})))))));
        await tester.pumpAndSettle();
        final l = L.of(tester.element(find.byType(LibraryConsoleCard)));
        expect(
            tester.widget<Text>(find.byKey(const ValueKey('source-size'))).data,
            known ? '0 B' : l.library_sizeUnknown);
        expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('managed-size')))
                .data,
            known ? '0 B' : l.library_sizeUnknown);
        expect(tester.takeException(), isNull,
            reason: '$locale / known=$known');
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
