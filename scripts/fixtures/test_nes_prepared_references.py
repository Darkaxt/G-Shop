"""Reviewed composites join the supplied catalogue without fuzzy ROM matches."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
import prepare_nes_box_catalogue as catalogue


class PreparedReferencesTest(unittest.TestCase):
    def fixture(self, root):
        id = 'nes-aaaaaaaaaaaa'
        folder = root/id
        folder.mkdir()
        file = folder/'model.json'
        file.write_text(json.dumps({'retailEditionId': id, 'canOpen': True,
            'resourceKind': 'box', 'system': 'nes'}))
        edition = {'id': id, 'label': 'Reviewed composite reference',
            'manifestSha256': hashlib.sha256(file.read_bytes()).hexdigest()}
        prepared = {'schemaVersion': 1, 'system': 'nes', 'editions': [edition],
            'bindings': {'Fixture (USA).7z': [id]}}
        current = {'schemaVersion': 1, 'system': 'nes', 'editions': [], 'bindings': {}}
        return current, prepared, file

    def test_reviewed_composite_binds_only_its_exact_retail_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            current, prepared, _ = self.fixture(root)
            catalogue.apply_prepared_references(current, prepared, root,
                {'Fixture (USA).7z', 'Fixture (USA) [Hack].7z'})
            self.assertEqual(current['bindings'], prepared['bindings'])
            self.assertEqual(current['editions'], prepared['editions'])
            self.assertNotIn('Fixture (Europe).7z', current['bindings'])

    def test_changed_manifest_and_unreviewed_or_nonretail_archive_are_rejected(self):
        for failure in ['changed', 'absent', 'hack', 'path']:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                current, prepared, file = self.fixture(root)
                if failure == 'changed': file.write_text('{}')
                elif failure == 'absent': prepared['bindings'] = {'Other (USA).7z': ['nes-aaaaaaaaaaaa']}
                elif failure == 'hack': prepared['bindings'] = {'Fixture (USA) [Hack].7z': ['nes-aaaaaaaaaaaa']}
                else: prepared['editions'][0]['id'] = '../model'
                with self.assertRaises(ValueError):
                    catalogue.apply_prepared_references(current, prepared, root,
                        {'Fixture (USA).7z', 'Fixture (USA) [Hack].7z'})
                self.assertEqual(current['editions'], [])
                self.assertEqual(current['bindings'], {})

    def test_prepared_primary_preserves_other_available_printing_choices(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            current, prepared, _ = self.fixture(root)
            other = {'id': 'nes-bbbbbbbbbbbb', 'label': 'Retained printing',
                'manifestSha256': 'b'*64}
            current['editions'].append(other)
            current['bindings']['Fixture (USA).7z'] = [other['id']]
            catalogue.apply_prepared_references(current, prepared, root,
                {'Fixture (USA).7z'})
            self.assertEqual(current['bindings']['Fixture (USA).7z'],
                ['nes-aaaaaaaaaaaa', 'nes-bbbbbbbbbbbb'])
            self.assertIn(other, current['editions'])


if __name__ == '__main__':
    unittest.main()
