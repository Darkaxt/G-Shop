"""Adapt the owner's hollow GBA/PCB export as an independent private import.

Blender --background --factory-startup --disable-autoexec --python this_file --
  --source-dir DIR --output DIR
No code from the source ZIP is imported/executed and no source printing is bundled.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import bpy
from mathutils import Vector


def read_glb(path):
    raw = path.read_bytes()
    size, kind = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or kind != 0x4e4f534a:
        raise ValueError('Expected GLB')
    return raw, json.loads(raw[20:20+size]), raw[28+size:]


def srgb(x):
    return 12.92*x if x <= .0031308 else 1.055*x**(1/2.4)-.055


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if args.output.exists():
        raise ValueError('Select an absent output; preserve existing conversions')
    source = args.source_dir/'cartridge-red.glb'
    raw, gltf, binary = read_glb(source)
    profiles, sources = {}, {}
    for style in ['red', 'blue', 'green', 'cloudy-red', 'cloudy-green']:
        content, data, _ = read_glb(args.source_dir/f'cartridge-{style}.glb')
        shell = next(m for m in data['materials'] if m['name'] == 'Dyed_polycarbonate')
        pbr = shell['pbrMetallicRoughness']
        profiles[style] = {'color': [srgb(c) for c in pbr['baseColorFactor'][:3]]+[1],
            'roughness': pbr['roughnessFactor'], 'metallic': 0,
            'transmission': shell['extensions']['KHR_materials_transmission']['transmissionFactor'],
            'ior': shell['extensions']['KHR_materials_ior']['ior'], 'thickness': .0007/.06}
        sources[style] = hashlib.sha256(content).hexdigest()
    profiles['gray'] = {'color': [.24,.245,.25,1], 'roughness': 1,
                        'metallic': 0, 'transmission': 0, 'ior': 1.49, 'thickness': .0007/.06}
    image_bytes, names = {}, {}
    for i, image in enumerate(gltf['images']):
        if image['mimeType'] != 'image/png': raise ValueError('Expected PNG textures')
        view = gltf['bufferViews'][image['bufferView']]
        offset = view.get('byteOffset', 0)
        image_bytes[i] = binary[offset:offset+view['byteLength']]
        names[i] = f'texture-{i:02d}.png'
    def texture(slot): return names[gltf['textures'][slot['index']]['source']]
    materials = {}
    for mat in gltf['materials']:
        pbr = mat.get('pbrMetallicRoughness', {})
        is_label = mat['name'] == 'Opaque_original_Power_Rangers_label'
        maps = {}
        if pbr.get('baseColorTexture') and not is_label:
            maps['albedo'] = texture(pbr['baseColorTexture'])
        if mat.get('normalTexture'): maps['normal'] = texture(mat['normalTexture'])
        if pbr.get('metallicRoughnessTexture'):
            maps.update(roughness=texture(pbr['metallicRoughnessTexture']), metallic=texture(pbr['metallicRoughnessTexture']))
        color = pbr.get('baseColorFactor', [1,1,1,1])
        materials[mat['name']] = {'color': [srgb(c) for c in color[:3]]+[color[3]],
            'textures': maps, 'sourceProperties': {
                'roughness': pbr.get('roughnessFactor', 1), 'metallic': pbr.get('metallicFactor', 1),
                'normal_scale': mat.get('normalTexture', {}).get('scale', 1),
                'roughness_texture_channel': 1, 'metallic_texture_channel': 2}}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    def axis(p): return Vector((p.x, p.z, -p.y))
    points = [axis(o.matrix_world @ v.co) for o in objects for v in o.data.vertices]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    center, scale = (low+high)/2, 1/(high.x-low.x)
    payload, surfaces = bytearray(), []
    for obj in objects:
        mesh = obj.data; mesh.calc_loop_triangles()
        uv = mesh.uv_layers.active.data
        is_label = obj.name == 'Opaque_label'
        if is_label:
            label_points = [axis(obj.matrix_world @ v.co) for v in mesh.vertices]
            label_low = [min(p[a] for p in label_points) for a in range(2)]
            label_high = [max(p[a] for p in label_points) for a in range(2)]
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        for index, mat in enumerate(mesh.materials):
            triangles = [t for t in mesh.loop_triangles if t.material_index == index]
            if not triangles: continue
            offset, count = len(payload), 0
            for tri in triangles:
                for vertex, loop in zip(tri.vertices, tri.loops):
                    p = (axis(obj.matrix_world @ mesh.vertices[vertex].co)-center)*scale
                    n = axis(normal_matrix @ mesh.vertices[vertex].normal).normalized()
                    tex = uv[loop].uv
                    if is_label:
                        # Source printing has its own orientation/bleed. The
                        # replacement Flutter image is top-down and must fit the
                        # whole label independently of that original UV atlas.
                        source_p = axis(obj.matrix_world @ mesh.vertices[vertex].co)
                        u = (source_p.x-label_low[0])/(label_high[0]-label_low[0])
                        v = (label_high[1]-source_p.y)/(label_high[1]-label_low[1])
                    else:
                        u, v = tex.x, 1-tex.y
                    payload.extend(struct.pack('<8f', *p, *n, u, v)); count += 1
            indices = len(payload)
            for i in range(count): payload.extend(struct.pack('<I', i))
            shell = mat.name in ('Dyed_polycarbonate', 'Dyed_polycarbonate_inner')
            surfaces.append({'node': obj.name, 'name': mat.name,
                'role': 'label' if obj.name == 'Opaque_label' else 'shell',
                'shellMaterial': shell, 'physicalMaterial': 'source',
                'singleSided': True, 'vertexOffset': offset, 'vertexCount': count,
                'indexOffset': indices, 'indexCount': count, 'material': materials[mat.name]})
    if not any(s['role'] == 'label' for s in surfaces) or not any(s['shellMaterial'] for s in surfaces):
        raise ValueError('Expected separate source label and hollow shell')
    used = {v for s in surfaces for v in s['material']['textures'].values()}
    textures = {names[i]: hashlib.sha256(b).hexdigest() for i,b in image_bytes.items() if names[i] in used}
    data = {'name': 'gba-hollow-pcb-v1', 'cartridgeGeometry': True, 'privateImport': True,
        'system': 'gba', 'motionKind': 'drop', 'bounds': list((high-low)*scale),
        'sourceWidth': 1, 'labelAspect': .04420377/.02282158, 'frontSign': 1,
        'geometrySha256': hashlib.sha256(payload).hexdigest(), 'textureFiles': textures,
        'profiles': profiles, 'profileSourceSha256': sources,
        'sourceReference': {'author': 'Owner-supplied adaptation of luigi_30 cartridge',
            'url': 'local:Gameboy_Advance_Cartridge.zip', 'licence': 'local-import-only',
            'sha256': hashlib.sha256(raw).hexdigest(),
            'adaptation': 'Full hollow cartridge/approximate AGB-E05-01 PCB; source label printing excluded; normalized Y-up'},
        'surfaces': surfaces}
    args.output.mkdir(parents=True)
    (args.output/'model.mesh').write_bytes(payload)
    (args.output/'model.json').write_text(json.dumps(data, indent=2), encoding='utf8')
    for i,b in image_bytes.items():
        if names[i] in used: (args.output/names[i]).write_bytes(b)
    print('CARTRIDGE_ADAPTED '+json.dumps({'triangles':sum(s['indexCount']//3 for s in surfaces),
        'surfaces':len(surfaces), 'textures':len(textures), 'meshSha256':data['geometrySha256']}))


if __name__ == '__main__': main()
