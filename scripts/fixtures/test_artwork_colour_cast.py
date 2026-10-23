"""A collector correction estimates one cast, not a per-colour repaint."""
import sys
from pathlib import Path
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parents[1]))
from artwork_colour_cast import match_colour_cast


def palette_image():
    colors = [(30, 70, 150), (170, 150, 35), (190, 190, 190), (130, 30, 35),
              (25, 110, 65), (80, 120, 160), (65, 55, 40), (20, 25, 35),
              (120, 85, 75), (50, 140, 145), (160, 110, 40), (95, 105, 115)]
    pixels = np.zeros((96, 128, 4), dtype=np.uint8)
    for index, color in enumerate(colors):
        y, x = divmod(index, 4)
        pixels[y*32:(y+1)*32, x*32:(x+1)*32, :3] = color
    pixels[:, :, 3] = 255
    pixels[-4:, :, 3] = 90
    return Image.fromarray(pixels)


class ColourCastTest(unittest.TestCase):
    def test_channel_contrast_inversion_is_not_a_scan_colour_cast(self):
        source = palette_image()
        inverted = np.asarray(source).copy()
        inverted[:, :, :2] = 255 - inverted[:, :, :2]
        corrected, receipt = match_colour_cast(source, Image.fromarray(inverted))
        self.assertFalse(receipt['applied'], receipt)
        self.assertEqual(receipt['reason'], 'nonphysical-colour-transform')
        self.assertEqual(source.tobytes(), corrected.tobytes())

    def test_one_global_cast_is_reversed_for_all_colours_and_alpha_is_untouched(self):
        reference = palette_image()
        original = np.asarray(reference).copy()
        tinted = original.copy()
        tinted[:, :, :3] = np.round(np.clip(
            original[:, :, :3] * [1.04, .61, 1.08] + [6, 0, 8], 0, 255))
        source = Image.fromarray(tinted)
        # A translated logo/text patch is not evidence of the scan's colour cast.
        target = original.copy()
        target[8:20, 35:65, :3] = [250, 245, 240]
        corrected, receipt = match_colour_cast(source, Image.fromarray(target))
        self.assertTrue(receipt['applied'], receipt)
        result = np.asarray(corrected)
        for x, y in [(16+32*x, 16+32*y) for y in range(3) for x in range(4)]:
            self.assertLessEqual(np.max(np.abs(result[y, x, :3].astype(float) - original[y, x, :3])), 4)
        np.testing.assert_array_equal(result[:, :, 3], tinted[:, :, 3])
        np.testing.assert_array_equal(np.asarray(source), tinted)
        again, second = match_colour_cast(source, Image.fromarray(target))
        self.assertEqual(corrected.tobytes(), again.tobytes())
        self.assertEqual(receipt, second)

    def test_matching_art_needs_no_adjustment(self):
        source = palette_image()
        corrected, receipt = match_colour_cast(source, source.copy())
        self.assertFalse(receipt['applied'])
        self.assertEqual(receipt['reason'], 'already-matched')
        self.assertEqual(source.tobytes(), corrected.tobytes())

    def test_unrelated_art_is_not_given_a_fabricated_correction(self):
        random = np.random.default_rng(418)
        source = Image.fromarray(random.integers(0, 256, (96, 128, 3), dtype=np.uint8))
        reference = palette_image().convert('RGB')
        corrected, receipt = match_colour_cast(source, reference)
        self.assertFalse(receipt['applied'], receipt)
        self.assertEqual(source.convert('RGBA').tobytes(), corrected.tobytes())


if __name__ == '__main__':
    unittest.main()
