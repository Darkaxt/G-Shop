"""Convert owner-supplied special GBA assemblies; never execute archive code.

Blender --background --factory-startup --disable-autoexec --python this_file --
  --source FILE --style twisted-us|boktai|yoshi-us --output DIR
Keep source geometry, separate shell/PCB materials and replaceable opaque labels.
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
    parser.add_argument('--style', choices=['twisted-us', 'boktai', 'yoshi-us'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Preserve earlier conversions; choose an absent output')
    raw = args.source.read_bytes()
    size, kind = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or kind != 0x4e4f534a:
        raise ValueError('Expected GLB JSON')
    gltf = json.loads(raw[20:20 + size])
    binary = raw[28 + size:]
    def srgb(c):
        return c * 12.92 if c <= .0031308 else 1.055 * c ** (1 / 2.4) - .055
    images = {}
    for i, image in enumerate(gltf.get('images', [])):
        if image.get('mimeType') not in ('image/png', 'image/jpeg'):
            raise ValueError('Expected embedded image')
        view = gltf['bufferViews'][image['bufferView']]
        offset = view.get('byteOffset', 0)
        suffix = 'png' if image['mimeType'] == 'image/png' else 'jpg'
        images[i] = (f'texture-{i:02d}.{suffix}', binary[offset:offset + view['byteLength']])
    materials = {}
    for material in gltf['materials']:
        pbr = material.get('pbrMetallicRoughness', {})
        label = material['name'] in ('Original_USA_label', 'Original_reference_label')
        maps = {}
        def texture(slot):
            return images[gltf['textures'][slot['index']]['source']][0]
        if pbr.get('baseColorTexture') and not label:
            maps['albedo'] = texture(pbr['baseColorTexture'])
        if material.get('normalTexture'):
            maps['normal'] = texture(material['normalTexture'])
        if pbr.get('metallicRoughnessTexture'):
            maps.update(roughness=texture(pbr['metallicRoughnessTexture']),
                        metallic=texture(pbr['metallicRoughnessTexture']))
        color = pbr.get('baseColorFactor', [1, 1, 1, 1])
        shell = material['name'] in ('Shell_polycarbonate', 'Rear_shell_polycarbonate')
        extensions = material.get('extensions', {})
        transmission = extensions.get('KHR_materials_transmission', {}).get('transmissionFactor', 0)
        properties = {'roughness': max(.32, pbr.get('roughnessFactor', 1)) if shell else pbr.get('roughnessFactor', 1),
                      'metallic': 0 if shell or label else pbr.get('metallicFactor', 1),
                      'normal_scale': material.get('normalTexture', {}).get('scale', 1),
                      'roughness_texture_channel': 1, 'metallic_texture_channel': 2}
        if shell:
            properties.update(sourceTransmission=transmission,
                transmission=(.32 if args.style == 'twisted-us' else .55) if transmission else 0,
                ior=extensions.get('KHR_materials_ior', {}).get('ior', 1.49), thickness=.012)
        materials[material['name']] = ({'color': [1, 1, 1, 1] if label else
            [*[srgb(c) for c in color[:3]], color[3]], 'textures': maps,
            'sourceProperties': properties}, label, shell, not material.get('doubleSided', False))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    def axis(p):
        return Vector((p.x, p.z, -p.y))
    points = [axis(o.matrix_world @ v.co) for o in objects for v in o.data.vertices]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    center, scale = (low + high) / 2, 1 / (high.x - low.x)
    payload, surfaces = bytearray(), []
    for obj in objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        uv = mesh.uv_layers.active.data if mesh.uv_layers.active else None
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        label_points = [axis(obj.matrix_world @ v.co) for v in mesh.vertices]
        label_low = [min(p[a] for p in label_points) for a in range(2)]
        label_high = [max(p[a] for p in label_points) for a in range(2)]
        for index, mat in enumerate(mesh.materials):
            material, label, shell, single_sided = materials[mat.name]
            triangles = [t for t in mesh.loop_triangles if t.material_index == index]
            if not triangles:
                continue
            offset, count = len(payload), 0
            for triangle in triangles:
                for vertex, loop in zip(triangle.vertices, triangle.loops):
                    original = axis(obj.matrix_world @ mesh.vertices[vertex].co)
                    position = (original - center) * scale
                    normal = axis(normal_matrix @ mesh.vertices[vertex].normal).normalized()
                    u, v = (uv[loop].uv.x, 1 - uv[loop].uv.y) if uv else (0, 0)
                    if label:
                        u = (original.x - label_low[0]) / (label_high[0] - label_low[0])
                        v = (label_high[1] - original.y) / (label_high[1] - label_low[1])
                    payload.extend(struct.pack('<8f', *position, *normal, u, v))
                    count += 1
            indices = len(payload)
            for i in range(count):
                payload.extend(struct.pack('<I', i))
            surfaces.append({'node': obj.name, 'name': mat.name, 'role': 'label' if label else 'shell',
                'shellMaterial': shell, 'singleSided': single_sided,
                'vertexOffset': offset, 'vertexCount': count, 'indexOffset': indices,
                'indexCount': count, 'material': material})
    labels = [s for s in surfaces if s['role'] == 'label']
    if len(labels) != 1 or not any(s['shellMaterial'] for s in surfaces):
        raise ValueError('Expected one replaceable label and separate shell')
    used = {name for s in surfaces for name in s['material']['textures'].values()}
    textures = {name: hashlib.sha256(content).hexdigest() for name, content in images.values() if name in used}
    data = {'name': f'gba-special-{args.style}', 'system': 'gba', 'motionKind': 'drop',
        'cartridgeStyle': args.style, 'cartridgeGeometry': True, 'privateImport': True,
        'sourceWidth': 1, 'bounds': list((high - low) * scale), 'labelAspect': 2,
        'frontSign': 1, 'geometrySha256': hashlib.sha256(payload).hexdigest(),
        'textureFiles': textures, 'surfaces': surfaces,
        'sourceReference': {'author': 'Darkaxt owner-supplied photo-based reconstruction',
            'url': 'local:gba-special-models.zip', 'licence': 'local-import-only',
            'sha256': hashlib.sha256(raw).hexdigest(),
            'adaptation': 'Preserved shell/PCB geometry and distinct materials; original label printing excluded; dimensions inferred; photograph attribution retained in SOURCES.md'}}
    args.output.mkdir(parents=True)
    (args.output / 'model.mesh').write_bytes(payload)
    (args.output / 'model.json').write_text(json.dumps(data, indent=2), encoding='utf8')
    for name, content in images.values():
        if name in used:
            (args.output / name).write_bytes(content)
    print('SPECIAL_CARTRIDGE_ADAPTED ' + json.dumps({'style': args.style,
        'triangles': sum(s['indexCount'] // 3 for s in surfaces),
        'surfaces': len(surfaces), 'bounds': data['bounds'], 'sha256': data['geometrySha256']}))


if __name__ == '__main__':
    main()
