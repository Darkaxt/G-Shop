"""Geometry registration checks; no copyrighted artwork is required."""
import unittest
import copy
import json
import os
from pathlib import Path
import struct
from fit_gamewatch_controls import fit_transform, transform, node_matrix, register, PROFILES


class RegistrationTest(unittest.TestCase):
    def test_dkong2_cross_is_registered_as_one_control(self):
        old = (-.04444, .01809759, -.03444, .02809759)
        # Actual black-control bounds on the supplied 1767 x 2199 faceplate.
        target = (-.058 + .116*108/1767, .14435993*(1-1985/2199),
                  -.058 + .116*351/1767, .14435993*(1-1742/2199))
        matrix = fit_transform(old, target)
        for point, expected in [((old[0], old[1], .007), (target[0], target[1], .007)),
                                ((old[2], old[3], .007), (target[2], target[3], .007))]:
            for actual, value in zip(transform(matrix, point), expected):
                self.assertAlmostEqual(actual, value)

    def test_fit_preserves_depth_and_rotated_button_orientation(self):
        node = {'translation': [.01335, .02262, .0068],
                'rotation': [.70710678, 0, 0, .70710678]}
        old = node_matrix(node)
        fit = fit_transform((.01155, .02082, .01515, .02442),
                            (.017, .027, .020, .032))
        # A cylinder's local Y axis is its depth after this rotation. It must
        # not be stretched just because its screen-space height is corrected.
        a = transform(fit, transform(old, (0, -.00075, 0)))
        b = transform(fit, transform(old, (0, .00075, 0)))
        self.assertAlmostEqual(abs(a[2]-b[2]), .0015)
        self.assertAlmostEqual(a[0], b[0])
        self.assertAlmostEqual(a[1], b[1])

    @unittest.skipUnless(os.environ.get('RSHOP_GAMEWATCH_SOURCE'), 'Private source models not supplied')
    def test_actual_reconstructions_keep_artwork_hinges_and_depth(self):
        for name in ('donkey-kong-ii.glb', 'mario-bros.glb'):
            raw = (Path(os.environ['RSHOP_GAMEWATCH_SOURCE'])/name).read_bytes()
            import hashlib
            profile = PROFILES[hashlib.sha256(raw).hexdigest()]
            size = struct.unpack_from('<I', raw, 12)[0]
            gltf = json.loads(raw[20:20+size]); original = copy.deepcopy(gltf)
            receipt = register(gltf, raw[28+size:], profile)
            # Regression: the supplied controls really were offset/undersized.
            self.assertTrue(any(max(abs(a-b) for a,b in zip(r['before'],r['after'])) > .001
                                for r in receipt))
            self.assertEqual(gltf['animations'], original['animations'])
            self.assertEqual(gltf['images'], original['images'])
            self.assertEqual(gltf['meshes'], original['meshes'])
            for before, after in zip(original['materials'], gltf['materials']):
                if before['name'] == 'Menu buttons':
                    self.assertEqual(after['pbrMetallicRoughness']['baseColorFactor'], [.012,.015,.016,1])
                else:
                    self.assertEqual(before, after)
            changed = {n for r in receipt for n in r['nodes']}
            for before, after in zip(original['nodes'], gltf['nodes']):
                if before['name'] not in changed:
                    self.assertEqual(before, after)
                else:
                    for p in ((0,0,-.001),(0,0,.001)):
                        self.assertAlmostEqual(transform(node_matrix(before),p)[2],
                                               transform(node_matrix(after),p)[2])


if __name__ == '__main__':
    unittest.main()
