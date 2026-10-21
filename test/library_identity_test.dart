import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/library_identity.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/services/library_platform_mapping.dart';

RemoteArtifactId artifactId({
  String provider = 'drive',
  String source = 'library',
  String? account = 'account-a',
  String file = 'file-a',
}) =>
    RemoteArtifactId(
      providerId: provider,
      sourceId: source,
      accountId: account,
      providerFileId: file,
    );

Map<String, dynamic> roundTrip(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

void main() {
  group('RemoteArtifact', () {
    test('rename, move, and version change preserve exact file identity', () {
      final original = RemoteArtifact(
        id: artifactId(),
        parentId: 'folder-a',
        displayPath: 'PSX/First.chd',
        displayName: 'First.chd',
        sizeBytes: 100,
        version: '1',
      );
      final refreshed = RemoteArtifact(
        id: artifactId(),
        parentId: 'folder-b',
        displayPath: 'PlayStation/Renamed.chd',
        displayName: 'Renamed.chd',
        sizeBytes: 120,
        version: '2',
      );

      expect(refreshed.id, original.id);
      expect(refreshed.id.key, original.id.key);
      expect(refreshed.version, isNot(original.version));
    });

    test('duplicate names stay distinct across files, accounts, and sources',
        () {
      final ids = {
        artifactId(),
        artifactId(file: 'file-b'),
        artifactId(account: 'account-b'),
        artifactId(source: 'second-library'),
        artifactId(provider: 'another-provider'),
        artifactId(account: null),
      };

      expect(ids, hasLength(6));
      expect(ids.map((id) => id.key).toSet(), hasLength(6));
      expect(
        artifactId(source: 'a:b', file: 'c').key,
        isNot(artifactId(source: 'a', file: 'b:c').key),
      );
    });

    test('provider checksums and unknown capability survive JSON unchanged',
        () {
      final artifact = RemoteArtifact(
        id: artifactId(),
        parentId: 'parent',
        displayName: 'Game.chd',
        displayPath: 'PSX/Game.chd',
        sizeBytes: 2147483648,
        modifiedAt: DateTime.utc(2026, 9, 8),
        version: '42',
        providerChecksums: {'md5': 'container-checksum'},
      );
      final restored = RemoteArtifact.fromJson(roundTrip(artifact.toJson()));

      expect(restored.id, artifact.id);
      expect(restored.toJson(), artifact.toJson());
      expect(restored.canDownload, isNull);
      expect(restored.providerChecksums, {'md5': 'container-checksum'});
    });

    test('identity rejects missing scope and preserves opaque ID characters',
        () {
      expect(() => artifactId(source: ''), throwsArgumentError);
      expect(() => artifactId(account: ' '), throwsArgumentError);
      expect(() => artifactId(file: ''), throwsArgumentError);
      final id = artifactId(source: 'Library:A', file: 'AbC/123');
      expect(RemoteArtifactId.fromJson(roundTrip(id.toJson())), id);
      expect(id, isNot(artifactId(source: 'library:a', file: 'abc/123')));
    });
  });

  group('GameIdentity and EditionIdentity', () {
    test('same-title games and a same-base hack retain assigned identities',
        () {
      final original = GameIdentity(
        id: 'game-base',
        platformId: 'psx',
        title: 'Example',
        providerIds: {'screenscraper': '100'},
      );
      final unrelated = GameIdentity(
        id: 'game-unrelated',
        platformId: 'psx',
        title: 'Example',
        providerIds: {'screenscraper': '200'},
      );
      final hack = GameIdentity(
        id: 'game-hack',
        platformId: 'psx',
        title: 'Example',
        baseGameId: original.id,
      );

      expect({original.id, unrelated.id, hack.id}, hasLength(3));
      expect(hack.providerIds, isEmpty);
      expect(hack.baseGameId, original.id);
      expect(hack.matchStatus, IdentityMatchStatus.unmatched);
    });

    test('regions and two discs group only through explicit game identity', () {
      final us = EditionIdentity(
        id: 'edition-us',
        gameId: 'game-base',
        releaseId: 'release-us',
        regions: ['US'],
        languages: ['en'],
        revision: '1.0',
        tags: {'Official'},
        members: [
          EditionMember(artifactId: artifactId(file: 'disc-1'), discNumber: 1),
          EditionMember(artifactId: artifactId(file: 'disc-2'), discNumber: 2),
        ],
      );
      final eu = EditionIdentity(
        id: 'edition-eu',
        gameId: 'game-base',
        releaseId: 'release-eu',
        regions: ['EU'],
        revision: '1.1',
      );

      expect(us.id, isNot(eu.id));
      expect(us.gameId, eu.gameId);
      expect(us.members.map((member) => member.discNumber), [1, 2]);
      expect(
          us.members.map((member) => member.artifactId).toSet(), hasLength(2));
      expect(EditionIdentity.fromJson(roundTrip(us.toJson())).toJson(),
          us.toJson());
      expect(EditionIdentity.fromJson(roundTrip(eu.toJson())).toJson(),
          eu.toJson());
    });

    test('translation, audio, uncensor and patch evidence stay independent',
        () {
      final translated = EditionIdentity(
        id: 'edition-translation-v1',
        gameId: 'game-base',
        patchId: 'translation-project:1.0',
        isTranslation: true,
        translatedLanguages: ['en'],
        tags: {'T-Eng', 'Undub', 'Uncensor'},
        evidence: [
          IdentityEvidence(
            source: 'manual',
            kind: 'patch',
            value: 'translation-project:1.0',
            confidence: 1,
          ),
        ],
        members: [
          EditionMember(
            artifactId: artifactId(),
            rawRomChecksums: {'sha1': 'verified-raw-rom-checksum'},
          ),
        ],
      );
      final officialEnglish = EditionIdentity(
        id: 'edition-official',
        gameId: 'game-base',
        languages: ['en'],
      );
      final secondPatch = EditionIdentity(
        id: 'edition-translation-v2',
        gameId: 'game-base',
        patchId: 'translation-project:2.0',
      );

      final restored = EditionIdentity.fromJson(roundTrip(translated.toJson()));
      expect(restored.toJson(), translated.toJson());
      expect(restored.tags, {'T-Eng', 'Undub', 'Uncensor'});
      expect(restored.tags, isNot(contains('Dub')));
      expect(restored.members.single.rawRomChecksums,
          {'sha1': 'verified-raw-rom-checksum'});
      expect(officialEnglish.isTranslation, isNull);
      expect(officialEnglish.tags, isEmpty);
      expect(secondPatch.id, isNot(translated.id));
    });

    test('known content-tag aliases canonicalize without inferring patch facts',
        () {
      final edition = EditionIdentity(
          id: 'aliases',
          gameId: 'game',
          languages: [
            'en'
          ],
          tags: {
            ' t-en ',
            'T-ENG',
            'Dubbed',
            ' UNDUBBED ',
            'uncensored',
            'HACK'
          });
      expect(edition.tags, {'T-Eng', 'Dub', 'Undub', 'Uncensor', 'Hack'});
      expect(edition.isTranslation, isNull);
      expect(edition.translatedLanguages, isEmpty);
      final restored = EditionIdentity.fromJson(roundTrip(edition.toJson()));
      expect(restored.tags, edition.tags);
      expect(() => restored.tags.add('official'), throwsUnsupportedError);
      final unknown = EditionIdentity(
          id: 'unknown',
          gameId: 'game',
          languages: ['en'],
          isTranslation: true,
          translatedLanguages: ['fr'],
          tags: {'Translation', 'English', 'PEGI 18', ' custom '});
      expect(unknown.tags, {'Translation', 'English', 'PEGI 18', ' custom '});
      expect(unknown.tags, isNot(contains('T-Eng')));
      expect(unknown.tags, isNot(contains('Uncensor')));
      expect(unknown.translatedLanguages, ['fr']);
    });

    test('ambiguous and manually corrected evidence persist without guessing',
        () {
      for (final status in [
        IdentityMatchStatus.ambiguous,
        IdentityMatchStatus.manuallyMatched,
      ]) {
        final game = GameIdentity(
          id: 'assigned-game-id',
          title: 'Unresolved title',
          matchStatus: status,
          providerIds: {'provider-a': 'candidate-7'},
          evidence: [
            IdentityEvidence(
              source: 'provider-a',
              kind: 'release',
              value: 'candidate-7',
              confidence: 0.6,
            ),
          ],
        );
        final restored = GameIdentity.fromJson(roundTrip(game.toJson()));
        expect(restored.toJson(), game.toJson());
        expect(restored.platformId, isNull);
        expect(restored.matchStatus, status);
      }
    });

    test('collections are immutable copies and invalid evidence is rejected',
        () {
      final ids = {'provider': '7'};
      final tags = {'Hack'};
      final game = GameIdentity(id: 'game', title: 'Title', providerIds: ids);
      final edition =
          EditionIdentity(id: 'edition', gameId: game.id, tags: tags);
      ids['provider'] = '8';
      tags.add('Dub');

      expect(game.providerIds, {'provider': '7'});
      expect(edition.tags, {'Hack'});
      expect(() => game.providerIds['new'] = '1', throwsUnsupportedError);
      expect(() => edition.tags.add('Dub'), throwsUnsupportedError);
      expect(
        () => IdentityEvidence(
            source: 'p', kind: 'id', value: '7', confidence: 2),
        throwsArgumentError,
      );
      expect(
        () => EditionMember(artifactId: artifactId(), discNumber: 0),
        throwsArgumentError,
      );
    });
  });

  group('LibraryPlatformMapping', () {
    test('explicit Nintendo, Sony, Sega and Microsoft aliases are supported',
        () {
      const fixtures = {
        ' Nintendo - GameCube ': 'gc',
        'Nintendo_3DS': 'n3ds',
        'Super Famicom': 'snes',
        'Sony - PlayStation': 'psx',
        'PS1': 'psx',
        'PS Vita': 'psvita',
        'Sega Genesis': 'megadrive',
        'Mega-CD': 'segacd',
        'Microsoft - MSX': 'msx',
        'MS-DOS': 'dos',
      };
      for (final fixture in fixtures.entries) {
        final result = LibraryPlatformMapping.resolve(fixture.key);
        expect(result.status, PlatformMappingStatus.supported,
            reason: fixture.key);
        expect(result.activePlatformId, fixture.value, reason: fixture.key);
      }
    });

    test('every catalog slug stays active without enabling absent consoles',
        () {
      for (final system in SystemModel.supportedSystems) {
        expect(LibraryPlatformMapping.resolve(system.id).activePlatformId,
            system.id);
      }
      for (final alias in [
        'Xbox',
        'Microsoft Xbox 360',
        'Sony PlayStation 5'
      ]) {
        final result = LibraryPlatformMapping.resolve(alias);
        expect(result.status, PlatformMappingStatus.unsupported);
        expect(result.requestedPlatformId, isNotNull);
        expect(result.activePlatformId, isNull);
      }
    });

    test('unknown and mixed folder names remain visible for assignment', () {
      for (final alias in ['Unknown Console', 'Nintendo', 'PSX and PS2', '']) {
        final result = LibraryPlatformMapping.resolve(alias);
        expect(result.folderName, alias);
        expect(result.status, PlatformMappingStatus.unknown);
        expect(result.activePlatformId, isNull);
      }
    });

    test('explicit corrections win and unsupported corrections never fall back',
        () {
      final corrected =
          LibraryPlatformMapping.resolve('PS1', overridePlatformId: 'ps2');
      expect(corrected.activePlatformId, 'ps2');
      expect(corrected.isOverride, isTrue);
      final invalid =
          LibraryPlatformMapping.resolve('PS1', overridePlatformId: 'xbox');
      expect(invalid.status, PlatformMappingStatus.unsupported);
      expect(invalid.activePlatformId, isNull);
      expect(invalid.requestedPlatformId, 'xbox');
      expect(invalid.isOverride, isTrue);
    });
  });
}
