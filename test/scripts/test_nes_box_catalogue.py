import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('nes_catalogue',
    Path(__file__).parents[2] / 'scripts/prepare_nes_box_catalogue.py')
catalogue = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalogue)


class NesEditionReferences(unittest.TestCase):
    def test_compound_regions_are_explicit_alternatives(self):
        self.assertEqual(catalogue.archive_regions('10-Yard Fight (USA, Europe).7z'),
            {'USA', 'Europe'})
        self.assertEqual(catalogue.archive_regions('Fixture (En,Fr) (Rev 1).7z'), set())

    def test_virtual_reissues_do_not_claim_retail_cartons(self):
        for tag in ['Virtual Console', '3DS Virtual Console', 'Switch',
                'Mega Man Legacy Collection', 'Retro-Bit Generations', 'FamicomBox']:
            self.assertFalse(catalogue.is_retail_reference(f'Fixture (USA) ({tag}).7z'))
        self.assertTrue(catalogue.is_retail_reference('Fixture (USA) (Rev 1).7z'))


if __name__ == '__main__':
    unittest.main()
