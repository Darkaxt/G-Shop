import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('nes_catalogue',
    Path(__file__).parents[2] / 'scripts/prepare_nes_box_catalogue.py')
catalogue = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalogue)


class NesEditionReferences(unittest.TestCase):
    def test_donor_names_preserve_distinct_plus_and_negative_number_titles(self):
        for original,modified in [('Final Fantasy','Final Fantasy ++'),
                                  ('Super Mario Bros. 3','Super Mario Bros. 3 +'),
                                  ('Super Mario Bros. 2','Super Mario Bros. -2')]:
            with self.subTest(original=original):
                self.assertNotEqual(catalogue.title(original),catalogue.title(modified))

    def test_donor_region_preserves_printing_instead_of_defaulting_to_europe(self):
        cases = {
            'AirFortress_NES-Box_EUR(NES-AI-AUS)': 'au',
            'TeenageMutantHeroTurtles_NES-Box_ASI(KDS-GN)': 'asi',
            'KirbysAdventure_NES-Box_ASI(HVC-KI)': 'asi',
            'Fixture_NES-Box_EUR(NES-X-NOE)': 'eu',
            'Fixture_NES-Box_AME(NES-X-USA)': 'us',
            'Fixture_NES-Box_AME(NES-X-CAN)': 'ca',
            'Fixture_NES-Box_JPN(HVC-X)': 'jp',
            'Fixture_NES-Box_CUSTOM(en)': None,
            'Fixture_NES-Box_AME': None,
        }
        for folder, expected in cases.items():
            with self.subTest(folder=folder):
                self.assertEqual(catalogue.source_region_code(
                    {'editionFolder': 'Nintandbox.org\\NES - Famicom\\' + folder}), expected)

    def test_compound_regions_are_explicit_alternatives(self):
        asian_famicom={'editionFolder':'KirbysAdventure_NES-Box_ASI(HVC-KI)'}
        self.assertEqual(catalogue.regions(asian_famicom),['Asia'])
        self.assertTrue(catalogue.is_famicom_box(asian_famicom))
        self.assertFalse(catalogue.is_famicom_box({'editionFolder':'Fixture_NES-Box_AME(NES-X-USA)'}))
        self.assertEqual(catalogue.archive_regions('10-Yard Fight (USA, Europe).7z'),
            {'USA', 'Europe'})
        self.assertEqual(catalogue.archive_regions('Fixture (En,Fr) (Rev 1).7z'), set())

    def test_virtual_reissues_do_not_claim_retail_cartons(self):
        for tag in ['Virtual Console', '3DS Virtual Console', 'Switch',
                'Mega Man Legacy Collection', 'Retro-Bit Generations', 'FamicomBox',
                'Evercade', 'Capcom Town', 'Toaplan Arcade Garage', 'Animal Crossing',
                'Possible Proto', 'Sample', 'Sample) (1990-08-20',
                'Limited Run Games', 'Kiosk', 'Test Program', 'Star Fox - Assault']:
            self.assertFalse(catalogue.is_retail_reference(f'Fixture (USA) ({tag}).7z'))
        self.assertTrue(catalogue.is_retail_reference('Fixture (USA) (Rev 1).7z'))


if __name__ == '__main__':
    unittest.main()
