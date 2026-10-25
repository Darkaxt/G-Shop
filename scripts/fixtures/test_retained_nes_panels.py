"""Unchanged selected cartons must participate in the normal resource handoff."""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parents[1]))
from prepare_retained_nes_panels import prepare


def sha(body):
    return hashlib.sha256(body).hexdigest()


class RetainedNesPanelsTest(unittest.TestCase):
    def fixture(self, root):
        library = root / 'library'
        (library / 'reports').mkdir(parents=True)
        model = library / 'models' / 'nes-example'
        model.mkdir(parents=True)
        geometry = b'fixture source geometry identity'
        (model / 'model.glb').write_bytes(geometry)
        panels = {}
        for number, face in enumerate(('front', 'back', 'left', 'right', 'top', 'bottom')):
            file = model / (face + '.jpg')
            Image.new('RGB', (80, 120), (20 + number * 20, 90, 140)).save(file)
            panels[face] = {'file': str(file.relative_to(library)), 'cropSha256': sha(file.read_bytes()),
                            'sourceSha256': 'b' * 64, 'sourceCRC': '12345678', 'rect': [0, 0, 80, 120]}
        entry = {'id': 'nes-0123456789ab', 'platform': 'NES - Famicom', 'game': 'Example',
                 'editionFolder': r'Nintandbox.org\NES - Famicom\Example\Example_NES-Box_AME(NES-X-USA)',
                 'model': 'models/nes-example/model.glb', 'modelSha256': sha(geometry),
                 'status': 'verified-animated-edition', 'printedFaceProvenance': panels}
        (library / 'reports/catalogue-full.json').write_text(json.dumps({'editions': [entry]}))
        (library / 'reports/reproduction-configs.json').write_text(json.dumps([{'id': entry['id'], 'panels': panels}]))
        catalogue = {'schemaVersion': 1, 'system': 'nes', 'editions': [
            {'id': entry['id'], 'sourceEditionFolder': entry['editionFolder'], 'manifestSha256': 'a' * 64}],
            'bindings': {'Example (USA).7z': [entry['id']]}}
        runtime = {'models': {entry['id']: {'manifestSha256': 'a' * 64,
                   'sourceReference': {'sha256': sha(geometry)},
                   'textureFiles': {f'{k}.jpg': v['cropSha256'] for k, v in panels.items()}}}}
        return library, catalogue, runtime

    def test_unchanged_catalogue_carton_gets_all_roles_without_a_new_crawl(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            library, catalogue, runtime = self.fixture(root)
            result = prepare(catalogue, library, runtime, root / 'out')
            self.assertEqual(len(result['candidates']), 1)
            row = result['candidates'][0]
            self.assertEqual(row['filename'], 'Example (USA).7z')
            self.assertEqual(len(row['resources']), 9)
            by_role = {r['type']: r for r in row['resources']}
            self.assertEqual(by_role['box-2D']['importReference']['sha256'],
                             by_role['outer-box-front']['importReference']['sha256'])
            self.assertFalse(result['published'])
            self.assertNotIn('editionId', row)  # Ownership binds only to the fresh native census.

    def test_changed_native_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            library, catalogue, runtime = self.fixture(root)
            runtime['models']['nes-0123456789ab']['manifestSha256'] = 'c' * 64
            with self.assertRaisesRegex(ValueError, 'native manifest'):
                prepare(catalogue, library, runtime, root / 'out')

    def test_changed_original_panel_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            library, catalogue, runtime = self.fixture(root)
            (library / 'models/nes-example/front.jpg').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'panel digest'):
                prepare(catalogue, library, runtime, root / 'out')

    def test_unknown_source_model_is_a_visible_hold(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            library, catalogue, runtime = self.fixture(root)
            (library / 'reports/catalogue-full.json').write_text('{"editions":[]}')
            result = prepare(catalogue, library, runtime, root / 'out')
            self.assertEqual(result['candidates'], [])
            self.assertEqual(result['held'][0]['reason'], 'selected-model-not-in-retained-source-catalogue')

    def test_reviewed_native_roles_and_uv_rotation_do_not_change_the_model(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            library, catalogue, runtime = self.fixture(root)
            source = library / 'models/nes-example/back.jpg'
            review = {'nes-0123456789ab': {'manifestSha256': 'a' * 64,
                'reason': 'Actual native front uses the back scan, rotated clockwise.',
                'nativeAssembledEvidence': 'hash-bound-native-face-review.json',
                'faces': {'front': {'sourcePanel': 'back', 'clockwiseDegrees': 90,
                                    'sourceSha256': sha(source.read_bytes())}}}}
            result = prepare(catalogue, library, runtime, root / 'out', panel_review=review)
            row = result['candidates'][0]
            front = next(r for r in row['resources'] if r['type'] == 'box-2D')
            self.assertEqual(front['importReference']['rotationDegrees'], 90)
            self.assertEqual(front['importReference']['sourceSha256'], sha(source.read_bytes()))
            with Image.open(root / 'out/images' / (front['importReference']['sha256'] + '.png')) as image:
                self.assertEqual(image.size, (120, 80))
            self.assertEqual(row['manifestSha256'], 'a' * 64)
            review['nes-0123456789ab']['faces']['front']['sourceSha256'] = 'd' * 64
            with self.assertRaisesRegex(ValueError, 'Reviewed source panel digest'):
                prepare(catalogue, library, runtime, root / 'changed', panel_review=review)


if __name__ == '__main__':
    unittest.main()
