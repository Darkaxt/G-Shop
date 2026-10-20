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
from mathutils import Vector, Quaternion, Matrix


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--system', required=True)
    parser.add_argument('--author', required=True)
    parser.add_argument('--source-url', required=True)
    parser.add_argument('--rom-set', help='Exact supplied Game & Watch MAME set')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Preserve existing conversions; select an absent output')
    raw = args.source.read_bytes()
    length, tag = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or tag != 0x4e4f534a:
        raise ValueError('Expected GLB JSON chunk')
    gltf = json.loads(raw[20:20+length])
    binary = raw[28+length:]
    if gltf.get('skins') or gltf.get('animations') and not args.rom_set:
        raise ValueError('This adapter preserves static console display scenes only')
    if args.rom_set and (args.system != 'gameandwatch' or
            not __import__('re').fullmatch('[a-z0-9_]+', args.rom_set)):
        raise ValueError('Expected an exact Game & Watch set')
    animation = next((a for a in gltf.get('animations', []) if a['name'] == 'Open'), None)
    if gltf.get('animations') and (animation is None or
            {a['name'] for a in gltf['animations']} != {'Open', 'Close'}):
        raise ValueError('Only the inspected rigid Open/Close pair is supported')
    def values(index):
        a = gltf['accessors'][index]
        view = gltf['bufferViews'][a['bufferView']]
        width = {'SCALAR': 1, 'VEC4': 4}[a['type']]
        if a['componentType'] != 5126 or 'sparse' in a:
            raise ValueError('Expected float rigid animation keys')
        start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = view.get('byteStride', width * 4)
        return [struct.unpack_from('<'+'f'*width, binary, start+i*stride) for i in range(a['count'])]
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
    double_sided = {}
    for mat in gltf['materials']:
        double_sided[mat['name']] = mat.get('doubleSided', False)
        pbr = mat.get('pbrMetallicRoughness', {})
        albedo = pbr.get('baseColorTexture')
        orm = pbr.get('metallicRoughnessTexture')
        maps = {}
        if albedo: maps['albedo'] = texture(albedo)
        if orm: maps.update(roughness=texture(orm), metallic=texture(orm))
        if mat.get('normalTexture'): maps['normal'] = texture(mat['normalTexture'])
        if mat.get('occlusionTexture'): maps['ao'] = texture(mat['occlusionTexture'])
        emission = mat.get('emissiveFactor', [0, 0, 0])
        if mat.get('emissiveTexture'): maps['emission'] = texture(mat['emissiveTexture'])
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
    frame_origin = 0
    if animation:
        starts = []
        for obj in bpy.context.scene.objects:
            if obj.animation_data:
                obj.animation_data.action = None
                for track in obj.animation_data.nla_tracks:
                    track.mute = track.name != 'Open'
                    if not track.mute: starts.extend(s.frame_start for s in track.strips)
        frame_origin = min(starts)
        bpy.context.scene.frame_set(int(frame_origin))
        bpy.context.view_layer.update()
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    def axis(p): return Vector((p.x, p.z, -p.y))
    points = [axis(o.matrix_world @ v.co) for o in objects for v in o.data.vertices]
    # Frame the actual articulated envelope, not only the closed shell. Mesh
    # vertices and hinge pivots are still exported from the closed rest pose.
    pose_bounds = []
    if animation:
        key_times = sorted({t[0] for s in animation['samplers'] for t in values(s['input'])})
        fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
        for time in key_times:
            frame = frame_origin + time * fps
            bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame))
            bpy.context.view_layer.update()
            current = [axis(o.matrix_world @ v.co) for o in objects for v in o.data.vertices]
            points.extend(current)
            pose_bounds.append((time/key_times[-1], Vector([
                (min(p[a] for p in current)+max(p[a] for p in current))/2
                for a in range(3)])))
        bpy.context.scene.frame_set(int(frame_origin))
        bpy.context.view_layer.update()
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    center, scale = (low + high) / 2, 2 / max(high - low)
    hinges = {}
    duration = 0
    if animation:
        for channel in animation['channels']:
            node = gltf['nodes'][channel['target']['node']]
            sampler = animation['samplers'][channel['sampler']]
            if channel['target']['path'] != 'rotation' or sampler.get('interpolation', 'LINEAR') != 'LINEAR':
                raise ValueError('Expected inspected linear quaternion hinge')
            obj = bpy.data.objects[node['name']]
            rotations = values(sampler['output'])
            # Geometry is baked from frame zero (closed), not glTF's authored
            # default node pose, which is open in the supplied folding models.
            rotation = rotations[0]
            base = Quaternion((rotation[3], *rotation[:3]))
            pairs = []
            direction = None
            times = values(sampler['input'])
            duration = max(duration, times[-1][0])
            for time, q in zip(times, rotations):
                delta = Quaternion((q[3], *q[:3])) @ base.inverted()
                if delta.w < 0: delta.negate()
                if delta.angle > .00001 and direction is None: direction = delta.axis.copy()
                pairs.append((time[0] / times[-1][0], delta))
            direction = direction or Vector((1, 0, 0))
            parent = obj.parent.matrix_world.to_3x3() if obj.parent else Matrix.Identity(3)
            blender_direction = Vector((direction.x, -direction.z, direction.y))
            hinges[obj.name] = {'pivot': list((axis(obj.matrix_world.translation)-center)*scale),
                'axis': list(axis(parent @ blender_direction).normalized()),
                'keys': [[t, q.angle * (-1 if q.axis.dot(direction) < 0 else 1)] for t, q in pairs]}
    payload, surfaces = bytearray(), []
    closed_world = {o.name: o.matrix_world.copy() for o in objects}
    for obj in objects:
        chain, parent = [], obj.parent
        while parent:
            if parent.name in hinges: chain.insert(0, hinges[parent.name])
            parent = parent.parent
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
                'singleSided': not double_sided[mat.name], 'openingHinges': chain,
                'vertexOffset': offset, 'vertexCount': count,
                'indexOffset': indices, 'indexCount': count, 'material': material})
    animation_error = 0
    if hinges:
        # Verify the converted pivot/axis convention against Blender's actual
        # evaluated animation before accepting a private articulated import.
        for progress in (.5, 1):
            frame = frame_origin + progress * duration * fps
            bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame))
            bpy.context.view_layer.update()
            for obj in objects:
                chain = next(s['openingHinges'] for s in surfaces if s['node'] == obj.name)
                for vertex in obj.data.vertices:
                    point = (axis(closed_world[obj.name] @ vertex.co)-center)*scale
                    for hinge in reversed(chain):
                        keys = hinge['keys']
                        a, b = next((a, b) for a, b in zip(keys, keys[1:]) if a[0] <= progress <= b[0])
                        angle = a[1] + (b[1]-a[1]) * (progress-a[0])/(b[0]-a[0])
                        pivot = Vector(hinge['pivot'])
                        point = pivot + Quaternion(Vector(hinge['axis']), angle) @ (point-pivot)
                    expected = (axis(obj.matrix_world @ vertex.co)-center)*scale
                    animation_error = max(animation_error, (expected-point).length)
        if animation_error > .0001:
            raise ValueError(f'Converted hinge differs from source animation: {animation_error}')
    used = {name for s in surfaces for name in s['material']['textures'].values()}
    textures = {names[i]: hashlib.sha256(content).hexdigest()
                for i, content in images.items() if names[i] in used}
    manifest = {'name': f'console-{args.system}-v1', 'hardwareGeometry': True,
        'privateImport': True, 'system': args.system, 'motionKind': 'hardware',
        'bounds': list((high-low)*scale), 'sourceWidth': (high.x-low.x)*scale,
        'labelAspect': 1, 'frontSign': 1, 'canOpen': bool(hinges),
        'animationVerifiedMaxError': animation_error,
        'geometrySha256': hashlib.sha256(payload).hexdigest(), 'textureFiles': textures,
        'sourceReference': {'author': args.author, 'url': args.source_url,
            'licence': 'local-import-only', 'sha256': hashlib.sha256(raw).hexdigest(),
            'adaptation': 'Full authored scene; uniform centering/scale, Y-up, source UV/PBR and screen emission'},
        'surfaces': surfaces}
    if args.rom_set:
        manifest['romSet'] = args.rom_set
        manifest['openingDurationMs'] = round(duration*1000) if hinges else 2000
    if pose_bounds:
        manifest['poseCenters'] = [[time, *list((point-center)*scale)] for time, point in pose_bounds]
    if gltf.get('extras', {}).get('controlRegistration'):
        manifest['sourceReference']['controlRegistration'] = gltf['extras']['controlRegistration']
    args.output.mkdir(parents=True)
    (args.output/'model.mesh').write_bytes(payload)
    (args.output/'model.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')
    for i, content in images.items():
        if names[i] in used: (args.output/names[i]).write_bytes(content)
    print('CONSOLE_ADAPTED '+json.dumps({'triangles': sum(s['indexCount']//3 for s in surfaces),
        'surfaces': len(surfaces), 'textures': len(textures), 'sourceSha256': manifest['sourceReference']['sha256']}))


if __name__ == '__main__': main()
