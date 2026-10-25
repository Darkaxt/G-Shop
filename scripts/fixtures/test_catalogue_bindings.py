"""A reviewed source/edition JSON binding must reach the real artwork pack."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

from PIL import Image

sys.path.insert(0, str(Path(__file__).parents[1]))
import prepare_packaging_resources as packaging
from prepare_catalogue_bindings import census_selection, corroborate_providers
import test_packaging_collection as collection_fixture


class CatalogueBindingsTest(unittest.TestCase):
    def test_targeted_binding_correction_keeps_the_full_census_and_acquires_only_selected_editions(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _, args, _, body = self.fixture(root)
            args.catalogue_bindings = None
            rows = collection_fixture.CollectionTest().collection_rows()
            args.edition_ids = [rows[0]['edition']['id'], rows[1]['edition']['id']]
            games = {str(i): r['title'] for i,r in enumerate(rows)}
            images = {str(i): [{'Type':'Box - Front','Region':'North America',
                'FileName':f'{i:08x}-0000-0000-0000-000000000000.png'}] for i in range(26)}
            names = {packaging.normalized(r['title']):{str(i)} for i,r in enumerate(rows)}
            with patch.object(packaging,'collection_selection',return_value=rows), \
                    patch.object(packaging,'launchbox_index',return_value=(games,images,names)), \
                    patch.object(packaging,'website_box',return_value=None), \
                    patch.object(packaging,'fetch',return_value=body) as fetch:
                packaging.collect(args)
            self.assertEqual(fetch.call_count,2)
            selection=json.loads(args.output.with_suffix('.selection.json').read_text())
            self.assertEqual(selection['coverageScope'],'selected-editions')
            self.assertEqual(selection['collectionSelected'],len(rows))
            self.assertEqual(selection['editionFilter'],sorted(args.edition_ids))
            progress=json.loads(args.output.with_suffix('.batches.json').read_text())
            self.assertEqual(progress['selected'],2)
            self.assertEqual(progress['collectionSelected'],len(rows))
            with zipfile.ZipFile(args.output) as archive:
                actual=json.loads(archive.read('packaging.json'))
            self.assertEqual({g['editionId'] for g in actual['games']},set(args.edition_ids))

    def test_targeted_binding_correction_rejects_unknown_and_duplicate_editions_before_fetch(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            row,args,_,_=self.fixture(root)
            for selection in [['unknown'],['edition','edition']]:
                args.edition_ids=selection
                with patch.object(packaging,'collection_selection',return_value=[row]), \
                        patch.object(packaging,'website_box',return_value=None), \
                        patch.object(packaging,'fetch',return_value=None) as fetch:
                    with self.assertRaisesRegex(ValueError,'edition selection'):
                        packaging.collect(args)
                    fetch.assert_not_called()

    def test_corroboration_uses_declared_alias_but_keeps_numeric_word_collisions(self):
        games = {'7': {'title': 'Canonical Name', 'aliases': ['Alternate Name']}}
        anchor = {'screenscraper': {'id': '8', 'title': 'Alternate Name', 'method': 'audited-alias'}}
        result = corroborate_providers(anchor, games, {'alternate name': {'7'}}, {})
        self.assertEqual(result['launchbox']['id'], '7')
        self.assertEqual(result['launchbox']['corroboratedBy']['id'], '8')
        self.assertNotIn('launchbox', anchor)
        self.assertEqual(corroborate_providers({}, games, {}, {}), {})
        anchor = {'launchbox': {'id': '7', 'title': 'Final Fantasy III', 'method': 'audited-canonical'}}
        result = corroborate_providers(anchor, games, {}, {'final fantasy i ii': {'8': 'Final Fantasy I•II'}})
        self.assertNotIn('screenscraper', result)
        result = corroborate_providers({'screenscraper': {'id': '8', 'title': 'Alternate Name'}},
            {**games, '9': {'title': 'Other Game'}}, {'alternate name': {'7', '9'}}, {})
        self.assertNotIn('launchbox', result)

    def fixture(self, root, *, namespace='nes'):
        identity = {'providerId': 'drive', 'sourceId': 'source', 'accountId': 'account', 'providerFileId': 'file'}
        game = {'id': 'game', 'platformId': 'nes', 'title': 'Regional Archive Title'}
        edition = {'id': 'edition', 'gameId': 'game', 'regions': ['us'], 'tags': [],
                   'members': [{'artifactId': identity, 'label': 'source.7z'}]}
        artifact = {'id': identity, 'displayPath': 'NES/source.7z', 'version': '1',
                    'sizeBytes': 42, 'providerChecksums': {'sha256': 'a' * 64}}
        records = [('snapshot', {'editionDirty': 0, 'cacheDirty': 0, 'readOnly': True}),
                   ('game', game), ('edition', edition), ('artifact', artifact)]
        census = root / 'census.ndjson'
        census.write_text(''.join(json.dumps({'kind': k, 'record': v}) + '\n' for k, v in records)
                          + json.dumps({'kind': 'end', 'rows': len(records)}) + '\n')
        index = root / 'Metadata.zip'
        platform = 'Nintendo Famicom Disk System' if namespace == 'fds' else 'Nintendo Entertainment System'
        xml = f'''<LaunchBox><Game><DatabaseID>7</DatabaseID><Name>Known Canonical Name</Name>
          <Platform>{platform}</Platform></Game><GameImage><DatabaseID>7</DatabaseID>
          <Type>Box - Front</Type><Region>North America</Region>
          <FileName>00000007-0000-0000-0000-000000000000.png</FileName></GameImage></LaunchBox>'''
        with zipfile.ZipFile(index, 'w') as archive:
            archive.writestr('Metadata.xml', xml)
        binding = {'platform': 'nes', 'gameId': 'game', 'editionId': 'edition',
            'identityKey': packaging.owner_key(game, edition), 'archive': 'source.7z',
            'artifact': artifact, 'cataloguePlatform': namespace,
            'providers': {'launchbox': {'id': '7', 'title': 'Known Canonical Name',
                                       'method': 'reviewed-manual'}}}
        document = {'version': 1, 'scope': 'artwork-candidates',
            'launchboxIndexSha256': packaging.file_sha256(index),
            'censusSha256': packaging.file_sha256(census), 'bindings': [binding], 'unresolved': []}
        mapping = root / 'bindings.json'
        mapping.write_text(json.dumps(document))
        row = {'rank': None, 'cache_row_id': 1, 'title': game['title'],
               'game': game, 'edition': edition, 'metadata': None}
        args = SimpleNamespace(system='nes', selection='collection', projection=root/'projection.gz',
            launchbox=index, panel_layouts=None, env=None, output=root/'pack.zip',
            catalogue_bindings=mapping, binding_census=census)
        args.projection.write_bytes(b'projection fixture')
        image = Image.new('RGB', (12, 16), 'navy')
        image.paste('white', (2, 2, 9, 7))
        encoded = io.BytesIO()
        image.save(encoded, format='PNG')
        return row, args, document, encoded.getvalue()

    def collect(self, row, args, body):
        with patch.object(packaging, 'collection_selection', return_value=[row]), \
                patch.object(packaging, 'website_box', return_value=None), \
                patch.object(packaging, 'fetch', return_value=body) as fetch:
            packaging.collect(args)
            return fetch

    def test_manual_binding_retrieves_the_actual_id_and_keeps_target_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, _, body = self.fixture(Path(folder))
            self.collect(row, args, body)
            self.assertTrue(args.output.exists(), 'The mapped artwork never entered a pack')
            with zipfile.ZipFile(args.output) as archive:
                game = json.loads(archive.read('packaging.json'))['games'][0]
            self.assertEqual((game['gameId'], game['editionId']), ('game', 'edition'))
            self.assertEqual(game['resources'][0]['importReference']['assetId'].split('/')[0], '7')

    def test_nested_fds_binding_uses_the_fds_index_without_reclassifying_the_rom(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, _, body = self.fixture(Path(folder), namespace='fds')
            with patch.object(packaging, 'website_box', return_value=None) as website, \
                    patch.object(packaging, 'collection_selection', return_value=[row]), \
                    patch.object(packaging, 'fetch', return_value=body):
                packaging.collect(args)
                self.assertEqual(website.call_args.args[1], 'fds')
            self.assertTrue(args.output.exists(), 'The nested FDS namespace was ignored')
            with zipfile.ZipFile(args.output) as archive:
                manifest = json.loads(archive.read('packaging.json'))
            self.assertEqual(manifest['platform'], 'nes')

    def test_bound_reference_carton_does_not_fabricate_an_unknown_edition_region(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, document, body = self.fixture(Path(folder))
            row['edition']['regions'] = []
            records = [json.loads(line) for line in args.binding_census.read_text().splitlines()]
            next(r for r in records if r['kind'] == 'edition')['record'] = row['edition']
            args.binding_census.write_text(''.join(json.dumps(r)+'\n' for r in records))
            document['censusSha256'] = packaging.file_sha256(args.binding_census)
            document['bindings'][0]['identityKey'] = packaging.owner_key(row['game'], row['edition'])
            args.catalogue_bindings.write_text(json.dumps(document))
            self.collect(row, args, body)
            self.assertTrue(args.output.exists(), 'Unknown region discarded a proven reference candidate')
            with zipfile.ZipFile(args.output) as archive:
                resource = json.loads(archive.read('packaging.json'))['games'][0]['resources'][0]
            self.assertEqual(resource['region'], 'wor')
            self.assertEqual(resource['importReference']['sourceRegion'], 'us')
            self.assertEqual(resource['importReference']['reconstruction'], 'composite')
            self.assertEqual(row['edition']['regions'], [])
            report = json.loads(args.output.with_suffix('.report.json').read_text())
            self.assertEqual(report[0]['regions'], [])
            self.assertEqual(report[0]['artworkScope'], 'reference-carton')

    def test_stale_edition_binding_is_rejected_before_any_acquisition(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, _, body = self.fixture(Path(folder))
            row['edition']['tags'] = ['Demo']
            with self.assertRaisesRegex(ValueError, 'binding.*identity|identity.*binding'):
                self.collect(row, args, body)

    def test_reference_face_without_a_provider_region_keeps_unknown_provenance(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, document, body = self.fixture(Path(folder))
            row['edition']['regions'] = []
            records = [json.loads(line) for line in args.binding_census.read_text().splitlines()]
            next(r for r in records if r['kind'] == 'edition')['record'] = row['edition']
            args.binding_census.write_text(''.join(json.dumps(r)+'\n' for r in records))
            document['censusSha256'] = packaging.file_sha256(args.binding_census)
            document['bindings'][0]['identityKey'] = packaging.owner_key(row['game'], row['edition'])
            with zipfile.ZipFile(args.launchbox) as archive:
                xml = archive.read('Metadata.xml').replace(b'<Region>North America</Region>', b'')
            with zipfile.ZipFile(args.launchbox, 'w') as archive:
                archive.writestr('Metadata.xml', xml)
            document['launchboxIndexSha256'] = packaging.file_sha256(args.launchbox)
            args.catalogue_bindings.write_text(json.dumps(document))
            self.collect(row, args, body)
            with zipfile.ZipFile(args.output) as archive:
                resource = json.loads(archive.read('packaging.json'))['games'][0]['resources'][0]
            self.assertIsNone(resource['importReference']['sourceRegion'])
            self.assertEqual(resource['region'], 'wor')

    def test_source_path_hack_marker_is_not_lost_when_metadata_has_no_tags(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, document, body = self.fixture(Path(folder))
            document['bindings'][0]['modifiedContext'] = True
            args.catalogue_bindings.write_text(json.dumps(document))
            requests = self.collect(row, args, body)
            self.assertFalse(args.output.exists())
            requests.assert_not_called()
            report = json.loads(args.output.with_suffix('.report.json').read_text())
            self.assertEqual(report[0]['gap'], 'modified-release-artwork-binding')

    def test_original_donor_also_supplies_gallery_faces_when_replacement_is_absent(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            row, args, _, body = self.fixture(root)
            source = root/'scan.png'
            source.write_bytes(body)
            args.panel_layouts = root/'panels.json'
            args.panel_layouts.write_text(json.dumps({'version': 1, 'layouts': [{
                'platform': 'nes', 'gameId': 'game', 'targetRegions': ['us'],
                'sourceRegion': 'eu', 'reconstruction': 'composite', 'languages': ['fr'],
                'panels': {face: {'file': 'scan.png', 'sha256': packaging.file_sha256(source),
                    'rect': [0, 0, 12, 16], 'sourceUrl': 'https://www.nintandbox.org/'}
                    for face in packaging.BOX_FACES}}]}))
            self.collect(row, args, None)
            with zipfile.ZipFile(args.output) as archive:
                resources = json.loads(archive.read('packaging.json'))['games'][0]['resources']
            roles = {r['type']: r for r in resources}
            self.assertIn('box-2D', roles)
            self.assertEqual(roles['box-2D']['importReference'], roles['outer-box-front']['importReference'])

    def test_changed_index_is_rejected_before_any_acquisition(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, _, body = self.fixture(Path(folder))
            with args.launchbox.open('ab') as stream:
                stream.write(b'changed')
            with self.assertRaisesRegex(ValueError, 'index'):
                self.collect(row, args, body)

    def test_missing_or_other_platform_id_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, document, body = self.fixture(Path(folder))
            document['bindings'][0]['providers']['launchbox']['id'] = '999'
            args.catalogue_bindings.write_text(json.dumps(document))
            with self.assertRaisesRegex(ValueError, 'platform|catalogue|index'):
                self.collect(row, args, body)

    def test_changed_source_artifact_cannot_be_reused(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, document, body = self.fixture(Path(folder))
            document['bindings'][0]['artifact']['version'] = '2'
            args.catalogue_bindings.write_text(json.dumps(document))
            with self.assertRaisesRegex(ValueError, 'binding.*source'):
                self.collect(row, args, body)

    def test_changed_provider_title_is_rejected_before_fetch(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, document, body = self.fixture(Path(folder))
            document['bindings'][0]['providers']['launchbox']['title'] = 'A different game'
            args.catalogue_bindings.write_text(json.dumps(document))
            with patch.object(packaging, 'fetch') as fetch:
                with self.assertRaisesRegex(ValueError, 'binding title'):
                    self.collect(row, args, body)
                fetch.assert_not_called()

    def test_ss_artwork_binding_does_not_replace_conflicting_rom_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, document, body = self.fixture(Path(folder))
            document['bindings'][0]['providers']['screenscraper'] = {
                'id': '7', 'title': 'Known Canonical Name', 'platformId': 3, 'method': 'reviewed-manual'}
            args.catalogue_bindings.write_text(json.dumps(document))
            row['metadata'] = {'providerGameId': '8', 'media': [
                {'type': 'box-2D', 'region': 'us', 'providerReference': {'providerPlatformId': 3}}]}
            calls = []
            def fetch(session, url, **kwargs):
                if 'screenscraper' in url:
                    calls.append(kwargs['params']['jeuid'])
                    return None
                return body
            with patch.object(packaging, 'collection_selection', return_value=[row]), \
                    patch.object(packaging, 'website_box', return_value=None), \
                    patch.object(packaging, 'fetch', side_effect=fetch):
                packaging.collect(args)
            self.assertTrue(calls)
            self.assertEqual(set(calls), {'8'})
            report = json.loads(args.output.with_suffix('.report.json').read_text())
            self.assertTrue(report[0]['catalogueBinding']['screenscraperIdentityConflict'])
            self.assertEqual(row['metadata']['providerGameId'], '8')

    def test_clean_census_reuses_actual_projection_members_and_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            row, args, _, _ = self.fixture(Path(folder))
            lines = [json.loads(line) for line in args.binding_census.read_text().splitlines()][:-1]
            lines.extend([
                {'kind': 'projection', 'record': {'edition_id': 'edition', 'game_id': 'game',
                    'platform_id': 'nes', 'title': row['title'], 'member': 1, 'cache_row_id': 1}},
                {'kind': 'projection', 'record': {'edition_id': 'old', 'member': 0, 'platform_id': 'nes'}},
                {'kind': 'metadata', 'record': {'editionId': 'edition', 'gameId': 'game',
                    'platformId': 'nes', 'providerId': 'screenscraper', 'providerGameId': '8'}}])
            lines.append({'kind': 'end', 'rows': len(lines)})
            args.binding_census.write_text(''.join(json.dumps(line)+'\n' for line in lines))
            selected = census_selection(args.binding_census, 'nes')
            self.assertEqual(len(selected), 1)
            self.assertEqual(selected[0]['edition'], row['edition'])
            self.assertEqual(selected[0]['metadata']['providerGameId'], '8')
            self.assertIsNone(selected[0]['rank'])

    def test_full_collection_resume_preserves_committed_packs_and_only_acquires_the_tail(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _, args, _, body = self.fixture(root)
            args.catalogue_bindings = None
            args.resume = False
            rows = collection_fixture.CollectionTest().collection_rows()
            games = {str(i): r['title'] for i,r in enumerate(rows)}
            images = {str(i): [{'Type': 'Box - Front', 'Region': 'North America',
                'FileName': f'{i:08x}-0000-0000-0000-000000000000.png'}] for i in range(26)}
            names = {packaging.normalized(r['title']): {str(i)} for i,r in enumerate(rows)}
            calls = 0
            def interrupted(session, url, **kwargs):
                nonlocal calls
                calls += 1
                if calls == 26:
                    raise RuntimeError('Reproduced transport interruption')
                return body
            with patch.object(packaging, 'collection_selection', return_value=rows), \
                    patch.object(packaging, 'website_box', return_value=None), \
                    patch.object(packaging, 'launchbox_index', return_value=(games, images, names)), \
                    patch.object(packaging, 'fetch', side_effect=interrupted):
                with self.assertRaisesRegex(RuntimeError, 'transport interruption'):
                    packaging.collect(args)
            progress = json.loads(args.output.with_suffix('.batches.json').read_text())
            self.assertEqual(progress['processed'], 25)
            committed = root/progress['packs'][0]['file']
            before = committed.read_bytes()
            args.resume = True
            with patch.object(packaging, 'collection_selection', return_value=rows), \
                    patch.object(packaging, 'website_box', return_value=None), \
                    patch.object(packaging, 'launchbox_index', return_value=(games, images, names)), \
                    patch.object(packaging, 'fetch', return_value=body) as fetch:
                packaging.collect(args)
                self.assertEqual(fetch.call_count, 1)
            self.assertEqual(committed.read_bytes(), before)
            progress = json.loads(args.output.with_suffix('.batches.json').read_text())
            self.assertEqual(progress['processed'], 28)
            self.assertTrue(progress['preparationFinished'])
            self.assertEqual(sum(p['games'] for p in progress['packs']), 26)

    def test_already_reviewed_preparation_is_verified_and_not_reacquired(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            row, args, _, body = self.fixture(root)
            ready = root/'reviewed'
            ready.mkdir()
            digest = hashlib.sha256(body).hexdigest()
            game = {'gameId': 'game', 'editionId': 'edition',
                'identityKey': packaging.owner_key(row['game'], row['edition']),
                'resources': [{'type': role, 'region': 'us',
                    'importReference': {'sha256': digest}} for role in
                    ['box-2D', 'box-2D-back', 'box-2D-side',
                     *('outer-box-'+f for f in packaging.BOX_FACES)]]}
            packs = packaging.write_packaging_batches(ready/'reviewed.zip',
                {'version': 1, 'platform': 'nes', 'games': [game]}, {digest: body})
            args.prepared_resources = ready/'preparation.json'
            args.prepared_resources.write_text(json.dumps({'games': [game], 'packs': packs}))
            requests = self.collect(row, args, body)
            self.assertFalse(args.output.exists())
            requests.assert_not_called()
            report = json.loads(args.output.with_suffix('.report.json').read_text())
            self.assertEqual(report[0]['disposition'], 'retained-reviewed-preparation-awaiting-delivery')
            self.assertFalse(report[0]['publicationVerified'])
            with (ready/'reviewed.zip').open('ab') as stream:
                stream.write(b'changed')
            with self.assertRaisesRegex(ValueError, 'preparation pack changed'):
                self.collect(row, args, body)


if __name__ == '__main__':
    unittest.main()
