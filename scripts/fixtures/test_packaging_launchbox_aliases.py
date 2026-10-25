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
    def test_non_latin_modification_name_is_not_erased_from_the_title(self):
        self.assertNotEqual(packaging.normalized('Fire Emblem'),
            packaging.normalized('Fire Emblem: 天神陨落'))
        self.assertNotEqual(packaging.normalized('游戏一'),
            packaging.normalized('游戏二'))
        self.assertEqual(packaging.normalized('Pokémon Ruby Version'),
            packaging.normalized('Pokemon - Ruby Version'))

    def test_word_boundaries_distinguish_real_canonical_titles_from_collisions(self):
        cases = [
            ('Final Fantasy III', 'Final Fantasy III', 'Final Fantasy I•II'),
            ('Final Fantasy I, II', 'Final Fantasy I•II', 'Final Fantasy III'),
            ('Castle Quest', 'Castle Quest', 'Castlequest'),
            ('Fire Emblem', 'Fire Emblem', 'Fire Emblem: 天神陨落'),
        ]
        for target, correct, other in cases:
            with self.subTest(target=target), tempfile.TemporaryDirectory() as folder:
                source=Path(folder)/'Metadata.zip'
                xml=f'''<LaunchBox>
                  <GameAlternateName><DatabaseID>2</DatabaseID><AlternateName>{target}</AlternateName></GameAlternateName>
                  <GameAlternateName><DatabaseID>1</DatabaseID><AlternateName>{target}</AlternateName></GameAlternateName>
                  <Game><DatabaseID>1</DatabaseID><Name>{correct}</Name><Platform>Nintendo Entertainment System</Platform></Game>
                  <Game><DatabaseID>2</DatabaseID><Name>{other}</Name><Platform>Nintendo Entertainment System</Platform></Game>
                </LaunchBox>'''
                with zipfile.ZipFile(source,'w') as archive:archive.writestr('Metadata.xml',xml)
                games,_,names=packaging.launchbox_index(source,
                    {packaging.normalized(target)},'nes')
                result=packaging.launchbox_resolution(target,[],names,games)
                self.assertEqual(result['candidateIds'],['1','2'])
                self.assertEqual(result['selectedIds'],['1'])

    def test_spaced_compilation_join_matches_the_provider_slash_title(self):
        for left,right in [('2 Games in One!: Dr. Mario + Puzzle League','2 Games in One!: Dr. Mario / Puzzle League'),
                           ('Oshare Princess 2 + Doubutsu Kyaranabi Uranai','Oshare Princess 2 / Doubutsu Kyaranabi Uranai')]:
            self.assertEqual(packaging.normalized(left),packaging.normalized(right))

    def test_meaningful_plus_and_numeric_minus_do_not_collapse_distinct_titles(self):
        pairs=[('Final Fantasy','Final Fantasy ++'),
               ('Super Mario Bros. 3','Super Mario Bros. 3 +'),
               ('Super Mario Bros. 2','Super Mario Bros. -2')]
        for original,modified in pairs:
            with self.subTest(original=original), tempfile.TemporaryDirectory() as folder:
                source=Path(folder)/'Metadata.zip'
                xml=f'''<LaunchBox>
                  <Game><DatabaseID>1</DatabaseID><Name>{original}</Name><Platform>Nintendo Entertainment System</Platform></Game>
                  <Game><DatabaseID>2</DatabaseID><Name>{modified}</Name><Platform>Nintendo Entertainment System</Platform></Game>
                </LaunchBox>'''
                with zipfile.ZipFile(source,'w') as archive:archive.writestr('Metadata.xml',xml)
                games,_,names=packaging.launchbox_index(source,
                    {packaging.normalized(original),packaging.normalized(modified)},'nes')
                self.assertEqual(packaging.launchbox_resolution(original,[],names,games)['selectedIds'],['1'])
                self.assertEqual(packaging.launchbox_resolution(modified,[],names,games)['selectedIds'],['2'])

    def test_real_canonical_title_is_not_made_ambiguous_by_a_sequel_alias(self):
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)/'Metadata.zip'
            xml='''<LaunchBox>
              <GameAlternateName><DatabaseID>2</DatabaseID><AlternateName>Teenage Mutant Ninja Turtles</AlternateName></GameAlternateName>
              <Game><DatabaseID>1</DatabaseID><Name>Teenage Mutant Ninja Turtles</Name><Platform>Nintendo Entertainment System</Platform></Game>
              <Game><DatabaseID>2</DatabaseID><Name>Teenage Mutant Ninja Turtles II: The Arcade Game</Name><Platform>Nintendo Entertainment System</Platform></Game>
            </LaunchBox>'''
            with zipfile.ZipFile(source,'w') as archive:archive.writestr('Metadata.xml',xml)
            games,_,names=packaging.launchbox_index(source,
                {packaging.normalized('Teenage Mutant Ninja Turtles')},'nes')
        actual=packaging.launchbox_resolution('Teenage Mutant Ninja Turtles',[],names,games)
        self.assertEqual(actual['selectedIds'],['1'])
        self.assertEqual(actual['candidateIds'],['1','2'])

    def test_no_intro_articles_resolve_real_linked_images_without_dropping_articles(self):
        with tempfile.TemporaryDirectory() as folder:
            source=Path(folder)/'Metadata.zip'
            xml='''<LaunchBox>
              <Game><DatabaseID>1</DatabaseID><Name>The Polar Express</Name><Platform>Nintendo Game Boy Advance</Platform></Game>
              <Game><DatabaseID>2</DatabaseID><Name>The Incredibles: Rise of the Underminer</Name><Platform>Nintendo Game Boy Advance</Platform></Game>
              <Game><DatabaseID>3</DatabaseID><Name>Polar Express</Name><Platform>Nintendo Game Boy Advance</Platform></Game>
              <Game><DatabaseID>4</DatabaseID><Name>The Polar Express</Name><Platform>Nintendo Entertainment System</Platform></Game>
              <Game><DatabaseID>5</DatabaseID><Name>L'Aigle de Guerre</Name><Platform>Nintendo Game Boy Advance</Platform></Game>
              <GameImage><DatabaseID>1</DatabaseID><Type>Box - Front</Type><Region>Europe</Region><FileName>00000001-0000-0000-0000-000000000000.png</FileName></GameImage>
              <GameImage><DatabaseID>2</DatabaseID><Type>Box - Back</Type><Region>Europe</Region><FileName>00000002-0000-0000-0000-000000000000.png</FileName></GameImage>
            </LaunchBox>'''
            with zipfile.ZipFile(source,'w') as archive:archive.writestr('Metadata.xml',xml)
            games,images,names=packaging.launchbox_index(source,
                {packaging.normalized(t) for t in ['Polar Express, The','Incredibles, The - Rise of the Underminer',"Aigle de Guerre, L'"]},'gba')
        self.assertEqual(set(games),{'1','2','5'})
        self.assertEqual(set(images),{'1','2'})
        self.assertEqual(packaging.launchbox_resolution('Polar Express, The',[],names,games)['selectedIds'],['1'])
        self.assertEqual(packaging.launchbox_resolution('Incredibles, The - Rise of the Underminer',[],names,games)['selectedIds'],['2'])

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

    def test_exact_target_title_survives_another_regional_alias(self):
        names = {'familystadium87': {'163003'}, 'rbibaseball': {'1404'}}
        actual = packaging.launchbox_resolution('Family Stadium 87', ['RBI Baseball'], names,
            {'163003':'Family Stadium 87','1404':'RBI Baseball'})
        self.assertEqual(actual['selectedIds'], ['163003'])
        self.assertEqual(actual['candidateIds'], ['1404', '163003'])
        self.assertEqual(actual['method'], 'exact-canonical-title')

    def test_target_title_collision_is_not_resolved_by_a_convenient_alias(self):
        actual = packaging.launchbox_resolution('Shared Alias', ['Only One'],
            {'sharedalias': {'1', '2'}, 'onlyone': {'1'}},
            {'1':'Shared Alias','2':'Shared Alias'})
        self.assertEqual(actual['selectedIds'], ['1', '2'])
        actual = packaging.launchbox_resolution('Unknown', ['Shared Alias'],
            {'sharedalias': {'1', '2'}}, {'1':'One Game','2':'Another Game'})
        self.assertEqual(actual['selectedIds'], ['1', '2'])

    def test_collector_uses_alias_without_replacing_target_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            row = {'rank': None, 'cache_row_id': 1, 'title': 'Regional Compilation',
                'game': {'id': 'game', 'platformId': 'gba'},
                'edition': {'id': 'edition', 'regions': ['eu'], 'tags': []},
                'metadata': {'titles': [{'text': 'Different Compilation'}]}}
            args = SimpleNamespace(system='gba', selection='collection',
                projection=root/'projection.gz', launchbox=self.source(root),
                panel_layouts=None, env=None, output=root/'pack.zip')
            args.projection.write_bytes(b'projection fixture')
            output = io.BytesIO()
            artwork=Image.new('RGB', (8, 12), 'navy')
            artwork.paste('white',(2,2,6,5))
            artwork.save(output, format='PNG')
            with patch.object(packaging, 'collection_selection', return_value=[row]), \
                    patch.object(packaging, 'website_box', return_value=None), \
                    patch.object(packaging, 'fetch', return_value=output.getvalue()):
                packaging.collect(args)
            with zipfile.ZipFile(args.output) as archive:
                game = json.loads(archive.read('packaging.json'))['games'][0]
            self.assertEqual(game['editionId'], 'edition')
            self.assertEqual(game['gameId'], 'game')
            self.assertEqual(game['resources'][0]['importReference']['assetId'].split('/')[0], '1')
            report = json.loads(args.output.with_suffix('.report.json').read_text())
            self.assertEqual(report[0]['launchboxResolution']['candidateIds'], ['1', '2'])
            self.assertEqual(report[0]['launchboxResolution']['selectedIds'], ['1'])


if __name__ == '__main__':
    unittest.main()
