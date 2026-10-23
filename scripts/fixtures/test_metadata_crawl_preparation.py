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

    def test_recorded_relative_path_disambiguates_same_named_archives(self):
        row, artifact = self.sample()
        artifact['displayPath'] = 'fixtures/Original/Game.7z'
        manifest, gaps = self.run_prepare(row, artifact,
            ['E:/fixtures/Other/Game.7z', 'E:/fixtures/Original/Game.7z'])
        self.assertEqual(gaps, [])
        self.assertEqual(manifest['items'][0]['archive']['path'],
                         str(Path('E:/fixtures/Original/Game.7z').absolute()))

    def test_recorded_path_never_falls_back_to_a_different_copy(self):
        for location in ['fixtures/Missing/Game.7z', 'fixtures/../Game.7z']:
            with self.subTest(location=location):
                row, artifact = self.sample()
                artifact['displayPath'] = location
                manifest, gaps = self.run_prepare(row, artifact,
                    ['E:/fixtures/Other/Game.7z'])
                self.assertEqual(manifest['items'], [])
                self.assertEqual(gaps[0]['pathCandidates'], 0)

    def test_disk_system_subfolder_does_not_acquire_nes_cartridge_binding(self):
        row, artifact = self.sample()
        row['lookup']['request']['platformId'] = 'nes'
        artifact['displayPath'] = 'fixtures/Disk System/Game.7z'
        answer = subprocess.CompletedProcess([], 0,
            stdout='E:/fixtures/Disk System/Game.7z')
        with patch('prepare_metadata_crawl.subprocess.run', return_value=answer):
            manifest, gaps = prepare({'nes': [row]}, [artifact], {'nes': Path('E:/fixtures')})
        self.assertEqual(gaps, [])
        self.assertFalse(manifest['items'][0]['allowRawBinding'])
        self.assertEqual(manifest['items'][0]['rawBindingHoldReason'],
                         'disk-system-media-in-nes-folder')

    def test_prototype_and_manual_unknown_do_not_acquire_official_assertions(self):
        row, artifact = self.sample('Game (Proto 1).7z')
        manifest, _ = self.run_prepare(row, artifact, ['E:/fixtures/Game (Proto 1).7z'])
        self.assertFalse(manifest['items'][0]['allowRawBinding'])
        row, artifact = self.sample()
        row['lookup']['request']['contentTags'] = ['unknown']
        row['edition']['evidence'] = [{'source': 'manual', 'kind': 'contentClassification'}]
        manifest, _ = self.run_prepare(row, artifact, ['E:/fixtures/Game.7z'])
        self.assertFalse(manifest['items'][0]['allowRawBinding'])

    def test_bracketed_modifications_remain_in_census_without_retail_binding(self):
        for marker in ['[Color hack by Author v1.1]', '[Translation by Author]',
                       '(Graphics hack)', '[Proto 1]', '[T-Eng]']:
            with self.subTest(marker=marker):
                filename = 'Game (USA) ' + marker + '.7z'
                row, artifact = self.sample(filename)
                manifest, gaps = self.run_prepare(row, artifact, ['E:/fixtures/' + filename])
                self.assertEqual(gaps, [])
                self.assertEqual(len(manifest['items']), 1)
                self.assertFalse(manifest['items'][0]['allowRawBinding'])

    def test_game_title_words_do_not_act_as_modification_markers(self):
        filename = 'Hack Attack (USA) (Rev 1).7z'
        row, artifact = self.sample(filename)
        manifest, gaps = self.run_prepare(row, artifact, ['E:/fixtures/' + filename])
        self.assertEqual(gaps, [])
        self.assertTrue(manifest['items'][0]['allowRawBinding'])


if __name__ == '__main__':
    unittest.main()
