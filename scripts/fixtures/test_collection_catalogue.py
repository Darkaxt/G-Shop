"""Filename mapping keeps exact names, platform ownership and source membership."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from prepare_collection_catalogue import (filename_title, inventory, lookup, match, registry,
    source_games, screenscraper_csv, regional_alias, load_title_aliases, resolve_source, title_key)


class CollectionCatalogueTest(unittest.TestCase):
    def test_regional_alias_resolves_same_name_without_merging_different_games(self):
        games={'1':{'title':'Castle','aliases':['Mickey Mouse'], 'aliasRegions':{'Mickey Mouse':['Japan']}},
               '2':{'title':'Castle 2','aliases':['Mickey Mouse'], 'aliasRegions':{'Mickey Mouse':['Europe']}}}
        finding=match('Mickey Mouse',lookup(games))
        self.assertEqual(finding['status'],'ambiguous')
        self.assertEqual(regional_alias({'title':'Mickey Mouse','filename':'Mickey Mouse (Japan).7z'},finding,games)['ids'],['1'])
        self.assertEqual(regional_alias({'title':'Mickey Mouse','filename':'Mickey Mouse (Europe).7z'},finding,games)['ids'],['2'])
        self.assertEqual(regional_alias({'title':'Mickey Mouse','filename':'Mickey Mouse (World).7z'},finding,games)['status'],'ambiguous')

    def test_reviewed_title_order_alias_is_scoped_and_rejects_foreign_ids(self):
        source={'system':'n3ds','family':'root','title':'Metal Gear Solid 3D - Snake Eater',
                'filename':'Metal Gear Solid 3D - Snake Eater (USA).zcci'}
        game={'id':'7','title':'Metal Gear Solid: Snake Eater 3D','aliases':[], 'platformName':'Nintendo 3DS'}
        index={'platforms':{'n3ds':{'7':game}},'screenscraper':{'n3ds':{}}}
        rule={'system':'n3ds','sourceTitle':source['title'],'reason':'Reviewed 3D marker relocation',
              'providers':{'launchbox':{'id':'7','title':game['title']}}}
        reviews={('n3ds',title_key(source['title'])):[rule]}
        self.assertEqual(resolve_source(source,index,{})[1],{})
        matches,providers=resolve_source(source,index,{},reviews)
        self.assertEqual(providers['launchbox']['id'],'7')
        self.assertEqual(matches['launchbox']['method'],'reviewed-scoped-alias')
        rule['providers']['launchbox']['id']='8'
        with self.assertRaisesRegex(ValueError,'foreign'):
            resolve_source(source,index,{},reviews)

    def test_reviewed_alias_retains_region_and_revision_selectors(self):
        from prepare_collection_catalogue import reviewed_alias
        rule={'system':'gbc','sourceTitle':'Chromanoids','regions':['World'],'tags':['v1.0'],
              'providers':{'screenscraper':{'id':'1','title':'Chromanoids'}},'reason':'Exact revision proof'}
        reviews={('gbc','chromanoids'):[rule]}
        source={'system':'gbc','title':'Chromanoids','filename':'Chromanoids (World) (v1.0).7z'}
        self.assertIs(reviewed_alias(source,reviews),rule)
        source['filename']='Chromanoids (World) (v1.1).7z'
        self.assertIsNone(reviewed_alias(source,reviews))

    def test_excluded_provider_is_not_restored_by_corroboration(self):
        source={'system':'gb','family':'root','title':'Mickey Mouse',
                'filename':'Mickey Mouse (Japan).7z'}
        game={'id':'1','title':'Correct Game','aliases':['Mickey Mouse']}
        index={'platforms':{'gb':{'1':game}},'screenscraper':{'gb':{
            '2':{'id':'2','title':'Correct Game','aliases':[]}}}}
        rule={'system':'gb','sourceTitle':'Mickey Mouse','regions':['Japan'],
              'reason':'Provider groups a different regional game',
              'providers':{'launchbox':{'id':'1','title':'Correct Game'}},
              'blockedProviders':['screenscraper']}
        self.assertIn('screenscraper',resolve_source(source,index,{})[1])
        matches,providers=resolve_source(source,index,{}, {('gb','mickey mouse'):[rule]})
        self.assertEqual(set(providers),{'launchbox'})
        self.assertEqual(matches['screenscraper']['status'],'reviewed-provider-conflict')

    def test_reviewed_alias_evidence_changes_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            from prepare_collection_catalogue import sha
            evidence=Path(folder)/'evidence.json'
            evidence.write_text('original')
            rules=Path(folder)/'rules.json'
            rules.write_text(json.dumps({'version':1,'evidence':[{'path':str(evidence),'sha256':sha(evidence)}],'rules':[]}))
            self.assertEqual(load_title_aliases(rules),{})
            evidence.write_text('changed')
            with self.assertRaisesRegex(ValueError,'evidence changed'):
                load_title_aliases(rules)

    def test_registry_covers_actual_supported_app_systems(self):
        systems = registry()
        self.assertEqual(systems['ps2']['screenscraperId'], 58)
        self.assertIn('Sega - Mega Drive', systems['megadrive']['folders'])
        self.assertIn('.rvz', systems['gc']['extensions'])

    def test_blank_provider_row_is_retained_without_discarding_the_platform_index(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'gameslist.csv'
            path.write_text('Game ID;Game Name\n8420;\n1;Known Game\n', encoding='utf-8')
            games, invalid = screenscraper_csv(path, 15)
            self.assertEqual(set(games), {'1'})
            self.assertEqual(invalid, [{'Game ID': '8420', 'Game Name': ''}])
            path.write_text('Game ID;Game Name\n1;Game\n1;Other\n', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Duplicate'):
                screenscraper_csv(path, 15)

    def test_title_keeps_subtitles_operators_and_non_latin(self):
        self.assertEqual(filename_title('Name (The Movie) (USA) (Rev 1).7z'), 'Name (The Movie)')
        self.assertEqual(filename_title('Final Fantasy ++ (Japan).zip'), 'Final Fantasy ++')
        self.assertEqual(filename_title('游戏 (China).7z'), '游戏')
        self.assertEqual(filename_title('0001 - Electroplankton (Japan).7z', 'nds'), 'Electroplankton')
        self.assertEqual(filename_title('1942 - Game (USA).zip', 'snes'), '1942 - Game')
        self.assertEqual(filename_title('0004000000030800 Mario Kart 7 (CTR-P-AMKE) (v2.4.0) (U).legit.zcci', 'n3ds'), 'Mario Kart 7')
        self.assertEqual(filename_title('0004008C0007AE00 New Super Mario Bros. 2 (CTR-M-ABEE-00) (v0.3.0) (W).piratelegit.zcia', 'n3ds'), 'New Super Mario Bros. 2')
        self.assertEqual(filename_title('000400000F700100 Xenoblade Chronicles 3D (KTR-P-CAFE) (v2.2.0) (U).piratelegit.zcci', 'n3ds'), 'Xenoblade Chronicles 3D')
        self.assertEqual(match('102 Dalmatiens a la Rescousse, Les', lookup({
            '1': {'title': 'Les 102 Dalmatiens a la Rescousse', 'aliases': []}}))['ids'], ['1'])

    def test_canonical_wins_over_another_games_bad_alias_and_collisions_are_held(self):
        names = lookup({'1': {'title': 'Quest', 'aliases': []},
            '2': {'title': 'Quest II', 'aliases': ['Quest']},
            '3': {'title': 'Different', 'aliases': ['Same']},
            '4': {'title': 'Other', 'aliases': ['Same']}})
        self.assertEqual(match('Quest', names)['ids'], ['1'])
        self.assertEqual(match('Same', names)['status'], 'ambiguous')
        self.assertEqual(match('Quest III', names)['status'], 'unmatched')

    def test_word_boundaries_and_numeric_operators_are_not_silently_folded(self):
        names = lookup({'1': {'title': 'Castlequest', 'aliases': []},
            '2': {'title': 'Game 2', 'aliases': []},
            '3': {'title': 'Final Fantasy', 'aliases': []}})
        self.assertEqual(match('Castle Quest', names)['status'], 'loose-candidate')
        self.assertEqual(match('Game -2', names)['status'], 'unmatched')
        self.assertEqual(match('Final Fantasy ++', names)['status'], 'unmatched')
        names = lookup({'1': {'title': "Dewy's Adventure", 'aliases': []}})
        self.assertEqual(match('Dewys Adventure', names)['ids'], ['1'])

    def test_minis_uses_its_provider_namespace_without_changing_app_system(self):
        games = {'1': {'platformName': 'Sony PSP', 'title': 'Game', 'aliases': []},
                 '2': {'platformName': 'Sony PSP Minis', 'title': 'Game', 'aliases': []}}
        scoped = source_games({'system': 'psp', 'family': 'Minis'}, 'launchbox', games)
        self.assertEqual(set(scoped), {'2'})
        self.assertEqual(match('Game', lookup(scoped))['ids'], ['2'])

    def test_filename_map_reaches_normal_collector_and_rejects_changed_source(self):
        import zipfile
        from prepare_catalogue_bindings import promote_filename_mapping
        from prepare_collection_catalogue import mapping, load_mapping, sha
        import test_catalogue_bindings as fixture

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            row, args, _, body = fixture.CatalogueBindingsTest().fixture(root)
            # A newly mapped SNES source, using the same actual owner/pack lane.
            row['game']['platformId'] = 'snes'
            records = [json.loads(line) for line in args.binding_census.read_text().splitlines()]
            for envelope in records:
                if envelope['kind'] == 'game':
                    envelope['record']['platformId'] = 'snes'
                if envelope['kind'] == 'artifact':
                    envelope['record']['displayPath'] = 'SNES/Known Canonical Name (USA).7z'
                    identity = envelope['record']['id']
            records.insert(-1, {'kind': 'cache', 'record': {'artifact_key': json.dumps([
                identity[k] for k in ['providerId', 'sourceId', 'accountId', 'providerFileId']])}})
            records[-1]['rows'] = len(records)-1
            args.binding_census.write_text(''.join(json.dumps(r)+'\n' for r in records))
            with zipfile.ZipFile(args.launchbox, 'w') as archive:
                archive.writestr('Metadata.xml', '''<LaunchBox><Game><DatabaseID>7</DatabaseID>
                    <Name>Known Canonical Name</Name><Platform>Super Nintendo Entertainment System</Platform></Game>
                    <GameImage><DatabaseID>7</DatabaseID><Type>Box - Front</Type><Region>North America</Region>
                    <FileName>00000007-0000-0000-0000-000000000000.png</FileName></GameImage></LaunchBox>''')
            source = {'system': 'snes', 'sourcePath': 'SNES/Known Canonical Name (USA).7z',
                'filename': 'Known Canonical Name (USA).7z', 'folder': 'SNES',
                'title': 'Known Canonical Name', 'family': 'root', 'modifiedContext': False}
            inventory_path, index_path, map_path = (root/name for name in ['inventory.json', 'index.json', 'map.json'])
            inventory_path.write_text(json.dumps({'version': 1, 'registrySha256': sha(Path(__file__).parents[1]/'catalogue_platforms.json'),
                'supportedSystems': registry(), 'systems': {'snes': {'sources': 1}}, 'rows': [source]}))
            game = {'id': '7', 'title': 'Known Canonical Name', 'aliases': [],
                    'platformName': 'Super Nintendo Entertainment System'}
            index_path.write_text(json.dumps({'inventorySha256': sha(inventory_path),
                'launchbox': {'path': str(args.launchbox), 'sha256': sha(args.launchbox)},
                'screenscraperSources': {}, 'platforms': {'snes': {'7': game}}, 'screenscraper': {'snes': {}}}))
            mapping(inventory_path, index_path, map_path)
            args.catalogue_bindings = root/'promoted.json'
            promoted = promote_filename_mapping(map_path, args.binding_census, args.launchbox, args.catalogue_bindings)
            self.assertEqual(len(promoted['bindings']), 1)
            self.assertEqual(promoted['unpromotedSources'], [])
            args.system = 'snes'
            fixture.CatalogueBindingsTest().collect(row, args, body)
            with zipfile.ZipFile(args.output) as archive:
                actual = json.loads(archive.read('packaging.json'))['games'][0]
            self.assertEqual(actual['gameId'], 'game')
            self.assertEqual(actual['resources'][0]['importReference']['assetId'].split('/')[0], '7')
            document = json.loads(map_path.read_text())
            document['rows'][0]['sourcePath'] = 'SNES/Other Game.7z'
            map_path.write_text(json.dumps(document))
            with self.assertRaisesRegex(ValueError, 'source changed'):
                load_mapping(map_path)

    def test_inventory_reads_names_without_opening_roms_and_retains_duplicate_leaf_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            roms = root/'roms'
            for name in ['Hacks/Game (USA).zip', 'Retail/Game (USA).zip', 'saves/ignored.zip']:
                path = roms/'Test'/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'do not read this payload')
            settings = {'test': {'folders': ['Test'], 'extensions': ['.bin']}}
            with patch('prepare_collection_catalogue.registry', return_value=settings), \
                    patch.object(Path, 'open', side_effect=AssertionError('ROM contents opened')):
                # Output/hash IO is deliberately separate from the mounted tree.
                with patch('prepare_collection_catalogue.write') as write, patch('prepare_collection_catalogue.sha', return_value='registry'):
                    result = inventory(roms, root/'inventory.json')
            self.assertEqual(len(result['rows']), 2)
            self.assertEqual(len({r['sourcePath'] for r in result['rows']}), 2)
            self.assertEqual(result['romBodiesRead'], 0)
            self.assertTrue(next(r for r in result['rows'] if r['family'] == 'Hacks')['modifiedContext'])
            write.assert_called_once()


if __name__ == '__main__':
    unittest.main()
