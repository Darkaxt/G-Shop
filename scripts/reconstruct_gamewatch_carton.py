"""Build a private opening carton in Blender from reviewed scan panel crops.

Input JSON supplies six face images, their actual proportions and provenance.
Only the reviewed printing is used. Card caliper, hidden folds and flap motion
are inferred presentation geometry, explicitly recorded in the receipt.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector, Quaternion


def attach_clips(path, hinges):
    raw = path.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    data = json.loads(raw[20:20+length])
    binary = bytearray(raw[28+length:])

    def accessor(rows, kind):
        binary.extend(b'\0' * (-len(binary) % 4))
        start = len(binary)
        for row in rows:
            binary.extend(struct.pack('<'+'f'*len(row), *row))
        view = len(data.setdefault('bufferViews', []))
        data['bufferViews'].append({'buffer': 0, 'byteOffset': start,
                                   'byteLength': len(binary)-start})
        index = len(data.setdefault('accessors', []))
        item = {'bufferView': view, 'componentType': 5126,
                'count': len(rows), 'type': kind}
        if kind == 'SCALAR':
            item.update(min=[rows[0][0]], max=[rows[-1][0]])
        data['accessors'].append(item)
        return index

    times = accessor([[i/30] for i in range(61)], 'SCALAR')
    clips = []
    for name in ('Open', 'Close'):
        channels, samplers = [], []
        for obj, axis, angle, start, end in hinges:
            node = next(i for i, n in enumerate(data['nodes']) if n.get('name') == obj.name)
            # Blender Z-up -> glTF Y-up, matching the exported rest geometry.
            direction = Vector((axis[0], axis[2], -axis[1]))
            rows = []
            for i in range(61):
                t = i/60 if name == 'Open' else 1-i/60
                t = max(0, min(1, (t-start)/(end-start)))
                t = t*t*(3-2*t)
                q = Quaternion(direction, angle*t)
                rows.append([q.x, q.y, q.z, q.w])
            output = accessor(rows, 'VEC4')
            channels.append({'sampler': len(samplers), 'target': {'node': node, 'path': 'rotation'}})
            samplers.append({'input': times, 'output': output, 'interpolation': 'LINEAR'})
        clips.append({'name': name, 'channels': channels, 'samplers': samplers})
    data['animations'] = clips
    binary.extend(b'\0' * (-len(binary) % 4))
    data['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(data, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    path.write_bytes(struct.pack('<4sII', b'glTF', 2, 28+len(encoded)+len(binary)) +
        struct.pack('<I4s', len(encoded), b'JSON')+encoded +
        struct.pack('<I4s', len(binary), b'BIN\0')+binary)


def build(spec, output):
    if output.exists():
        raise ValueError('Use an absent output; preserve prior reconstructions')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    w, h, d = spec['proportions']
    scale = .16/max(w, h)
    w, h, d = w*scale, h*scale, d*scale
    root = bpy.data.objects.new('Scan_reconstructed_carton', None)
    bpy.context.scene.collection.objects.link(root)
    paper = bpy.data.materials.new('Inferred unprinted inner cardboard')
    paper.use_nodes = True
    p = paper.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (.57, .52, .42, 1)
    p.inputs['Roughness'].default_value = .95
    materials = {}
    for face, file in spec['images'].items():
        mat = bpy.data.materials.new('Scanned '+face)
        mat.use_nodes = True
        node = mat.node_tree.nodes.new('ShaderNodeTexImage')
        node.image = bpy.data.images.load(file)
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        mat.node_tree.links.new(node.outputs['Color'], bsdf.inputs['Base Color'])
        bsdf.inputs['Roughness'].default_value = .8
        materials[face] = mat
    meshes, hinges = [], []

    def hinge(name, pivot, axis, angle, phase):
        obj = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = root
        obj.location = pivot
        hinges.append((obj, axis, math.radians(angle), *phase))
        return obj

    def panel(name, points, normal, face=None, parent=None):
        parent = parent or root
        coordinates = [Vector(v) for v in points]
        uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
        if (coordinates[1]-coordinates[0]).cross(coordinates[2]-coordinates[0]).dot(Vector(normal)) < 0:
            coordinates.reverse()
            uv.reverse()
        # Points are authored in shared closed-pose space, including hinges.
        inverse = parent.matrix_world.inverted()
        coordinates = [inverse @ p for p in coordinates]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(coordinates, [], [list(range(4))])
        mesh.materials.append(materials.get(face, paper))
        mesh.materials.append(paper)
        layer = mesh.uv_layers.new()
        for loop in mesh.loops:
            layer.data[loop.index].uv = uv[loop.vertex_index]
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = parent
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new('Inferred 0.38 mm card', 'SOLIDIFY')
        mod.thickness = .00038
        mod.offset = -1
        mod.material_offset = 1
        mod.material_offset_rim = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
        meshes.append(obj)
        return obj

    # Each face's image is upright when viewed from outside its physical face.
    panel('Scanned_front', [(-w/2,-d/2,0),(w/2,-d/2,0),(w/2,-d/2,h),(-w/2,-d/2,h)], (0,-1,0), 'front')
    panel('Scanned_back', [(w/2,d/2,0),(-w/2,d/2,0),(-w/2,d/2,h),(w/2,d/2,h)], (0,1,0), 'back')
    if spec['opening'] == 'right':
        panel('Scanned_top', [(-w/2,-d/2,h),(w/2,-d/2,h),(w/2,d/2,h),(-w/2,d/2,h)], (0,0,1), 'top')
        panel('Scanned_bottom', [(-w/2,d/2,0),(w/2,d/2,0),(w/2,-d/2,0),(-w/2,-d/2,0)], (0,0,-1), 'bottom')
        panel('Scanned_left', [(-w/2,d/2,0),(-w/2,-d/2,0),(-w/2,-d/2,h),(-w/2,d/2,h)], (-1,0,0), 'left')
        door = hinge('Right_end_hinge', (w/2,d/2,h/2), (0,0,1), 110, (.22,.8))
        bpy.context.view_layer.update()
        panel('Scanned_right_opening_end', [(w/2,-d/2,0),(w/2,d/2,0),(w/2,d/2,h),(w/2,-d/2,h)], (1,0,0), 'right', door)
        tab = bpy.data.objects.new('Right_tuck_hinge', None)
        bpy.context.scene.collection.objects.link(tab)
        tab.parent = door
        tab.location = (0,-d+.0012,0)
        hinges.append((tab,(0,0,1),math.pi/2,0,.24))
        bpy.context.view_layer.update()
        lip = min(d*.6, w*.15)
        panel('Inferred_tuck', [(w/2-lip,-d/2+.0012,0),(w/2,-d/2+.0012,0),(w/2,-d/2+.0012,h),(w/2-lip,-d/2+.0012,h)], (0,-1,0), 'tuck', tab)
        for top in (True, False):
            z = h-.0012 if top else .0012
            obj = hinge(('Upper' if top else 'Lower')+'_dust_hinge', (w/2-.0012,0,z), (0,1,0), 110 if top else -110, (.55,1))
            bpy.context.view_layer.update()
            panel(('Upper' if top else 'Lower')+'_inferred_dust_flap', [(w/2-d*.8,-d/2+.0012,z),(w/2-.0012,-d/2+.0012,z),(w/2-.0012,d/2-.0012,z),(w/2-d*.8,d/2-.0012,z)], (0,0,1 if top else -1), parent=obj)
        extraction = [1,0,0]
    else:
        panel('Scanned_left', [(-w/2,d/2,0),(-w/2,-d/2,0),(-w/2,-d/2,h),(-w/2,d/2,h)], (-1,0,0), 'left')
        panel('Scanned_right', [(w/2,-d/2,0),(w/2,d/2,0),(w/2,d/2,h),(w/2,-d/2,h)], (1,0,0), 'right')
        panel('Scanned_bottom', [(-w/2,d/2,0),(w/2,d/2,0),(w/2,-d/2,0),(-w/2,-d/2,0)], (0,0,-1), 'bottom')
        door = hinge('Top_end_hinge', (0,d/2,h), (1,0,0), -110, (.22,.8))
        bpy.context.view_layer.update()
        panel('Scanned_top_opening_end', [(-w/2,-d/2,h),(w/2,-d/2,h),(w/2,d/2,h),(-w/2,d/2,h)], (0,0,1), 'top', door)
        tab = bpy.data.objects.new('Top_tuck_hinge', None)
        bpy.context.scene.collection.objects.link(tab)
        tab.parent = door
        tab.location = (0,-d+.0012,-.0012)
        hinges.append((tab,(1,0,0),-math.pi/2,0,.24))
        bpy.context.view_layer.update()
        lip = min(d*.6,h*.15)
        panel('Inferred_tuck', [(-w/2+.0012,-d/2+.0012,h-lip),(w/2-.0012,-d/2+.0012,h-lip),(w/2-.0012,-d/2+.0012,h-.0012),(-w/2+.0012,-d/2+.0012,h-.0012)], (0,-1,0), 'tuck', tab)
        for left in (True,False):
            x = -w/2+.0012 if left else w/2-.0012
            obj = hinge(('Left' if left else 'Right')+'_dust_hinge', (x,0,h-.0012), (0,1,0), -110 if left else 110, (.55,1))
            bpy.context.view_layer.update()
            inner = x+(d*.8 if left else -d*.8)
            panel(('Left' if left else 'Right')+'_inferred_dust_flap', [(x,-d/2+.0012,h-.0012),(inner,-d/2+.0012,h-.0012),(inner,d/2-.0012,h-.0012),(x,d/2-.0012,h-.0012)], (0,0,1), parent=obj)
        extraction = [0,1,0]
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB',
                              export_animations=False, export_yup=True)
    attach_clips(output, hinges)
    receipt = {**spec['provenance'], 'blender': bpy.app.version_string,
        'hardware': spec['hardware'], 'dimensionsInferred': True,
        'inferred': 'card caliper, hidden glue/tuck/dust folds and opening motion; no insert invented',
        'printedFaces': [f for f in spec['images']
                         if f not in spec['provenance']['inferredFaces']],
        'opening': spec['opening'], 'extractionAxis': extraction,
        'closedDimensionsMetres': [w,h,d], 'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
    output.with_suffix('.reconstruction.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    print('CARTON_RECONSTRUCTED '+json.dumps(receipt))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--spec',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args = p.parse_args(sys.argv[sys.argv.index('--')+1:])
    build(json.loads(args.spec.read_text(encoding='utf-8')),args.output)


if __name__ == '__main__':
    main()
