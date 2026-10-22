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
import subprocess
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
    parser.add_argument('--edition-id', help='Exact NES carton catalogue edition ID')
    parser.add_argument('--nes-standard-carton', action='store_true',
                        help='Reviewed metre-scale NES carton with separate foam spacer')
    parser.add_argument('--cartridge-style', help='Explicit NES cartridge reference identity')
    parser.add_argument('--launch-target', choices=('nes-front-loader', 'nes-top-loader'),
                        help='Inspected NES launch derivative with source-bound calibration')
    parser.add_argument('--launch-display', action='store_true',
                        help='Inspected supplied NES external display with physical screen anchors')
    parser.add_argument('--scratch-directory', type=Path,
                        help='Owned scratch for GLBs requiring unique Blender material names')
    parser.add_argument('--visual-variant-id', help='Explicit visual-only hardware edition; no ROM binding')
    parser.add_argument('--resource-kind', choices=('handheld', 'box'), default='handheld')
    parser.add_argument('--text-orientation-python', type=Path,
                        help='Explicit installed host Python with Pillow for assembled-panel OCR')
    parser.add_argument('--orientation-title',
                        help='Actual carton title used for source-bound OCR anchors')
    parser.add_argument('--orientation-language', default='en-US',
                        help='Installed Windows OCR language; uncertain text requires review')
    parser.add_argument('--gamewatch-collection', action='store_true',
                        help='Bounded overview of the supplied 63-device selector; hide its display board')
    parser.add_argument('--overview-max-triangles', type=int,
                        help='Bound a static multi-object console selector without removing objects')
    parser.add_argument('--overview-texture-size', type=int, default=512)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.resource_kind == 'box' and (not args.text_orientation_python or
            not args.text_orientation_python.is_file() or not args.orientation_title):
        parser.error('Box conversion requires --text-orientation-python and --orientation-title')
    if args.output.exists():
        raise ValueError('Preserve existing conversions; select an absent output')
    raw = args.source.read_bytes()
    length, tag = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or tag != 0x4e4f534a:
        raise ValueError('Expected GLB JSON chunk')
    gltf = json.loads(raw[20:20+length])
    binary = raw[28+length:]
    import_source = args.source
    material_names = [m.get('name','') for m in gltf.get('materials',[])]
    if len(set(material_names)) != len(material_names):
        if args.scratch_directory is None:
            raise ValueError('Duplicate source material names require an explicit scratch directory')
        for index, mat in enumerate(gltf['materials']):
            mat['name'] = mat.get('name','Material')[:40] + f'__gltf_{index}'
        encoded = json.dumps(gltf,separators=(',',':')).encode('utf-8')
        encoded += b' ' * (-len(encoded)%4)
        prepared = struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary)) + struct.pack('<II',len(encoded),0x4e4f534a) + encoded + struct.pack('<II',len(binary),0x004e4942) + binary
        args.scratch_directory.mkdir(parents=True,exist_ok=True)
        import_source = args.scratch_directory/(hashlib.sha256(prepared).hexdigest()+'.glb')
        if not import_source.exists(): import_source.write_bytes(prepared)
        elif import_source.read_bytes()!=prepared: raise ValueError('Canonical material scratch differs')
    if gltf.get('skins') or gltf.get('animations') and not (args.rom_set or args.visual_variant_id or args.edition_id or args.cartridge_style or args.launch_target):
        raise ValueError('This adapter preserves static console display scenes only')
    launch = gltf.get('extras', {}).get('launchHardware')
    display = gltf.get('extras', {}).get('launchDisplay')
    if args.launch_display and (args.system != 'nes' or args.launch_target or
            args.rom_set or args.visual_variant_id or args.edition_id or
            args.cartridge_style or not isinstance(display, dict) or
            display.get('schema') != 1 or display.get('target') != 'sony-kv1300e' or
            display.get('sourceUnits') != 'centimetres' or
            display.get('physicalWidthCm') != 47.4):
        raise ValueError('Expected the source-bound Sony external display')
    if args.launch_target and (args.system != 'nes' or args.rom_set or
            args.visual_variant_id or args.edition_id or args.cartridge_style or
            not isinstance(launch, dict) or launch.get('schema') != 1 or
            launch.get('target') != args.launch_target or
            launch.get('system') != args.system or
            launch.get('compatibleMedia') != 'nes-72-pin' or
            launch.get('controllerPort') != 1):
        raise ValueError('Expected a source-bound NES launch calibration')
    if args.rom_set and (args.system != 'gameandwatch' or
            not __import__('re').fullmatch('[a-z0-9_]+', args.rom_set)):
        raise ValueError('Expected an exact Game & Watch set')
    if args.visual_variant_id and (args.rom_set or args.system != 'gameandwatch' or
            not __import__('re').fullmatch('[a-z0-9_-]+', args.visual_variant_id)):
        raise ValueError('Expected a visual-only Game & Watch variant identity')
    if args.edition_id and (args.system != 'nes' or args.resource_kind != 'box' or
            args.rom_set or args.visual_variant_id or
            not __import__('re').fullmatch('nes-[0-9a-f]{12}', args.edition_id)):
        raise ValueError('Expected an exact NES carton edition')
    if args.resource_kind == 'box' and not (args.rom_set or args.visual_variant_id or args.edition_id):
        raise ValueError('A box import requires its exact associated hardware identity')
    source_animations = {a['name']: a for a in gltf.get('animations', [])}
    if args.cartridge_style and (args.system != 'nes' or args.edition_id or args.rom_set or args.visual_variant_id or not __import__('re').fullmatch('[a-z0-9-]+',args.cartridge_style)):
        raise ValueError('Expected an explicit NES cartridge reference')
    if args.overview_max_triangles is not None and (
            source_animations or args.gamewatch_collection or
            not 1000 <= args.overview_max_triangles <= 180000 or
            args.overview_texture_size not in (256, 512, 1024)):
        raise ValueError('Expected a bounded static selector overview')
    if len(source_animations) != len(gltf.get('animations', [])):
        raise ValueError('Source animation names must be unique')
    clip_names = set(source_animations)
    if clip_names not in ((set(), {'Explode','Assemble'}) if args.cartridge_style else (set(), {'Open', 'Close'},
            {'BatteryRemove', 'BatteryInsert'},
            {'Open', 'Close', 'BatteryRemove', 'BatteryInsert'})):
        raise ValueError('Expected inspected opening and/or battery animation pairs')
    animation = source_animations.get('Explode' if args.cartridge_style else 'Open')
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
    material_uv_sets = {}
    double_sided = {}
    for mat in gltf['materials']:
        double_sided[mat['name']] = mat.get('doubleSided', False)
        pbr = mat.get('pbrMetallicRoughness', {})
        slots = [value for value in [pbr.get('baseColorTexture'),
            pbr.get('metallicRoughnessTexture'), mat.get('normalTexture'),
            mat.get('occlusionTexture'), mat.get('emissiveTexture')] if value]
        uv_sets = {slot.get('texCoord', 0) for slot in slots}
        if len(uv_sets) > 1:
            raise ValueError('A runtime surface requires one shared texture UV set')
        material_uv_sets[mat['name']] = next(iter(uv_sets), 0)
        albedo = pbr.get('baseColorTexture')
        orm = pbr.get('metallicRoughnessTexture')
        maps = {}
        if albedo: maps['albedo'] = texture(albedo)
        if orm: maps.update(roughness=texture(orm), metallic=texture(orm))
        if mat.get('normalTexture'): maps['normal'] = texture(mat['normalTexture'])
        if mat.get('occlusionTexture'): maps['ao'] = texture(mat['occlusionTexture'])
        emission = mat.get('emissiveFactor', [0, 0, 0])
        if mat.get('emissiveTexture'): maps['emission'] = texture(mat['emissiveTexture'])
        # glTF factors are linear; this renderer's material colour is sRGB,
        # decoded by its shader alongside the source texture. Preserve alpha.
        factor = pbr.get('baseColorFactor', [1, 1, 1, 1])
        color = [12.92*v if v <= .0031308 else 1.055*v**(1/2.4)-.055
            for v in factor[:3]] + factor[3:]
        materials[mat['name']] = {
            'color': color, 'textures': maps,
            'sourceProperties': {'roughness': pbr.get('roughnessFactor', 1),
                'gltfTexCoord': material_uv_sets[mat['name']],
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
    bpy.ops.import_scene.gltf(filepath=str(import_source))
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
        # Preserve the authored horizontal layout and vertical rotation axis.
        # The selector viewer uses an elevated camera so standing tabletop
        # consoles and flat handhelds remain readable together.
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
    overview = None
    if args.overview_max_triangles is not None:
        objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
        source_count = sum(len(o.data.polygons) for o in objects)
        minimum = sum(min(24, len(o.data.polygons)) for o in objects)
        if minimum >= args.overview_max_triangles:
            raise ValueError('Overview budget cannot retain every object')
        ratio = min(1, (args.overview_max_triangles-minimum) / source_count)
        for obj in objects:
            if len(obj.data.polygons) <= 24 or ratio == 1:
                continue
            bpy.context.view_layer.objects.active = obj
            mod = obj.modifiers.new('Console overview tessellation', 'DECIMATE')
            mod.ratio = max(ratio, 24 / len(obj.data.polygons))
            mod.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=mod.name)
        for i in images:
            source_name = gltf['images'][i].get('name')
            image = bpy.data.images.get(source_name) if source_name else None
            if image is None:
                raise ValueError(f'Cannot identify overview texture {i}')
            width, height = image.size[:]
            if max(width, height) > args.overview_texture_size:
                factor = args.overview_texture_size / max(width, height)
                image.scale(max(1, round(width*factor)), max(1, round(height*factor)))
            image.pack()
            images[i] = bytes(image.packed_file.data)
            if images[i][:8] == b'\x89PNG\r\n\x1a\n':
                replacement, original = f'texture-{i:02d}.png', names[i]
                for material in materials.values():
                    for role, value in material['textures'].items():
                        if value == original: material['textures'][role] = replacement
                names[i] = replacement
        overview = {'objects': [o.name for o in objects],
                    'sourceTriangles': source_count,
                    'decimationRatio': ratio,
                    'textureMaxDimension': args.overview_texture_size}
    frame_origin = 0
    starts = []
    for obj in bpy.context.scene.objects:
        if obj.animation_data:
            obj.animation_data.action = None
            for track in obj.animation_data.nla_tracks:
                track.mute = not animation or track.name != ('Explode' if args.cartridge_style else 'Open')
                if not track.mute: starts.extend(s.frame_start for s in track.strips)
    if animation:
        if not starts:
            raise ValueError('Imported opening action was not found')
        frame_origin = min(starts)
        bpy.context.scene.frame_set(int(frame_origin))
        bpy.context.view_layer.update()
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH' and len(o.data.polygons)>0]
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
    translations = {}
    if animation:
        for channel in animation['channels']:
            node = gltf['nodes'][channel['target']['node']]
            sampler = animation['samplers'][channel['sampler']]
            if args.cartridge_style:
                if channel['target']['path'] != 'translation' or sampler.get('interpolation','LINEAR') != 'LINEAR':
                    raise ValueError('Expected inspected translation-only cartridge assembly')
                obj = bpy.data.objects[node['name']]
                positions = values(sampler['output'])
                parent = obj.parent.matrix_world.to_3x3() if obj.parent else Matrix.Identity(3)
                keys=[]
                for time,p in zip(values(sampler['input']),positions):
                    delta=Vector(p)-Vector(positions[0])
                    vector=axis(parent@Vector((delta.x,-delta.z,delta.y)))*scale
                    keys.append([(time[0]-animation_start)/duration,*vector])
                translations[obj.name]={'keys':keys}
                continue
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
    label_aspect = None
    closed_world = {o.name: o.matrix_world.copy() for o in objects}
    for obj in objects:
        chain, motion_chain, parent = [], [], obj
        while parent:
            if parent.name in translations: motion_chain.insert(0,translations[parent.name])
            parent=parent.parent
        # glTF permits a rigid rotation directly on a mesh node as well as on
        # an empty parent. The NES lid uses the former; include its own hinge.
        parent = obj
        while parent:
            if parent.name in hinges: chain.insert(0, hinges[parent.name])
            parent = parent.parent
        mesh = obj.data
        mesh.calc_loop_triangles()
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        for index, mat in enumerate(mesh.materials):
            triangles = [t for t in mesh.loop_triangles if t.material_index == index]
            if not triangles: continue
            material = materials[mat.name]
            uv_set = material_uv_sets[mat.name]
            uv = mesh.uv_layers[uv_set].data if len(mesh.uv_layers) > uv_set else None
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
            is_label = bool(args.cartridge_style and obj.name in
                ('Replaceable front artwork', 'Replaceable wrap-over artwork'))
            if is_label and label_aspect is None:
                # UV derivatives preserve the full wrap atlas, including the
                # narrow top strip. Other shell families have different labels.
                tri = triangles[0]
                a,b,c = [obj.matrix_world @ mesh.vertices[v].co for v in tri.vertices]
                ta,tb,tc = [uv[l].uv for l in tri.loops]
                du,dv = tb-ta,tc-ta
                determinant = du.x*dv.y-du.y*dv.x
                if abs(determinant) < 1e-10:
                    raise ValueError('Replaceable label requires a nondegenerate UV mapping')
                dpdu = ((b-a)*dv.y-(c-a)*du.y)/determinant
                dpdv = ((c-a)*du.x-(b-a)*dv.x)/determinant
                label_aspect = dpdu.length/dpdv.length
            surfaces.append({'node': obj.name, 'name': mat.name,
                'role': 'label' if is_label else 'shell',
                'physicalMaterial': 'glass' if any(material['sourceProperties']['emission']) else 'source',
                'singleSided': not double_sided[mat.name], 'openingHinges': chain,
                'openingTranslations': motion_chain,
                'vertexOffset': offset, 'vertexCount': count,
                'indexOffset': indices, 'indexCount': count, 'material': material})
    animation_error = 0
    if hinges or translations:
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
                    for motion in next(s['openingTranslations'] for s in surfaces if s['node']==obj.name):
                        keys=motion['keys']; a,b=next((a,b) for a,b in zip(keys,keys[1:]) if a[0]<=progress<=b[0])
                        point += Vector(a[1:]).lerp(Vector(b[1:]),(progress-a[0])/(b[0]-a[0]))
                    expected = (axis(obj.matrix_world @ vertex.co)-center)*scale
                    animation_error = max(animation_error, (expected-point).length)
        if animation_error > .0001:
            raise ValueError(f'Converted hinge differs from source animation: {animation_error}')
    if collection or overview:
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
        manifest['sourceReference']['adaptation'] = 'All 63 original placements and vertical axis; only Display_board hidden; elevated overview camera, reduced tessellation and 256px textures; original sources retained'
    if overview:
        manifest['overviewGeometry'] = True
        manifest['sourceReference']['overview'] = overview
        manifest['sourceReference']['adaptation'] = 'All authored objects and placements retained; bounded tessellation/textures for the console selector; original source retained'
    if args.rom_set:
        manifest['romSet'] = args.rom_set
        manifest['resourceKind'] = args.resource_kind
        manifest['openingDurationMs'] = round(duration*1000) if hinges else 2000
    if args.visual_variant_id:
        manifest['visualVariantId'] = args.visual_variant_id
        manifest['resourceKind'] = args.resource_kind
        manifest['openingDurationMs'] = round(duration*1000) if hinges else 2000
    if args.edition_id:
        manifest['retailEditionId'] = args.edition_id
        manifest['resourceKind'] = 'box'
        manifest['openingDurationMs'] = round(duration*1000) if hinges else 2000
    if args.nes_standard_carton:
        extra=gltf.get('asset',{}).get('extras',{})
        if (not args.edition_id or extra.get('units')!='metres' or
                extra.get('dimensions_mm')!=[127.0,181.0,25.4] or
                not any(s['node']=='Separate foam spacer' for s in surfaces)):
            raise ValueError('Expected the reviewed standard NES carton and foam')
        manifest['nesStandardCarton']={
            'previewUnitsPerMetre':scale,'foamNode':'Separate foam spacer',
            'interiorBounds':[
                list((Vector(v)-center)*scale) for v in
                [(-.06302,.00048,-.01222),(.06302,.18052,.01222)]],
            'cardboardThicknessMetres':.00048,
            'foamDimensionsAccuracy':'Estimated visual fit, not a measured original specimen'}
        manifest['sourceReference']['preparedPrinting']=extra.get('preparedPrinting')
        manifest['sourceReference']['construction']=extra
    if args.cartridge_style:
        manifest.pop('hardwareGeometry')
        manifest.update(name='nes-reference-'+args.cartridge_style,
            cartridgeGeometry=True, cartridgeStyle=args.cartridge_style,
            motionKind='pushClick', labelAspect=label_aspect or 1,
            assemblyInspection=bool(translations), inspectionDurationMs=round(duration*1000))
        manifest['sourceReference']['previewAnimationPolicy']={'inspection':['Explode','Assemble'] if translations else []}
    original_licence = gltf.get('asset', {}).get('extras', {}).get('sketchfab', {}).get('license')
    if original_licence:
        manifest['sourceReference']['originalLicence'] = original_licence
    if pose_bounds:
        manifest['poseCenters'] = [[time, *list((point-center)*scale)] for time, point in pose_bounds]
    if gltf.get('extras', {}).get('controlRegistration'):
        manifest['sourceReference']['controlRegistration'] = gltf['extras']['controlRegistration']
    if args.launch_target:
        nodes = {s['node'] for s in surfaces}
        required = [launch['lidNode'], *launch['trayNodes'], *launch['controllerNodes']]
        required += [launch[key] for key in ('powerLedNode', 'powerNode') if launch.get(key)]
        if any(name not in nodes for name in required):
            raise ValueError('Launch calibration references absent source geometry')
        pivot = launch['lidPivot']
        if len(pivot) != 3 or any(not __import__('math').isfinite(v) for v in pivot):
            raise ValueError('Launch hinge requires a finite source-space anchor')
        manifest['launchHardware'] = {
            **launch, 'lidPivot': list((axis(Vector(pivot)) - center) * scale),
            'sourceScale': scale,
            'sourceCenter': list(center),
            'geometrySha256': manifest['geometrySha256'],
        }
        manifest['sourceReference']['parents'] = [{
            'author': launch['sourceAuthor'], 'url': launch['sourceUrl'],
            'sha256': launch['sourceSha256'],
        }]
        manifest['sourceReference']['adaptation'] = launch['adaptation']
    if args.launch_display:
        if display['screenNode'] not in {s['node'] for s in surfaces}:
            raise ValueError('Display calibration references absent screen geometry')
        manifest['launchDisplay'] = {
            **display, 'sourceScale': scale, 'sourceCenter': list(center),
            'geometrySha256': manifest['geometrySha256'],
        }
        manifest['sourceReference']['parents'] = [{
            'author': display['sourceAuthor'], 'url': display['sourceUrl'],
            'sha256': display['sourceSha256'],
        }]
        manifest['sourceReference']['adaptation'] = display['adaptation']
    args.output.mkdir(parents=True)
    (args.output/'model.mesh').write_bytes(payload)
    # A rejected/uncertain carton must not expose the normal import entry point.
    # Preserve its candidate and OCR evidence for diagnosis, not as an accepted model.
    manifest_name = 'model.pending.json' if args.resource_kind == 'box' else 'model.json'
    (args.output/manifest_name).write_text(json.dumps(manifest, indent=2), encoding='utf8')
    for i, content in images.items():
        if names[i] in used: (args.output/names[i]).write_bytes(content)
    if args.resource_kind == 'box':
        orientation_output=args.output/'text-orientation'
        result=subprocess.run([str(args.text_orientation_python),
            str(Path(__file__).with_name('verify_carton_orientation.py')),
            '--model-dir',str(args.output),'--manifest-name',manifest_name,
            '--output',str(orientation_output),'--title',args.orientation_title,
            '--language',args.orientation_language])
        if result.returncode != 0:
            raise ValueError('Carton text orientation requires review; no accepted model.json was written')
        report_bytes=(orientation_output/'report.json').read_bytes()
        report=json.loads(report_bytes)
        if report['status']!='verified' or report['geometrySha256']!=manifest['geometrySha256'] or report['textureFiles']!=textures:
            raise ValueError('Carton orientation evidence differs from the conversion')
        manifest['cartonTextOrientation']={
            'status':'verified','reportSha256':hashlib.sha256(report_bytes).hexdigest(),
            'validatedBaseManifestSha256':report['modelManifestSha256'],
            'geometrySha256':manifest['geometrySha256'],
            'frontSurfaceIndex':report['panels']['front']['surfaceIndex'],
            'backSurfaceIndex':report['panels']['back']['surfaceIndex'],
            'clockwiseCorrectionDegrees':0,
            'evidence':'text-orientation/report.json',
        }
        (args.output/'model.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    print('CONSOLE_ADAPTED '+json.dumps({'triangles': sum(s['indexCount']//3 for s in surfaces),
        'surfaces': len(surfaces), 'textures': len(textures), 'sourceSha256': manifest['sourceReference']['sha256']}))


if __name__ == '__main__': main()
