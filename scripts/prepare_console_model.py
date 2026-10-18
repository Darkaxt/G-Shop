"""Convert a user-provided static GLB scene into a local console preview import.

Blender --background --factory-startup --python this_file -- --source FILE
  --output DIR --system gba --author Unconid --source-url URL
No original geometry or textures are distributed with the application.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--system', required=True)
    parser.add_argument('--author', required=True)
    parser.add_argument('--source-url', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Preserve existing conversions; select an absent output')
    raw = args.source.read_bytes()
    length, tag = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or tag != 0x4e4f534a:
        raise ValueError('Expected GLB JSON chunk')
    gltf = json.loads(raw[20:20+length])
    binary = raw[28+length:]
    if gltf.get('animations') or gltf.get('skins'):
        raise ValueError('This adapter preserves static console display scenes only')
    images = {}
    for i, image in enumerate(gltf['images']):
        if image.get('mimeType') not in ('image/png', 'image/jpeg'):
            raise ValueError('Unsupported embedded texture format')
        view = gltf['bufferViews'][image['bufferView']]
        start = view.get('byteOffset', 0)
        images[i] = binary[start:start+view['byteLength']]
    names = {i: f'texture-{i:02d}.' + ('png' if image['mimeType'] == 'image/png' else 'jpg')
             for i, image in enumerate(gltf['images'])}
    def texture(slot):
        return names[gltf['textures'][slot['index']]['source']]
    materials = {}
    for mat in gltf['materials']:
        pbr = mat.get('pbrMetallicRoughness', {})
        albedo = pbr.get('baseColorTexture')
        orm = pbr.get('metallicRoughnessTexture')
        maps = {}
        if albedo: maps['albedo'] = texture(albedo)
        if orm: maps.update(roughness=texture(orm), metallic=texture(orm))
        if mat.get('normalTexture'): maps['normal'] = texture(mat['normalTexture'])
        if mat.get('occlusionTexture'): maps['ao'] = texture(mat['occlusionTexture'])
        emission = mat.get('emissiveFactor', [0, 0, 0])
        if mat.get('emissiveTexture') and texture(mat['emissiveTexture']) != maps.get('albedo'):
            raise ValueError('Inspected screen emission must share its albedo texture')
        materials[mat['name']] = {
            'color': pbr.get('baseColorFactor', [1, 1, 1, 1]), 'textures': maps,
            'sourceProperties': {'roughness': pbr.get('roughnessFactor', 1),
                'metallic': pbr.get('metallicFactor', 1),
                'normal_scale': mat.get('normalTexture', {}).get('scale', 1),
                'ao_strength': mat.get('occlusionTexture', {}).get('strength', 1),
                'roughness_texture_channel': 1, 'metallic_texture_channel': 2,
                'ao_texture_channel': 0, 'emission': emission}}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    def axis(p): return Vector((p.x, p.z, -p.y))
    points = [axis(o.matrix_world @ v.co) for o in objects for v in o.data.vertices]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    center, scale = (low + high) / 2, 2 / max(high - low)
    payload, surfaces = bytearray(), []
    for obj in objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        uv = mesh.uv_layers.active.data
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        for index, mat in enumerate(mesh.materials):
            triangles = [t for t in mesh.loop_triangles if t.material_index == index]
            if not triangles: continue
            offset, count = len(payload), 0
            for tri in triangles:
                for vertex, loop in zip(tri.vertices, tri.loops):
                    p = (axis(obj.matrix_world @ mesh.vertices[vertex].co) - center) * scale
                    n = axis(normal_matrix @ mesh.vertices[vertex].normal).normalized()
                    tex = uv[loop].uv
                    payload.extend(struct.pack('<8f', *p, *n, tex.x, 1-tex.y))
                    count += 1
            indices = len(payload)
            for i in range(count): payload.extend(struct.pack('<I', i))
            material = materials[mat.name]
            surfaces.append({'node': obj.name, 'name': mat.name, 'role': 'shell',
                'physicalMaterial': 'glass' if any(material['sourceProperties']['emission']) else 'source',
                'singleSided': True, 'vertexOffset': offset, 'vertexCount': count,
                'indexOffset': indices, 'indexCount': count, 'material': material})
    used = {name for s in surfaces for name in s['material']['textures'].values()}
    textures = {names[i]: hashlib.sha256(content).hexdigest()
                for i, content in images.items() if names[i] in used}
    manifest = {'name': f'console-{args.system}-v1', 'hardwareGeometry': True,
        'privateImport': True, 'system': args.system, 'motionKind': 'hardware',
        'bounds': list((high-low)*scale), 'sourceWidth': (high.x-low.x)*scale,
        'labelAspect': 1, 'frontSign': 1, 'canOpen': False,
        'geometrySha256': hashlib.sha256(payload).hexdigest(), 'textureFiles': textures,
        'sourceReference': {'author': args.author, 'url': args.source_url,
            'licence': 'local-import-only', 'sha256': hashlib.sha256(raw).hexdigest(),
            'adaptation': 'Full authored scene; uniform centering/scale, Y-up, source UV/PBR and screen emission'},
        'surfaces': surfaces}
    args.output.mkdir(parents=True)
    (args.output/'model.mesh').write_bytes(payload)
    (args.output/'model.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')
    for i, content in images.items():
        if names[i] in used: (args.output/names[i]).write_bytes(content)
    print('CONSOLE_ADAPTED '+json.dumps({'triangles': sum(s['indexCount']//3 for s in surfaces),
        'surfaces': len(surfaces), 'textures': len(textures), 'sourceSha256': manifest['sourceReference']['sha256']}))


if __name__ == '__main__': main()
