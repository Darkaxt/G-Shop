"""Provider-declared aliases retrieve candidates without weakening edition gates."""
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


class LaunchBoxAliasesTest(unittest.TestCase):
    def source(self, root):
        source = root / 'Metadata.zip'
        # Deliberately put aliases and images before games: XML section order
        # must not decide whether the provider's exact ID link is available.
        xml = '''<LaunchBox>
          <GameAlternateName><DatabaseID>1</DatabaseID><AlternateName>Regional Compilation</AlternateName></GameAlternateName>
          <GameAlternateName><DatabaseID>2</DatabaseID><AlternateName>Shared Alias</AlternateName></GameAlternateName>
          <GameAlternateName><DatabaseID>1</DatabaseID><AlternateName>Shared Alias</AlternateName></GameAlternateName>
          <GameAlternateName><DatabaseID>3</DatabaseID><AlternateName>Regional Compilation</AlternateName></GameAlternateName>
          <GameImage><DatabaseID>1</DatabaseID><Type>Box - Front</Type><Region>Europe</Region><FileName>00000001-0000-0000-0000-000000000000.png</FileName></GameImage>
          <Game><DatabaseID>1</DatabaseID><Name>Canonical Compilation</Name><Platform>Nintendo Game Boy Advance</Platform></Game>
          <Game><DatabaseID>2</DatabaseID><Name>Different Compilation</Name><Platform>Nintendo Game Boy Advance</Platform></Game>
          <Game><DatabaseID>3</DatabaseID><Name>Other Console</Name><Platform>Nintendo Entertainment System</Platform></Game>
        </LaunchBox>'''
        with zipfile.ZipFile(source, 'w') as archive:
            archive.writestr('Metadata.xml', xml)
        return source

    def test_exact_alias_uses_linked_game_images_and_preserves_canonical_name(self):
        with tempfile.TemporaryDirectory() as folder:
            games, images, names = packaging.launchbox_index(self.source(Path(folder)),
                {packaging.normalized('Regional Compilation')}, 'gba')
        self.assertEqual(games, {'1': 'Canonical Compilation'})
        self.assertEqual(set(images), {'1'})
        self.assertEqual(names, {'regionalcompilation': {'1'}})

    def test_same_platform_alias_collision_is_retained_as_ambiguous(self):
        with tempfile.TemporaryDirectory() as folder:
            games, _, names = packaging.launchbox_index(self.source(Path(folder)),
                {packaging.normalized('Shared Alias')}, 'gba')
        self.assertEqual(set(games), {'1', '2'})
        self.assertEqual(names['sharedalias'], {'1', '2'})

    def test_collector_uses_alias_without_replacing_target_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            row = {'rank': None, 'cache_row_id': 1, 'title': 'Regional Compilation',
                'game': {'id': 'game', 'platformId': 'gba'},
                'edition': {'id': 'edition', 'regions': ['eu'], 'tags': []}, 'metadata': None}
            args = SimpleNamespace(system='gba', selection='collection',
                projection=root/'projection.gz', launchbox=self.source(root),
                panel_layouts=None, env=None, output=root/'pack.zip')
            args.projection.write_bytes(b'projection fixture')
            output = io.BytesIO()
            Image.new('RGB', (8, 12), 'navy').save(output, format='PNG')
            with patch.object(packaging, 'collection_selection', return_value=[row]), \
                    patch.object(packaging, 'website_box', return_value=None), \
                    patch.object(packaging, 'fetch', return_value=output.getvalue()):
                packaging.collect(args)
            with zipfile.ZipFile(args.output) as archive:
                game = json.loads(archive.read('packaging.json'))['games'][0]
            self.assertEqual(game['editionId'], 'edition')
            self.assertEqual(game['gameId'], 'game')
            self.assertEqual(game['resources'][0]['importReference']['assetId'].split('/')[0], '1')


if __name__ == '__main__':
    unittest.main()
