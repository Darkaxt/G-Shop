"""Convert the supplied Socket 0.7 media to R-Shop's selected-model data.

Scene transforms, visible source triangles, UVs and material bindings are retained.
No simplification, substitute silhouettes or generated cartridge images are used.
Run against private staging until distribution provenance has been reconciled.
"""
import argparse
import hashlib
import io
import json
import math
import pathlib
import re
import struct

from socket_resources import APK_SHA256, SocketArchive, decode_script, scene_nodes, decompress_resource

IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]


def compressed_environment(data):
    """Keep the supplied HDR studio panorama's exact ASTC mip chain."""
    if len(data) < 52 or data[:4] != b'GST2':
        raise ValueError('Expected source environment texture')
    kind, width, height, extra_mips, fmt = struct.unpack_from('<IHHII', data, 36)
    if kind != 0 or fmt != 36 or not width or not height:
        raise ValueError('Expected source ASTC 4x4 HDR environment')
    if extra_mips != int(math.log2(max(width, height))):
        raise ValueError('Source environment mip chain is incomplete')
    levels, offset = [], 0
    for level in range(extra_mips + 1):
        w, h = max(1, width >> level), max(1, height >> level)
        length = ((w + 3) // 4) * ((h + 3) // 4) * 16
        levels.append({'offset': offset, 'length': length})
        offset += length
    blocks = data[52:]
    if len(blocks) != offset:
        raise ValueError('Source environment blocks are truncated or oversized')
    return {'width': width, 'height': height, 'format': 'astc4x4HDR', 'mips': levels}, blocks


def shader_defaults(archive, path, ancestors=()):
    """Read numeric source declarations, including the actual casing include.

    Only values are retained, never proprietary shader source in public recipes.
    """
    if path in ancestors:
        raise ValueError('Cyclic source shader include')
    code = archive.plain(archive.resolve(path)).decode().rstrip('\0')
    code = re.sub(r'/\*.*?\*/', '', code, flags=re.S)
    code = re.sub(r'^\s*//[^\n]*', '', code, flags=re.M)
    result = {}
    for include in re.findall(r'#include\s+"([^"]+)"', code):
        result.update(shader_defaults(archive, include, (*ancestors, path)))
    declarations = re.findall(
        r'\buniform\s+(bool|int|float|vec[234])\s+(\w+)\s*(?::[^;=]*)?=\s*([^;]+);', code)
    for kind, name, expression in declarations:
        expression = expression.strip()
        if kind == 'bool':
            if expression not in ('true', 'false'):
                raise ValueError('Nonconstant source shader boolean')
            value = expression == 'true'
        elif kind.startswith('vec'):
            match = re.fullmatch(kind + r'\(([^)]+)\)', expression)
            if not match:
                raise ValueError('Nonconstant source shader vector')
            numbers = [float(v.strip()) for v in match[1].split(',')]
            width = int(kind[-1])
            if len(numbers) == 1:
                numbers *= width
            if len(numbers) != width:
                raise ValueError('Invalid source shader vector')
            value = {'variant': {2: 10, 3: 12, 4: 50}[width], 'values': numbers}
        else:
            value = int(expression) if kind == 'int' else float(expression)
        result['shader_parameter/' + name] = value
    return result


def gradient_color(props, position):
    """Godot's source gradients here use linear RGB interpolation."""
    if props.get('interpolation_mode', 0) != 0 or props.get('interpolation_color_space', 0) != 0:
        raise ValueError('Unsupported source gradient interpolation')
    values = props.get('colors', {'values': [0, 0, 0, 1, 1, 1, 1, 1]})['values']
    colors = [values[i:i + 4] for i in range(0, len(values), 4)]
    offsets = props.get('offsets', {'values': [i / (len(colors) - 1) for i in range(len(colors))]
                                 if len(colors) > 1 else [0]})['values']
    points = sorted(zip(offsets, colors))
    if not points or len(offsets) != len(colors):
        raise ValueError('Invalid source gradient stops')
    if position <= points[0][0]:
        return points[0][1]
    for (left, a), (right, b) in zip(points, points[1:]):
        if position <= right:
            t = (position - left) / (right - left)
            return [x + (y - x) * t for x, y in zip(a, b)]
    return points[-1][1]


def point(matrix, value, translate=True):
    # Godot's binary resource format writes Basis.rows, not columns.
    return [sum(matrix[r * 3 + c] * value[c] for c in range(3)) +
            (matrix[9 + r] if translate else 0) for r in range(3)]


def multiply(a, b):
    return [sum(a[r * 3 + k] * b[k * 3 + c] for k in range(3))
            for r in range(3) for c in range(3)] + point(a, b[9:12])


def transform_normal(matrix, normal):
    columns = [[matrix[r * 3 + c] for r in range(3)] for c in range(3)]
    def cross(a, b):
        return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    cofactors = [cross(columns[1], columns[2]), cross(columns[2], columns[0]), cross(columns[0], columns[1])]
    determinant = sum(columns[0][i] * cofactors[0][i] for i in range(3))
    if abs(determinant) < 1e-15:
        raise ValueError('Singular source normal basis')
    transformed = [sum(cofactors[c][r] * normal[c] for c in range(3)) / determinant for r in range(3)]
    length = math.sqrt(sum(v * v for v in transformed))
    if not length:
        raise ValueError('Zero source normal')
    return [v / length for v in transformed]


def pack_mesh(surfaces):
    binary, ranges = bytearray(), []
    for surface in surfaces:
        count = len(surface['positions'])
        if len(surface['normals']) != count or len(surface['uv']) != count:
            raise ValueError('Required source normal/UV data missing')
        vertex_offset = len(binary)
        for position, normal, uv in zip(surface['positions'], surface['normals'], surface['uv']):
            binary.extend(struct.pack('<8f', *position, *normal, *uv))
        index_offset = len(binary)
        for index in surface['indices']:
            binary.extend(struct.pack('<I', index))
        ranges.append(dict(vertexOffset=vertex_offset, vertexCount=count,
                           indexOffset=index_offset, indexCount=len(surface['indices'])))
    return bytes(binary), ranges


def oct_normal(x, y):
    x, y = x * 2 - 1, y * 2 - 1
    z = 1 - abs(x) - abs(y)
    if z < 0:
        x, y = (1 - abs(y)) * (1 if x >= 0 else -1), (1 - abs(x)) * (1 if y >= 0 else -1)
    length = math.sqrt(x * x + y * y + z * z)
    return [x / length, y / length, z / length]


def surface_arrays(surface):
    count, fmt = surface['vertex_count'], surface['format']
    compressed = bool(fmt & 0x20000000)
    raw = surface['vertex_data']
    positions, normals, uv = [], [], []
    if compressed:
        bounds = surface['aabb']['values']
        positions = [[bounds[i] + q[i] / 65535 * bounds[i + 3] for i in range(3)]
                     for q in struct.iter_unpack('<4H', raw[:count * 8])]
    else:
        positions = [list(p) for p in struct.iter_unpack('<3f', raw[:count * 12])]
    if fmt & 2:
        stride = (len(raw) // count) - (8 if compressed else 12)
        start = count * (8 if compressed else 12)
        for i in range(count):
            x, y = struct.unpack_from('<2H', raw, start + i * stride)
            normal = oct_normal(x / 65535, y / 65535)
            if compressed:
                angle = struct.unpack_from('<H', raw, i * 8 + 6)[0] / 65535
                angle = abs(angle * 2 - 1) * math.pi
                x, y, z = normal
                # Godot's packed TBN axis/angle row 2.
                cosine, sine = math.cos(angle), math.sin(angle)
                normal = [(1 - cosine) * z * x - sine * y,
                          (1 - cosine) * z * y + sine * x,
                          cosine + (1 - cosine) * z * z]
            normals.append(normal)
    attrs = surface.get('attribute_data', b'')
    if fmt & 16:
        stride, offset = len(attrs) // count, 4 if fmt & 8 else 0
        for i in range(count):
            if compressed:
                values = struct.unpack_from('<2H', attrs, i * stride + offset)
                values = [v / 65535 for v in values]
                scale = surface['uv_scale']['values'][:2]
                if any(scale):
                    values = [(values[j] - 0.5) * scale[j] for j in range(2)]
            else:
                values = struct.unpack_from('<2f', attrs, i * stride + offset)
            uv.append(list(values))
    width = 2 if count <= 65536 else 4
    indices = [p[0] for p in struct.iter_unpack('<H' if width == 2 else '<I', surface['index_data'])]
    if len(indices) != surface['index_count'] or any(i >= count for i in indices):
        raise ValueError('Invalid source surface index buffer')
    return positions, normals, uv, indices


class MediaBuilder:
    def __init__(self, archive, output, tokenizer_header):
        self.archive, self.output, self.header = archive, pathlib.Path(output), tokenizer_header
        self.output.mkdir(parents=True, exist_ok=True)
        self.textures = {}
        self.recipes = []

    def environment(self):
        scene = self.archive.load('res://scenes/main.tscn')
        nodes = scene_nodes(scene)
        camera = next(n for n in nodes if n['type'] == 'Camera3D')['properties']
        light = next(n for n in nodes if n['type'] == 'DirectionalLight3D')['properties']
        environment = next(n for n in nodes if n['type'] == 'WorldEnvironment')['properties']
        env, context = self.archive.reference(environment['environment'], scene)
        sky, context = self.archive.reference(env['properties']['sky'], context)
        sky_material, context = self.archive.reference(sky['properties']['sky_material'], context)
        panorama = sky_material['properties']['panorama']
        path = context['external'][panorama['index']][1]
        member = self.archive.resolve(path)
        source = self.archive.plain(member)
        result, blocks = compressed_environment(source)
        basis = camera['transform']['values'][:9]
        direction = light['transform']['values'][:9]
        world = [direction[2], direction[5], direction[8]]
        # Camera is an orthonormal Basis; inverse is its transpose.
        result.update({
            'apkSha256': APK_SHA256, 'file': 'environment.astc',
            'source': path, 'sourceMember': member,
            'sourceSha256': hashlib.sha256(source).hexdigest(),
            'pixelsSha256': hashlib.sha256(blocks).hexdigest(),
            'sourceSceneSha256': hashlib.sha256(self.archive.plain(scene['member'])).hexdigest(),
            'lightDirection': [sum(basis[c * 3 + r] * world[c] for c in range(3)) for r in range(3)],
            'lightEnergy': light.get('light_energy', 1),
            'ambientEnergy': env['properties'].get('ambient_light_energy', 1),
            'reflectionEnergy': sky_material['properties'].get('energy_multiplier', 1),
            'exposure': env['properties'].get('tonemap_exposure', 1),
        })
        if (env['properties'].get('ambient_light_source') != 3 or
                env['properties'].get('reflected_light_source') != 2):
            raise ValueError('Unexpected source environment lighting contract')
        (self.output / result['file']).write_bytes(blocks)
        (self.output / 'environment.json').write_text(json.dumps(result, separators=(',', ':')), encoding='utf-8')
        return result

    def graph(self, path):
        scene = self.archive.load(path)
        bundled = scene['resources'][-1]['properties']['_bundled']
        nodes = scene_nodes(scene)
        graph, paths = {}, []
        if 'base_scene' in bundled:
            ref = bundled['variants'][bundled['base_scene']]
            base_path = scene['external'][ref['index']][1]
            graph = self.graph(base_path)
        for i, node in enumerate(nodes):
            if i == 0:
                path = ''
            else:
                parent = node['parent']
                if parent & (1 << 30):
                    parent_path = '/'.join(bundled['node_paths'][parent & 0x3fffffff]['node_path'])
                else:
                    parent_path = paths[parent]
                path = '/'.join(p for p in [parent_path, node['name']] if p)
            paths.append(path)
            instance = node['instance']
            if instance:
                imported = scene['external'][instance['index']][1]
                for child, props in self.graph(imported).items():
                    full = '/'.join(p for p in [path, child] if p)
                    graph[full] = dict(props)
            graph.setdefault(path, {}).update({k: (v, scene) for k, v in node['properties'].items()})
        return graph

    def texture(self, path):
        if path in self.textures:
            return self.textures[path]
        from PIL import Image
        import texture2ddecoder as decoder
        member = self.archive.resolve(path)
        data = self.archive.plain(member)
        if data[:4] != b'GST2':
            raise ValueError('Expected Godot 2D compressed texture')
        kind, width, height, mipmaps, fmt = struct.unpack_from('<IHHII', data, 36)
        payload = data[52:]
        if kind in (1, 2):
            size = struct.unpack_from('<I', payload)[0]
            image = Image.open(io.BytesIO(payload[4:4 + size])).convert('RGBA')
        elif kind == 0:
            functions = {25: decoder.decode_etc1, 26: decoder.decode_eacr,
                         27: decoder.decode_eacr_signed, 28: decoder.decode_eacrg,
                         29: decoder.decode_eacrg_signed, 30: decoder.decode_etc2,
                         31: decoder.decode_etc2a8, 32: decoder.decode_etc2a1,
                         33: decoder.decode_etc2a8, 17: decoder.decode_bc1,
                         19: decoder.decode_bc3, 22: decoder.decode_bc7}
            if fmt in functions:
                raw = functions[fmt](payload, width, height)
                image = Image.frombytes('RGBA', (width, height), raw, 'raw', 'BGRA')
            elif fmt in (0, 2, 4, 5):
                mode, channels = {0: ('L', 1), 2: ('L', 1), 4: ('RGB', 3), 5: ('RGBA', 4)}[fmt]
                image = Image.frombytes(mode, (width, height), payload[:width * height * channels]).convert('RGBA')
            else:
                raise ValueError(f'Unsupported source texture format {fmt}: {path}')
        else:
            raise ValueError(f'Unsupported texture container {kind}')
        filename = hashlib.sha256(data).hexdigest() + '.png'
        image.save(self.output / filename)
        result = {'file': filename, 'source': path, 'sourceMember': member,
                  'sourceSha256': hashlib.sha256(data).hexdigest(),
                  'width': width, 'height': height, 'format': fmt}
        self.textures[path] = result
        return result

    def source_tree(self, value, scene):
        if isinstance(value, dict) and 'resource_reference' in value:
            resource, context = self.archive.reference(value, scene)
            return {'type': resource['type'],
                    'properties': self.source_tree(resource['properties'], context)}
        if isinstance(value, dict):
            return {k: self.source_tree(v, scene) for k, v in value.items()}
        if isinstance(value, list):
            return [self.source_tree(v, scene) for v in value]
        return value

    def internal_texture(self, reference, scene):
        from PIL import Image
        tree = self.source_tree(reference, scene)
        source = json.dumps(tree, sort_keys=True, separators=(',', ':')).encode()
        digest = hashlib.sha256(source).hexdigest()
        identity = 'resource:' + digest
        if identity in self.textures:
            return self.textures[identity]
        props = tree['properties']
        if tree['type'] == 'GradientTexture1D':
            width, height = props.get('width', 256), 1
            if props.get('use_hdr'):
                raise ValueError('HDR source gradient needs a float texture')
            gradient = props['gradient']['properties']
            colors = [gradient_color(gradient, i / max(width - 1, 1)) for i in range(width)]
        elif tree['type'] == 'NoiseTexture2D':
            # Actual SNES PAL resource: nonseamless 2D FastNoiseLite + RGB ramp.
            # Godot normalizes the noise into L8 before applying that ramp.
            import numpy as np
            from pyfastnoiselite.pyfastnoiselite import (FastNoiseLite, NoiseType,
                FractalType, CellularDistanceFunction, CellularReturnType)
            if any(props.get(k) for k in ('seamless', 'as_normal_map', 'in_3d_space')):
                raise ValueError('Unsupported source noise texture mode')
            noise = props['noise']
            if noise['type'] != 'FastNoiseLite' or noise['properties'].get('domain_warp_enabled'):
                raise ValueError('Unsupported source noise generator')
            settings = noise['properties']
            generator = FastNoiseLite(seed=settings.get('seed', 0))
            generator.noise_type = NoiseType(settings.get('noise_type', 1))
            generator.frequency = settings.get('frequency', .01)
            generator.fractal_type = FractalType(settings.get('fractal_type', 1))
            generator.fractal_octaves = settings.get('fractal_octaves', 5)
            generator.fractal_lacunarity = settings.get('fractal_lacunarity', 2)
            generator.fractal_gain = settings.get('fractal_gain', .5)
            generator.fractal_weighted_strength = settings.get('fractal_weighted_strength', 0)
            generator.fractal_ping_pong_strength = settings.get('fractal_ping_pong_strength', 2)
            generator.cellular_distance_function = CellularDistanceFunction(settings.get('cellular_distance_function', 0))
            generator.cellular_return_type = CellularReturnType(settings.get('cellular_return_type', 1))
            generator.cellular_jitter = settings.get('cellular_jitter', 1)
            width, height = props.get('width', 512), props.get('height', 512)
            y, x = np.indices((height, width), dtype=np.float32)
            offset = settings.get('offset', {'values': [0, 0, 0]})['values']
            values = generator.gen_from_coords(np.stack((x.ravel() + offset[0], y.ravel() + offset[1])))
            if props.get('normalize', True):
                low, high = values.min(), values.max()
                gray = np.zeros_like(values) if low == high else (values - low) / (high - low) * 255
            else:
                gray = values * 127.5 + 127.5
            gray = np.clip(gray, 0, 255).astype(np.uint8)
            if props.get('invert'):
                gray = 255 - gray
            gradient = props.get('color_ramp', {}).get('properties', {})
            colors = [gradient_color(gradient, int(v) / 255) for v in gray]
        else:
            raise ValueError('Unsupported internal source texture: ' + tree['type'])
        pixels = bytes(max(0, min(255, int(v * 255))) for color in colors for v in color)
        filename = digest + '.png'
        Image.frombytes('RGBA', (width, height), pixels).save(self.output / filename)
        result = {'file': filename, 'source': identity, 'sourceMember': scene['member'],
                  'sourceSha256': digest, 'sourceType': tree['type'], 'sourceTree': tree,
                  'width': width, 'height': height, 'format': 'source-procedural-rgba8'}
        self.textures[identity] = result
        return result

    def material(self, reference, scene):
        if reference is None:
            return {'color': [0.7, 0.7, 0.7, 1]}
        item, context = self.archive.reference(reference, scene)
        props = dict(item['properties'])
        shader = props.get('shader')
        shader_path = context['external'][shader['index']][1] if shader and shader['resource_reference'] == 3 else None
        if shader_path:
            defaults = shader_defaults(self.archive, shader_path)
            defaults.update({k: v for k, v in props.items() if v is not None})
            props = defaults
        color = (props.get('albedo_color') or props.get('shader_parameter/tint_color') or
                 props.get('shader_parameter/base_color') or {'values': [1, 1, 1, 1]})['values']
        result = {'color': color, 'sourceType': item['type'], 'sourceProperties': props}
        for role in ['albedo', 'roughness', 'metallic', 'normal', 'ao']:
            for key in [role + '_texture', 'shader_parameter/' + role + '_texture']:
                value = props.get(key)
                if value:
                    texture = (self.texture(context['external'][value['index']][1])
                               if value['resource_reference'] == 3 else self.internal_texture(value, context))
                    result.setdefault('textures', {})[role] = texture['file']
                    break
        if shader_path:
            result['shaderSource'] = shader_path
        return result

    def build(self, name, scene_path):
        graph = self.graph(scene_path)
        root = graph['']
        if name == 'vita':
            # The platform references a missing cart_vita scene. Preserve the
            # actual imported label mesh and existing Vita script, not a made-up
            # shell. The shared Cartridge scene's -90-degree rest basis is the
            # only reconstructed selectable-scene property.
            cover = 'Sketchfab_model/PS Vita cart_STL_cleaner/Object_2_001'
            script_path = 'res://scripts/cartridge_vita.gd'
            root['transform'] = ({'values': [1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 0, 0]}, None)
        else:
            cover = '/'.join(root['cover_mesh'][0]['node_path'])
            script_value, script_scene = root['script']
            script_path = script_scene['external'][script_value['index']][1]
        script_member = self.archive.resolve(script_path)
        decoded = decode_script(self.archive.plain(script_member), self.header)
        getter = next(v for v in decoded.values() if 'RETURN cover_mesh PERIOD get_surface_override_material' in v)
        label_surface = int(re.search(r'PARENTHESIS_OPEN (\d+)', getter).group(1))
        casing = {('/'.join(v['node_path'])) for v in root.get('casing_meshs', ([], None))[0]}
        world_cache = {}

        def world(path):
            if path not in world_cache:
                transform = graph[path].get('transform', ({'values': IDENTITY}, None))[0]['values']
                parent = path.rpartition('/')[0]
                world_cache[path] = multiply(world(parent), transform) if path else transform
            return world_cache[path]

        surfaces = []
        for path, node in graph.items():
            if 'mesh' not in node or node.get('visible', (1, None))[0] == 0:
                continue
            # A hidden parent hides all its mesh children as in the source scene.
            ancestors = [p for p in graph if p and path.startswith(p + '/')]
            if any(graph[p].get('visible', (1, None))[0] == 0 for p in ancestors):
                continue
            ref, scene = node['mesh']
            mesh, mesh_scene = self.archive.reference(ref, scene)
            for index, surface in enumerate(mesh['properties']['_surfaces']):
                if surface['primitive'] != 3:
                    raise ValueError('Expected source triangles')
                positions, normals, uv, indices = surface_arrays(surface)
                matrix = world(path)
                positions = [point(matrix, p) for p in positions]
                positions = [[p[0], -p[1], p[2]] for p in positions]
                normals = [transform_normal(matrix, n) for n in normals]
                normals = [[n[0], -n[1], n[2]] for n in normals]
                is_label = path == cover and index == label_surface
                uv_source = 'source'
                if not uv and name == 'vita':
                    if is_label:
                        # The supplied Vita import is an untextured STL-derived
                        # mesh. Its actual label surface is planar but has no UV
                        # channel. Project only that existing surface, retaining
                        # every original vertex/index and recording the gap.
                        lo = [min(p[i] for p in positions) for i in range(2)]
                        hi = [max(p[i] for p in positions) for i in range(2)]
                        uv = [[(p[i] - lo[i]) / (hi[i] - lo[i]) for i in range(2)] for p in positions]
                        # Source camera faces -Z: +U runs toward decreasing X.
                        for value in uv:
                            value[0] = 1 - value[0]
                        uv_source = 'reconstructed planar label; supplied Vita import has no UV channel'
                    else:
                        uv = [[0, 0] for _ in positions]
                        uv_source = 'source has no UV channel; untextured casing'
                override = node.get(f'surface_material_override/{index}')
                if path in casing and index == 0 and 'default_casing_material' in root:
                    override = root['default_casing_material']
                material = (self.material(*override) if override else
                            self.material(surface.get('material'), mesh_scene))
                surfaces.append({'node': path, 'surface': index, 'name': surface.get('name'),
                                 'role': 'label' if is_label else 'shell',
                                 'positions': positions, 'normals': normals, 'uv': uv,
                                 'uvSource': uv_source,
                                 'indices': indices, 'material': material,
                                 'sourceTransform': matrix,
                                 'sourceVertexSha256': hashlib.sha256(surface['vertex_data']).hexdigest(),
                                 'sourceIndexSha256': hashlib.sha256(surface['index_data']).hexdigest(),
                                 '_import': self.source_buffers(surface, mesh_scene)})
        if not surfaces or not any(s['role'] == 'label' for s in surfaces):
            raise ValueError(f'Missing visible model/label: {name}, {cover}')
        points = [p for s in surfaces for p in s['positions']]
        low, high = [[min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]]
        center = [(low[i] + high[i]) / 2 for i in range(3)]
        width = high[0] - low[0]
        for surface in surfaces:
            surface['positions'] = [[(p[i] - center[i]) / width for i in range(3)] for p in surface['positions']]
            for n in surface['normals']:
                length = math.sqrt(sum(v * v for v in n))
                if length:
                    n[:] = [v / length for v in n]
        model = {'name': name, 'apkSha256': APK_SHA256, 'sourceScene': scene_path,
                 'sourceRootTransform': root.get('transform', ({'values': IDENTITY}, None))[0]['values'],
                 'sourceBasisLayout': 'rows',
                 'sourceMember': self.archive.resolve(scene_path), 'bounds': [(high[i] - low[i]) / width for i in range(3)],
                 'sourceWidth': width, 'surfaces': surfaces, 'animationSource': script_path,
                 'animationSourceSha256': hashlib.sha256(self.archive.plain(script_member)).hexdigest(),
                 'animationTokens': decoded}
        label_normals = [n for s in surfaces if s['role'] == 'label' for n in s['normals']]
        model['frontSign'] = 1 if sum(n[2] for n in label_normals) >= 0 else -1
        label_points = [p for s in surfaces if s['role'] == 'label' for p in s['positions']]
        model['labelAspect'] = ((max(p[0] for p in label_points) - min(p[0] for p in label_points)) /
                                (max(p[1] for p in label_points) - min(p[1] for p in label_points)))
        tokens = ' '.join(decoded.values())
        model['motionKind'] = ('disc' if name == 'disc' else 'umd' if name == 'psp' else
                               'pushClick' if 'bottom_out_y' in tokens else 'drop')
        if name == 'vita':
            model['sourceSceneGap'] = 'cart_vita.tscn absent; imported Vita shell/label and existing Vita script bound with shared rest basis'
        # Exact topology is uploaded once as indexed GPU buffers; the JSON is a
        # source-bound manifest, not thousands of Dart lists rebuilt per frame.
        binary, ranges = pack_mesh(surfaces)
        mesh_file = name + '.mesh'
        (self.output / mesh_file).write_bytes(binary)
        model['meshFile'], model['meshSha256'] = mesh_file, hashlib.sha256(binary).hexdigest()
        for surface, buffers in zip(surfaces, ranges):
            surface.update(buffers)
            matrix = surface['sourceTransform']
            # Disc rotates the cover node's local Y; UMD rotates its local Z.
            # Keep that axis in the same baked coordinates as its exact mesh.
            axis = 1 if name == 'disc' else 2
            spin_axis = [matrix[axis], -matrix[3 + axis], matrix[6 + axis]]
            length = math.sqrt(sum(v * v for v in spin_axis))
            surface['spinAxis'] = [v / length for v in spin_axis]
            surface['pivot'] = [(matrix[9] - center[0]) / width,
                                (-matrix[10] - center[1]) / width,
                                (matrix[11] - center[2]) / width]
            for key in ['positions', 'normals', 'uv', 'indices']:
                del surface[key]
        # Public importer recipes describe where/how to read the owner's APK.
        # They contain no source geometry, image pixels, script tokens or key.
        recipe = {k: v for k, v in model.items() if k != 'animationTokens'}
        recipe['normalizationCenter'] = center
        recipe['surfaces'] = []
        numeric_properties = {'roughness', 'metallic', 'shader_parameter/roughness_scale',
                              'shader_parameter/metallic_scale', 'shader_parameter/normal_depth',
                              'shader_parameter/tint_strength', 'shader_parameter/uv_scale',
                              'shader_parameter/uv_offset', 'shader_parameter/albedo_impact',
                              'shader_parameter/ao_strength'}
        for surface in surfaces:
            imported = dict(surface)
            imported['import'] = surface.pop('_import')
            imported.pop('_import')
            imported['material'] = dict(surface['material'])
            imported['material']['sourceProperties'] = {
                k: v for k, v in surface['material'].get('sourceProperties', {}).items()
                if k in numeric_properties}
            recipe['surfaces'].append(imported)
        self.recipes.append(recipe)
        file = self.output / (name + '.json')
        from socket_resources import json_value
        file.write_text(json.dumps(model, default=json_value, separators=(',', ':')), encoding='utf-8')
        return {'name': name, 'file': file.name, 'triangles': sum(s['indexCount'] // 3 for s in surfaces),
                'surfaces': len(surfaces), 'labelSurfaces': sum(s['role'] == 'label' for s in surfaces),
                'bounds': model['bounds'], 'sha256': hashlib.sha256(file.read_bytes()).hexdigest()}

    def source_buffers(self, surface, scene):
        member = scene['member']
        plain, _ = decompress_resource(self.archive.plain(member))
        spans = {}
        for name in ['vertex_data', 'attribute_data', 'index_data']:
            raw = surface.get(name, b'')
            offset = plain.find(raw) if raw else 0
            if offset < 0:
                raise ValueError('Source buffer not present in its resource')
            spans[name] = {'offset': offset, 'length': len(raw),
                           'sha256': hashlib.sha256(raw).hexdigest()}
        return {'member': member, 'resourceSha256': hashlib.sha256(plain).hexdigest(),
                'spans': spans, 'format': surface['format'],
                'aabb': surface['aabb']['values'],
                'uvScale': surface.get('uv_scale', {'values': [0, 0, 0, 0]})['values']}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--tokenizer-header', required=True)
    parser.add_argument('--recipe-output', help='Public numeric importer recipe, no source payloads')
    args = parser.parse_args()
    archive = SocketArchive(args.apk)
    builder = MediaBuilder(archive, args.output, pathlib.Path(args.tokenizer_header).read_text())
    try:
        environment = builder.environment()
        names = [n.rsplit('/', 1)[1].split('.')[0] for n in archive.zip.namelist()
                 if n.startswith('assets/scenes/selectables/cart_') and n.endswith('.tscn.remap') and 'android' not in n]
        models = []
        for name in names:
            model = builder.build(name.removeprefix('cart_'), 'res://scenes/selectables/' + name + '.tscn')
            models.append(model)
            print(json.dumps(model))
        models.append(builder.build('vita', 'res://models/vita/vita.fbx'))
        print(json.dumps(models[-1]))
        manifest = {'apkSha256': APK_SHA256, 'models': models, 'textures': list(builder.textures.values()),
                    'environment': environment}
        (builder.output / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        if args.recipe_output:
            recipe = {'schema': 1, 'apkSha256': APK_SHA256,
                      'apkSize': pathlib.Path(args.apk).stat().st_size,
                      'models': builder.recipes, 'textures': list(builder.textures.values()),
                      'environment': environment}
            pathlib.Path(args.recipe_output).write_text(json.dumps(recipe, separators=(',', ':')), encoding='utf-8')
    finally:
        archive.close()


if __name__ == '__main__':
    main()
