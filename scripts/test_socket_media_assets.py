import math
import struct
import unittest

import build_socket_media_assets as media


class MediaConversionTest(unittest.TestCase):
    def test_godot_binary_basis_rows_are_not_transposed(self):
        # resource_format_binary.cpp serializes Basis.rows, unlike Transform2D.
        source = [1, 0, 0, 0, 0, 1, 0, -1, 0, 3, 4, 5]
        self.assertEqual(media.point(source, [0, 1, 0]), [3, 4, 4])
        self.assertEqual(media.transform_normal(source, [0, 1, 0]), [0, 0, -1])
        translated = list(media.IDENTITY)
        translated[9:] = [1, 2, 3]
        composed = media.multiply(source, translated)
        self.assertEqual(media.point(composed, [2, 3, 4]),
                         media.point(source, media.point(translated, [2, 3, 4])))

    def test_nonuniform_basis_uses_inverse_transpose_normals(self):
        # A tangent and its normal must remain perpendicular after scale/shear.
        matrix = [2, 0, 0, 1, 3, 0, 0, 0, 4, 7, 8, 9]
        tangent = media.point(matrix, [1, -1, 0], False)
        normal = media.transform_normal(matrix, [1, 1, 0])
        self.assertAlmostEqual(sum(a * b for a, b in zip(tangent, normal)), 0)
        self.assertAlmostEqual(sum(v * v for v in normal), 1)

    def test_mesh_buffer_preserves_source_indices_uv_and_surface_order(self):
        surface = dict(positions=[[0, 0, 0], [1, 0, 0], [0, 1, 0]],
                       normals=[[0, 0, 1]] * 3,
                       uv=[[0, 0], [1, 0], [0, 1]], indices=[2, 1, 0])
        binary, ranges = media.pack_mesh([surface])
        self.assertEqual(ranges, [dict(vertexOffset=0, vertexCount=3,
                                      indexOffset=96, indexCount=3)])
        self.assertEqual(struct.unpack_from('<8f', binary, 32),
                         (1, 0, 0, 0, 0, 1, 1, 0))
        self.assertEqual(struct.unpack_from('<3I', binary, 96), (2, 1, 0))
        self.assertEqual(len(binary), 108)


if __name__ == '__main__':
    unittest.main()
