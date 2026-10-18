"""Reviewed unfolded panels are data-driven, not per-title rendering code."""
import hashlib
import importlib.util
import io
import json
import sys
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).parents[1]))
from prepare_unfolded_boxes import locate_fold_panel, trim_closure, closure_has_print

spec = importlib.util.spec_from_file_location(
    'packaging', Path(__file__).parents[1] / 'prepare_packaging_resources.py')
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class PanelsTest(unittest.TestCase):
    def test_pale_print_at_fold_does_not_crop_the_body_to_one_dark_segment(self):
        image = Image.new('RGB', (600, 800), 'white')
        image.paste('navy', (0, 20, 80, 720))
        image.paste('navy', (80, 140, 560, 620))
        image.paste('white', (240, 140, 260, 148))
        image.paste('white', (400, 140, 420, 148))
        located = locate_fold_panel(image, 1)
        self.assertIsNotNone(located)
        self.assertEqual(located[0], [80, 140, 480, 480])

    def test_closure_retains_white_print_inside_the_full_flap(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'flap.png'
            image = Image.new('RGB', (200, 100), 'white')
            image.paste('navy', (0, 15, 200, 85))
            image.paste('white', (10, 35, 190, 65))
            image.save(path)
            self.assertEqual(trim_closure(path, [0, 0, 200, 100]), [0, 15, 200, 70])
            self.assertTrue(closure_has_print(path, [0, 0, 200, 100]))
            self.assertFalse(closure_has_print(path, [0, 0, 200, 10]))
            self.assertFalse(closure_has_print(path, [0, 90, 200, 30]))

    def test_language_and_tolerant_fit_preserve_content_without_gray_bands(self):
        self.assertLess(packaging.language_priority(['en']), packaging.language_priority(['en', 'es']))
        self.assertLess(packaging.language_priority(['en', 'es']), packaging.language_priority(['fr', 'de']))
        self.assertEqual(packaging.language_priority(['es']), 99)
        image = Image.new('RGB', (20, 10), 'red')
        image.paste('blue', (3, 3, 17, 7))
        fitted = packaging.fit_panel(image, 1)
        self.assertEqual(fitted.size, (20, 20))
        self.assertEqual(fitted.getpixel((10, 0)), (255, 0, 0, 255))
        self.assertEqual(fitted.getpixel((10, 10)), (0, 0, 255, 255))

    def test_complete_dump_precedes_website_launchbox_and_screenscraper(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            Image.new('RGB', (10, 10), 'red').save(root / 'scan.png')
            digest = hashlib.sha256((root / 'scan.png').read_bytes()).hexdigest()
            recipe = {'version': 1, 'layouts': [{'platform': 'gba', 'gameId': 'one',
                'targetRegions': ['us'], 'sourceRegion': 'eu', 'languages': ['en', 'de'],
                'reconstruction': 'regionalPackaging', 'panels': {role: {
                    'file': 'scan.png', 'sha256': digest, 'rect': [0, 0, 10, 10],
                    'sourceUrl': 'https://archive.org/details/nintandbox-2026'}
                    for role in packaging.BOX_FACES}}]}
            path = root / 'panels.json'
            path.write_text(json.dumps(recipe))
            row = {'rank': 1, 'title': 'Fixture', 'game': {'id': 'one'},
                'edition': {'id': 'edition', 'regions': ['us']},
                'metadata': {'providerGameId': '1', 'titles': [], 'media': []}}
            args = SimpleNamespace(system='gba', projection=root / 'projection.gz',
                launchbox=root / 'index.zip', env=None, panel_layouts=path,
                output=root / 'pack.zip')
            with patch.object(packaging, 'ranked_selection', return_value=[row]), \
                    patch.object(packaging, 'launchbox_index', return_value=({}, {})), \
                    patch.object(packaging, 'website_box', side_effect=AssertionError('Dump must win')), \
                    patch.object(packaging, 'fetch', side_effect=AssertionError('No provider request needed')):
                packaging.collect(args)

    def test_multiple_games_and_consoles_keep_six_distinct_reviewed_faces(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            scan = Image.new('RGB', (60, 10))
            colors = ['red', 'green', 'blue', 'yellow', 'purple', 'cyan']
            for index, color in enumerate(colors):
                scan.paste(color, (index * 10, 0, (index + 1) * 10, 10))
            scan.save(root / 'scan.png')
            digest = hashlib.sha256((root / 'scan.png').read_bytes()).hexdigest()
            recipes = {'version': 1, 'layouts': []}
            for platform in ['gba', 'gb']:
                for game in ['one', 'two']:
                    recipes['layouts'].append({
                        'platform': platform, 'gameId': game,
                        'targetRegions': ['us'], 'sourceRegion': 'eu',
                        'reconstruction': 'regionalPackaging',
                        'panels': {role: {'file': 'scan.png', 'sha256': digest,
                            'rect': [index * 10, 0, 10, 10], 'rotationDegrees': 0,
                            'sourceUrl': 'https://www.nintandbox.org/fixture'}
                            for index, role in enumerate(packaging.BOX_FACES)}})
            recipe_file = root / 'panels.json'
            recipe_file.write_text(json.dumps(recipes))
            for platform in ['gba', 'gb']:
                manifest = {'platform': platform, 'games': [
                    {'gameId': game, 'resources': [
                        {'type': 'box-2D', 'region': 'us'},
                        {'type': 'manual-page', 'memberIndex': 1, 'region': 'us'}]}
                    for game in ['one', 'two']]}
                bodies = {}
                packaging.apply_panel_layouts(manifest, bodies, recipe_file)
                for game in manifest['games']:
                    panels = [r for r in game['resources'] if r['type'].startswith('outer-box-')]
                    self.assertEqual(len(panels), 6)
                    self.assertEqual(len({p['importReference']['sha256'] for p in panels}), 6)
                    self.assertEqual(game['resources'][0]['type'], 'box-2D')
                    for panel in panels:
                        ref = panel['importReference']
                        self.assertEqual(ref['sourceRegion'], 'eu')
                        self.assertEqual(ref['reconstruction'], 'regionalPackaging')
                        self.assertEqual(ref['sourceSha256'], digest)
                        self.assertEqual(panel['region'], 'us')
                        self.assertEqual(len(ref['panel']), 4)
                # A changed reference source cannot silently reuse reviewed crops.
                (root / 'scan.png').write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'digest'):
                    packaging.apply_panel_layouts(manifest, {}, recipe_file)
                scan.save(root / 'scan.png')

    def test_invalid_crop_and_ambiguous_recipe_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            Image.new('RGB', (10, 10)).save(root / 'scan.png')
            recipe = {'platform': 'gba', 'gameId': 'one', 'targetRegions': ['us'],
                'sourceRegion': 'eu', 'reconstruction': 'regionalPackaging',
                'panels': {'front': {'file': 'scan.png',
                    'sha256': hashlib.sha256((root / 'scan.png').read_bytes()).hexdigest(),
                    'rect': [9, 0, 10, 10], 'rotationDegrees': 0,
                    'sourceUrl': 'https://www.nintandbox.org/fixture'}}}
            path = root / 'panels.json'
            manifest = {'platform': 'gba', 'games': [{'gameId': 'one',
                'resources': [{'type': 'box-2D', 'region': 'us'}]}]}
            path.write_text(json.dumps({'version': 1, 'layouts': [recipe]}))
            with self.assertRaisesRegex(ValueError, 'crop'):
                packaging.apply_panel_layouts(manifest, {}, path)
            path.write_text(json.dumps({'version': 1, 'layouts': [recipe, recipe]}))
            with self.assertRaisesRegex(ValueError, 'Ambiguous'):
                packaging.apply_panel_layouts(manifest, {}, path)


if __name__ == '__main__':
    unittest.main()
