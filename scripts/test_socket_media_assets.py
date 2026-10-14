import math
import struct
import unittest
from unittest.mock import patch

import build_socket_media_assets as media


class MediaConversionTest(unittest.TestCase):
    def test_internal_material_gradient_is_bound_and_keeps_source_pixels(self):
        class Source:
            def reference(self, value, scene):
                return scene['resources'][value['index']], scene
        scene = {'member': 'fixture.scn', 'resources': [
            {'type': 'Gradient', 'properties': {
                'colors': {'values': [.59, .59, .59, 1]}, 'offsets': {'values': [0]}}},
            {'type': 'GradientTexture1D', 'properties': {
                'gradient': {'resource_reference': 2, 'index': 0}}},
            {'type': 'StandardMaterial3D', 'properties': {
                'albedo_texture': {'resource_reference': 2, 'index': 1}}}
        ]}
        pixels = []
        # Isolate filesystem IO only; image generation and material binding run.
        def save(image, *args, **kwargs): pixels.append((image.size, image.tobytes()))
        builder = media.MediaBuilder(Source(), '.', '')
        with patch('PIL.Image.Image.save', save):
            result = builder.material({'resource_reference': 2, 'index': 2}, scene)
        self.assertEqual(pixels, [((256, 1), bytes([150, 150, 150, 255]) * 256)])
        self.assertIn(result['textures']['albedo'], [t['file'] for t in builder.textures.values()])
        self.assertEqual(next(iter(builder.textures.values()))['sourceType'], 'GradientTexture1D')

    def test_noise_texture_normalizes_before_applying_source_ramp(self):
        class Source:
            def reference(self, value, scene):
                return scene['resources'][value['index']], scene
        scene = {'member': 'fixture.scn', 'resources': [
            {'type': 'FastNoiseLite', 'properties': {'noise_type': 2, 'frequency': .5}},
            {'type': 'Gradient', 'properties': {'colors': {'values': [0, 0, 1, 1, 1, 0, 0, 1]}}},
            {'type': 'NoiseTexture2D', 'properties': {'width': 4, 'height': 2,
                'noise': {'resource_reference': 2, 'index': 0},
                'color_ramp': {'resource_reference': 2, 'index': 1}}}
        ]}
        pixels = []
        def save(image, *args, **kwargs): pixels.append(image.tobytes())
        builder = media.MediaBuilder(Source(), '.', '')
        with patch('PIL.Image.Image.save', save):
            result = builder.internal_texture({'resource_reference': 2, 'index': 2}, scene)
        self.assertEqual((result['width'], result['height']), (4, 2))
        colors = list(zip(*[iter(pixels[0])] * 4))
        self.assertIn((255, 0, 0, 255), colors)
        self.assertIn((0, 0, 255, 255), colors)
        self.assertTrue(all(g == 0 and a == 255 for r, g, b, a in colors))

    def test_shader_defaults_include_scalar_and_vector_constants(self):
        class Source:
            files = {
                'shader': '#include "res://common"\nuniform float roughness = 0.15;\n'
                          'uniform vec4 base_color : source_color = vec4(0.6, 0.6, 0.6, 1.0);',
                'res://common': 'uniform float metallic_scale = 1.0;\n'
                          'uniform vec2 uv_offset = vec2(0.0);\n'
                          'uniform bool enable_sheen = false;'
            }
            def resolve(self, path): return path
            def plain(self, path): return self.files[path].encode()
        defaults = media.shader_defaults(Source(), 'shader')
        self.assertEqual(defaults['shader_parameter/metallic_scale'], 1)
        self.assertEqual(defaults['shader_parameter/roughness'], .15)
        self.assertEqual(defaults['shader_parameter/base_color']['values'], [.6, .6, .6, 1])
        self.assertEqual(defaults['shader_parameter/uv_offset']['values'], [0, 0])
        self.assertFalse(defaults['shader_parameter/enable_sheen'])

    def test_gradient_sampling_preserves_constant_and_linear_source_colors(self):
        constant = {'offsets': {'values': [1]},
                    'colors': {'values': [.23, .23, .23, 1]}}
        self.assertEqual(media.gradient_color(constant, .5), [.23, .23, .23, 1])
        linear = {'colors': {'values': [0, .2, .4, 1, 1, .8, .6, .5]}}
        self.assertEqual(media.gradient_color(linear, 0), [0, .2, .4, 1])
        self.assertEqual(media.gradient_color(linear, 1), [1, .8, .6, .5])
        for actual, expected in zip(media.gradient_color(linear, .5), [.5, .5, .5, .75]):
            self.assertAlmostEqual(actual, expected)

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
