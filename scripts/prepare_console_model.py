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
    parser.add_argument('--visual-variant-id', help='Explicit visual-only hardware edition; no ROM binding')
    parser.add_argument('--resource-kind', choices=('handheld', 'box'), default='handheld')
    parser.add_argument('--gamewatch-collection', action='store_true',
                        help='Bounded overview of the supplied 63-device selector; hide its display board')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Preserve existing conversions; select an absent output')
    raw = args.source.read_bytes()
    length, tag = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or tag != 0x4e4f534a:
        raise ValueError('Expected GLB JSON chunk')
    gltf = json.loads(raw[20:20+length])
    binary = raw[28+length:]
    if gltf.get('skins') or gltf.get('animations') and not (args.rom_set or args.visual_variant_id):
        raise ValueError('This adapter preserves static console display scenes only')
    if args.rom_set and (args.system != 'gameandwatch' or
            not __import__('re').fullmatch('[a-z0-9_]+', args.rom_set)):
        raise ValueError('Expected an exact Game & Watch set')
    if args.visual_variant_id and (args.rom_set or args.system != 'gameandwatch' or
            not __import__('re').fullmatch('[a-z0-9_-]+', args.visual_variant_id)):
        raise ValueError('Expected a visual-only Game & Watch variant identity')
    if args.resource_kind == 'box' and not (args.rom_set or args.visual_variant_id):
        raise ValueError('A box import requires its exact associated hardware identity')
    source_animations = {a['name']: a for a in gltf.get('animations', [])}
    if len(source_animations) != len(gltf.get('animations', [])):
        raise ValueError('Source animation names must be unique')
    clip_names = set(source_animations)
    if clip_names not in (set(), {'Open', 'Close'},
            {'BatteryRemove', 'BatteryInsert'},
            {'Open', 'Close', 'BatteryRemove', 'BatteryInsert'}):
        raise ValueError('Expected inspected opening and/or battery animation pairs')
    animation = source_animations.get('Open')
    def values(index):
        a = gltf['accessors'][index]
        view = gltf['bufferViews'][a['bufferView']]
        width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[a['type']]
        if a['componentType'] != 5126 or 'sparse' in a:
            raise ValueError('Expected float rigid animation keys')
        start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = view.get('byteStride', width * 4)
        return [struct.unpack_from('<'+'f'*width, binary, start+i*stride) for i in range(a['count'])]
    # Battery removal is a separate source action, not a handheld opening. Keep
    # it closed in the preview and preserve the complete original GLB/Blend.
    # Accept only the inspected reversible rigid tracks whose first removal
    # pose agrees with the authored node rest; never bake an arbitrary NLA pose.
    if 'BatteryRemove' in source_animations:
        remove, insert = (source_animations[n] for n in ('BatteryRemove', 'BatteryInsert'))
        def battery_tracks(clip):
            tracks = {}
            for channel in clip['channels']:
                target = channel['target']
                sampler = clip['samplers'][channel['sampler']]
                key = (target['node'], target['path'])
                if key in tracks or target['path'] not in ('translation', 'rotation') or sampler.get('interpolation', 'LINEAR') != 'LINEAR':
                    raise ValueError('Expected independent linear rigid battery action')
                tracks[key] = values(sampler['output'])
            return tracks
        removed, inserted = battery_tracks(remove), battery_tracks(insert)
        if removed.keys() != inserted.keys():
            raise ValueError('Battery removal/insertion target mismatch')
        opening_targets = {c['target']['node'] for c in animation['channels']} if animation else set()
        for (index, path), keys in removed.items():
            reverse = inserted[(index, path)]
            rest = gltf['nodes'][index].get(path, [0, 0, 0] if path == 'translation' else [0, 0, 0, 1])
            if index in opening_targets or len(keys) != len(reverse) or any(abs(a-b) > 1e-6 for a, b in zip(keys[0], rest)) or any(abs(a-b) > 1e-6 for left, right in zip(keys, reversed(reverse)) for a, b in zip(left, right)):
                raise ValueError('Battery action must preserve closed rest and reverse exactly')
    images = {}
    for i, image in enumerate(gltf.get('images', [])):
        if image.get('mimeType') not in ('image/png', 'image/jpeg'):
            raise ValueError('Unsupported embedded texture format')
        view = gltf['bufferViews'][image['bufferView']]
        start = view.get('byteOffset', 0)
        images[i] = binary[start:start+view['byteLength']]
    names = {i: f'texture-{i:02d}.' + ('png' if image['mimeType'] == 'image/png' else 'jpg')
             for i, image in enumerate(gltf.get('images', []))}
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
    # Preserve the source's optical glass contract for the existing transmission
    # renderer. A blank Crystal window must not become an opaque LCD plate.
    for mat in gltf['materials']:
        extensions = mat.get('extensions', {})
        properties = materials[mat['name']]['sourceProperties']
        if 'KHR_materials_transmission' in extensions:
            properties['transmission'] = extensions['KHR_materials_transmission'].get('transmissionFactor', 0)
        if 'KHR_materials_ior' in extensions:
            properties['ior'] = extensions['KHR_materials_ior'].get('ior', 1.5)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    collection = None
    if args.gamewatch_collection:
        if args.system != 'gameandwatch' or args.rom_set or args.visual_variant_id or source_animations:
            raise ValueError('Collection preparation is only for the static Game & Watch selector')
        root = bpy.data.objects.get('LCD_handheld_collection')
        board = bpy.data.objects.get('Display_board')
        if root is None or board is None or board.parent != root or len(root.children) != 64:
            raise ValueError('Expected the inspected collection with 63 devices and its separate board')
        devices = sorted(o.name for o in root.children if o != board)
        source_triangles = sum(len(o.data.polygons) for o in root.children_recursive if o.type == 'MESH')
        bpy.data.objects.remove(board, do_unlink=True)
        # The authored display is horizontal. Stand the complete arrangement up
        # as one unit so the existing upright turntable presents its faces.
        root.rotation_euler.rotate_axis('X', __import__('math').pi / 2)
        bpy.context.view_layer.update()
        # Close-up imports remain untouched. At overview scale each device is
        # only a small fraction of the display; retain every object and its UVs
        # while reducing curved tessellation and limiting decoded texture memory.
        for obj in list(root.children_recursive):
            if obj.type != 'MESH' or len(obj.data.polygons) <= 24:
                continue
            bpy.context.view_layer.objects.active = obj
            mod = obj.modifiers.new('Selector overview tessellation', 'DECIMATE')
            mod.ratio = max(.10, 24 / len(obj.data.polygons))
            mod.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=mod.name)
        # Semantically identical materials can share a draw without altering
        # printed artwork, optical properties or the individual placements.
        canonical = {}
        aliases = {}
        for name, material in materials.items():
            key = json.dumps([material, double_sided[name]], sort_keys=True)
            aliases[name] = canonical.setdefault(key, name)
        for obj in root.children_recursive:
            if obj.type == 'MESH':
                for slot in obj.material_slots:
                    slot.material = bpy.data.materials[aliases[slot.material.name]]
        # Merge only surfaces sharing the full material contract after geometry
        # export below; retain per-device names in provenance.
        collection = {'kind': 'gamewatchCollection', 'deviceCount': len(devices),
                      'devices': devices, 'hiddenNodes': ['Display_board'],
                      'textureMaxDimension': 256, 'sourcePolygons': source_triangles,
                      'overviewDecimationRatio': .10}
        for i, content in list(images.items()):
            # Blender's imported images carry the exact embedded bytes; find by
            # glTF image name, and encode a private smaller overview copy.
            source_name = gltf['images'][i].get('name')
            image = bpy.data.images.get(source_name) if source_name else None
            if image is None:
                raise ValueError(f'Cannot identify selector texture {i}: {source_name}')
            width, height = image.size[:]
            if max(width, height) > 256:
                ratio = 256 / max(width, height)
                image.scale(max(1, round(width * ratio)), max(1, round(height * ratio)))
            # pack() encodes the in-memory resized pixels without a scratch file.
            image.pack()
            images[i] = bytes(image.packed_file.data)
            if images[i][:8] == b'\x89PNG\r\n\x1a\n':
                replacement = f'texture-{i:02d}.png'
                original = names[i]
                for material in materials.values():
                    for role, value in material['textures'].items():
                        if value == original: material['textures'][role] = replacement
                names[i] = replacement
    frame_origin = 0
    starts = []
    for obj in bpy.context.scene.objects:
        if obj.animation_data:
            obj.animation_data.action = None
            for track in obj.animation_data.nla_tracks:
                track.mute = not animation or track.name != 'Open'
                if not track.mute: starts.extend(s.frame_start for s in track.strips)
    if animation:
        if not starts:
            raise ValueError('Imported opening action was not found')
        frame_origin = min(starts)
        bpy.context.scene.frame_set(int(frame_origin))
        bpy.context.view_layer.update()
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    def axis(p): return Vector((p.x, p.z, -p.y))
    points = [axis(o.matrix_world @ v.co) for o in objects for v in o.data.vertices]
    # Frame the actual articulated envelope, not only the closed shell. Mesh
    # vertices and hinge pivots are still exported from the closed rest pose.
    pose_bounds = []
    animation_start, duration = 0, 0
    if animation:
        key_times = sorted({t[0] for s in animation['samplers'] for t in values(s['input'])})
        animation_start, animation_end = key_times[0], key_times[-1]
        duration = animation_end - animation_start
        if duration <= 0:
            raise ValueError('Opening action requires a positive time span')
        fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
        for time in key_times:
            frame = frame_origin + (time - animation_start) * fps
            bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame))
            bpy.context.view_layer.update()
            current = [axis(o.matrix_world @ v.co) for o in objects for v in o.data.vertices]
            points.extend(current)
            pose_bounds.append(((time-animation_start)/duration, Vector([
                (min(p[a] for p in current)+max(p[a] for p in current))/2
                for a in range(3)])))
        bpy.context.scene.frame_set(int(frame_origin))
        bpy.context.view_layer.update()
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    center, scale = (low + high) / 2, 2 / max(high - low)
    hinges = {}
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
            if abs(times[0][0] - animation_start) > 1e-6 or abs(times[-1][0] - animation_end) > 1e-6:
                raise ValueError('Opening hinges must share the inspected clip time span')
            for time, q in zip(times, rotations):
                delta = Quaternion((q[3], *q[:3])) @ base.inverted()
                if delta.w < 0: delta.negate()
                if delta.angle > .00001 and direction is None: direction = delta.axis.copy()
                pairs.append(((time[0] - animation_start) / duration, delta))
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
        uv = mesh.uv_layers.active.data if mesh.uv_layers.active else None
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        for index, mat in enumerate(mesh.materials):
            triangles = [t for t in mesh.loop_triangles if t.material_index == index]
            if not triangles: continue
            material = materials[mat.name]
            if uv is None and material['textures']:
                raise ValueError(f'Textured mesh part has no UV coordinates: {obj.name}')
            offset, count = len(payload), 0
            for tri in triangles:
                for vertex, loop in zip(tri.vertices, tri.loops):
                    p = (axis(obj.matrix_world @ mesh.vertices[vertex].co) - center) * scale
                    n = axis(normal_matrix @ mesh.vertices[vertex].normal).normalized()
                    tex = uv[loop].uv if uv is not None else (0, 0)
                    payload.extend(struct.pack('<8f', *p, *n, tex[0], 1-tex[1]))
                    count += 1
            indices = len(payload)
            for i in range(count): payload.extend(struct.pack('<I', i))
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
    if collection:
        merged = {}
        for surface in surfaces:
            key = surface['name']
            group = merged.setdefault(key, [])
            group.append(surface)
        source_payload, payload, surfaces = payload, bytearray(), []
        for name, group in merged.items():
            surface = dict(group[0])
            offset, count = len(payload), 0
            for part in group:
                start, size = part['vertexOffset'], part['vertexCount'] * 32
                payload.extend(source_payload[start:start+size])
                count += part['vertexCount']
            indices = len(payload)
            for i in range(count): payload.extend(struct.pack('<I', i))
            surface.update(node='Collection material ' + name, vertexOffset=offset,
                           vertexCount=count, indexOffset=indices, indexCount=count)
            surfaces.append(surface)
        if len(payload) > 20 * 1024 * 1024 or len(surfaces) > 384:
            raise ValueError('Selector exceeds the bounded overview geometry budget')
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
            'sourceAnimationClips': list(source_animations),
            'previewAnimationPolicy': {
                'opening': ['Open', 'Close'] if animation else [],
                'heldAtAuthoredRest': ['BatteryRemove', 'BatteryInsert'] if 'BatteryRemove' in source_animations else []},
            'adaptation': 'Full authored scene; uniform centering/scale, Y-up, source UV/PBR and screen emission'},
        'surfaces': surfaces}
    if collection:
        manifest['selectorScene'] = collection
        manifest['sourceReference']['adaptation'] = 'All 63 original placements; only Display_board hidden; upright overview, reduced tessellation and 256px textures; original sources retained'
    if args.rom_set:
        manifest['romSet'] = args.rom_set
        manifest['resourceKind'] = args.resource_kind
        manifest['openingDurationMs'] = round(duration*1000) if hinges else 2000
    if args.visual_variant_id:
        manifest['visualVariantId'] = args.visual_variant_id
        manifest['resourceKind'] = args.resource_kind
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
