"""Full collection preparation must retain unrated and resource-missing editions."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import zipfile

from PIL import Image

sys.path.insert(0, str(Path(__file__).parents[1]))
import prepare_packaging_resources as packaging


class CollectionTest(unittest.TestCase):
    def collection_rows(self):
        rows = []
        for i in range(28):
            rows.append({'rank': None, 'score': None, 'title': f'Title {i}',
                'cache_row_id': i + 1, 'game': {'id': f'g{i}', 'platformId': 'nes'},
                'edition': {'id': f'e{i}', 'gameId': f'g{i}', 'regions': ['us'], 'tags': []},
                'metadata': None})
        rows[26]['edition']['tags'] = ['Hack']
        rows[27]['edition']['regions'] = []
        return rows

    def projection(self, root, *, wrong_metadata_owner=False):
        db = sqlite3.connect(':memory:')
        db.executescript('''
          CREATE TABLE library_query_editions(member,platform_id,group_key,
            source_order,rating_eligible,score,title,edition_id,game_id,cache_row_id);
          CREATE TABLE library_game_identities(game_id,record_json);
          CREATE TABLE library_editions(edition_id,record_json);
          CREATE TABLE library_metadata(edition_id,provider_id,record_json);
        ''')
        for index, (platform, tags) in enumerate([
                ('nes', []), ('nes', ['Hack']), ('gba', [])]):
            game = {'id': f'g{index}', 'platformId': platform, 'title': f'Title {index}'}
            edition = {'id': f'e{index}', 'gameId': game['id'], 'regions': [],
                       'tags': tags, 'members': [{'label': f'archive-{index}'}]}
            db.execute('INSERT INTO library_game_identities VALUES(?,?)',
                       (game['id'], json.dumps(game)))
            db.execute('INSERT INTO library_editions VALUES(?,?)',
                       (edition['id'], json.dumps(edition)))
            db.execute('INSERT INTO library_query_editions VALUES(?,?,?,?,?,?,?,?,?,?)',
                       (1, platform, game['id'], None, 0, None,
                        game['title'], edition['id'], game['id'], index + 1))
        if wrong_metadata_owner:
            db.execute('INSERT INTO library_metadata VALUES(?,?,?)',
                ('e0', 'screenscraper', json.dumps({'gameId': 'other', 'editionId': 'e0'})))
        db.commit()
        path = root / 'projection.gz'
        path.write_bytes(gzip.compress(db.serialize()))
        db.close()
        return path

    def test_all_editions_include_unrated_modified_and_missing_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            rows = packaging.collection_selection(self.projection(Path(folder)), 'nes')
        self.assertEqual([r['edition']['id'] for r in rows], ['e0', 'e1'])
        self.assertTrue(all(r['rank'] is None and r['score'] is None for r in rows))
        self.assertTrue(all(r['metadata'] is None for r in rows))
        self.assertEqual(rows[1]['edition']['tags'], ['Hack'])
        self.assertEqual(rows[0]['edition']['regions'], [])
        self.assertEqual(rows[1]['cache_row_id'], 2)

    def test_wrong_metadata_identity_cannot_be_reused(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'metadata identity'):
                packaging.collection_selection(
                    self.projection(Path(folder), wrong_metadata_owner=True), 'nes')

    def test_batches_obey_import_cap_without_dropping_references(self):
        body = b'image fixture'
        digest = hashlib.sha256(body).hexdigest()
        games = [{'gameId': f'g{i}', 'editionId': f'e{i}', 'identityKey': f'k{i}',
                  'resources': [{'type': 'box-2D', 'importReference': {'sha256': digest}}]}
                 for i in range(26)]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            receipts = packaging.write_packaging_batches(
                root / 'all.zip', {'version': 1, 'platform': 'nes', 'games': games},
                {digest: body, 'unused': b'not referenced'})
            self.assertEqual([r['games'] for r in receipts], [25, 1])
            editions = []
            for receipt in receipts:
                path = root / receipt['file']
                self.assertEqual(receipt['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())
                with zipfile.ZipFile(path) as archive:
                    editions.extend(g['editionId'] for g in json.loads(
                        archive.read('packaging.json'))['games'])
                    self.assertEqual(set(archive.namelist()),
                        {'packaging.json', f'images/{digest}.png'})
            self.assertEqual(editions, [f'e{i}' for i in range(26)])

    def test_no_empty_import_and_missing_body_is_rejected_before_writing(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.assertEqual(packaging.write_packaging_batches(root/'empty.zip',
                {'version': 1, 'platform': 'gba', 'games': []}, {}), [])
            with self.assertRaisesRegex(ValueError, 'Missing resource body'):
                packaging.write_packaging_batches(root/'missing.zip',
                    {'version': 1, 'platform': 'gba', 'games': [
                        {'resources': [{'importReference': {'sha256': 'missing'}}]}]}, {})
            self.assertEqual(list(root.iterdir()), [])

    def test_full_collection_prepares_all_batches_and_keeps_unresolved_members(self):
        rows = self.collection_rows()
        games = {str(i): f'Title {i}' for i in range(28)}
        images = {str(i): [{'Type': 'Box - Front', 'Region': 'United States',
                           'FileName': f'{i:08x}-0000-0000-0000-000000000000.png'}]
                  for i in range(28)}
        image = io.BytesIO()
        Image.new('RGB', (8, 12), 'navy').save(image, format='PNG')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            args = SimpleNamespace(selection='collection', system='nes',
                projection=root/'projection.gz', launchbox=root/'metadata.zip',
                panel_layouts=None, env=None, output=root/'all.zip')
            args.projection.write_bytes(b'projection fixture')
            with patch.object(packaging, 'collection_selection', return_value=rows), \
                    patch.object(packaging, 'launchbox_index', return_value=(games, images,
                        {packaging.normalized(title): {key} for key, title in games.items()})), \
                    patch.object(packaging, 'website_box', return_value=None), \
                    patch.object(packaging, 'fetch', return_value=image.getvalue()) as fetch:
                packaging.collect(args)
            census = json.loads(args.output.with_suffix('.selection.json').read_text())
            report = json.loads(args.output.with_suffix('.report.json').read_text())
            batches = json.loads(args.output.with_suffix('.batches.json').read_text())
            self.assertEqual(len(census['editions']), 28)
            self.assertEqual(len(report), 28)
            self.assertEqual([x['games'] for x in batches['packs']], [25, 1])
            self.assertEqual(batches['processed'], 28)
            self.assertTrue(batches['preparationFinished'])
            self.assertFalse(batches['publicationVerified'])
            self.assertEqual(fetch.call_count, 26)
            self.assertEqual([x.get('gap') for x in report[-2:]],
                ['modified-release-artwork-binding', 'edition-region-unresolved'])

    def test_inventory_does_not_start_acquisition(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            args = SimpleNamespace(selection='collection', inventory_only=True,
                system='nes', projection=root/'projection.gz', launchbox=root/'metadata.zip',
                output=root/'inventory.zip')
            args.projection.write_bytes(b'projection fixture')
            with patch.object(packaging, 'collection_selection', return_value=self.collection_rows()), \
                    patch.object(packaging, 'launchbox_index', side_effect=AssertionError('No acquisition')):
                packaging.collect(args)
            self.assertEqual(len(json.loads(args.output.with_suffix('.selection.json').read_text())['editions']), 28)
            self.assertFalse(args.output.exists())


if __name__ == '__main__':
    unittest.main()
