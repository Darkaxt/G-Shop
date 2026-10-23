import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
from prepare_metadata_crawl import prepare


class PreparationTest(unittest.TestCase):
    def sample(self, filename='Game.7z'):
        identity = {'providerId': 'drive', 'sourceId': 'source', 'accountId': 'owner',
                    'providerFileId': 'file'}
        row = {'archive': filename, 'editionId': 'edition',
               'edition': {'members': [{'artifactId': identity}], 'evidence': []},
               'lookup': {'request': {'gameId': 'game', 'editionId': 'edition',
                   'platformId': 'gba', 'title': 'Game', 'contentTags': [],
                   'refreshGeneration': 1, 'romIdentifier': {'stale': True}}}}
        return row, {'id': identity, 'displayName': filename}

    def run_prepare(self, row, artifact, paths):
        answer = subprocess.CompletedProcess([], 0, stdout='\n'.join(paths))
        with patch('prepare_metadata_crawl.subprocess.run', return_value=answer):
            return prepare({'gba': [row]}, [artifact], {'gba': Path('E:/fixtures')})

    def test_exact_member_and_filename_bind_without_reading_a_body(self):
        row, artifact = self.sample()
        manifest, gaps = self.run_prepare(row, artifact, ['E:/fixtures/Game.7z'])
        self.assertEqual(gaps, [])
        self.assertIsNone(manifest['items'][0]['request']['romIdentifier'])
        self.assertTrue(manifest['items'][0]['allowRawBinding'])

    def test_duplicate_names_are_reported_not_first_picked(self):
        row, artifact = self.sample()
        manifest, gaps = self.run_prepare(row, artifact,
            ['E:/fixtures/Game.7z', 'E:/fixtures/Other/Game.7z'])
        self.assertEqual(manifest['items'], [])
        self.assertEqual(gaps[0]['pathCandidates'], 2)

    def test_prototype_and_manual_unknown_do_not_acquire_official_assertions(self):
        row, artifact = self.sample('Game (Proto 1).7z')
        manifest, _ = self.run_prepare(row, artifact, ['E:/fixtures/Game (Proto 1).7z'])
        self.assertFalse(manifest['items'][0]['allowRawBinding'])
        row, artifact = self.sample()
        row['lookup']['request']['contentTags'] = ['unknown']
        row['edition']['evidence'] = [{'source': 'manual', 'kind': 'contentClassification'}]
        manifest, _ = self.run_prepare(row, artifact, ['E:/fixtures/Game.7z'])
        self.assertFalse(manifest['items'][0]['allowRawBinding'])


if __name__ == '__main__':
    unittest.main()
