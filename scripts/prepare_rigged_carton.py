"""Adapt the owner's rigged cardboard GLB, without copying its original printing.

Blender --background --factory-startup --python this_file -- --source FILE --output DIR
The Open clip drives real hierarchical flap hinges; the cinematic is separate.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector, Quaternion, Matrix


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Choose an absent output directory; preserve earlier conversions')
    raw = args.source.read_bytes()
    size, tag = struct.unpack_from('<II', raw, 12)
    data = json.loads(raw[20:20+size])
    binary = memoryview(raw)[28+size:]
    def values(index):
        a = data['accessors'][index]
        view = data['bufferViews'][a['bufferView']]
        width = {'SCALAR': 1, 'VEC4': 4}[a['type']]
        if a['componentType'] != 5126 or 'sparse' in a:
            raise ValueError('Expected inspected float animation accessors')
        start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = view.get('byteStride', width*4)
        return [struct.unpack_from('<'+'f'*width, binary, start+i*stride) for i in range(a['count'])]
    animation = next(a for a in data['animations'] if a['name'] == 'Open')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    objects = {o.name:o for o in bpy.data.objects}
    meshes = [o for o in objects.values() if o.type == 'MESH']
    if len(meshes) != 13 or 'Top_lid_hinge' not in objects:
        raise ValueError('Source differs from the inspected thirteen-part carton')
    for obj in objects.values():
        if obj.animation_data:
            obj.animation_data.action = None
            for track in obj.animation_data.nla_tracks:
                track.mute = track.name != 'Open'
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    def axis(p): return Vector((p.x, p.z, -p.y))
    points = [axis(o.matrix_world @ v.co) for o in meshes for v in o.data.vertices]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    center, half = (low+high)/2, (high-low)/2
    def normalized(p): return [(p[a]-center[a])/half[a] for a in range(3)]
    hinges = {}
    for channel in animation['channels']:
        node = data['nodes'][channel['target']['node']]
        sampler = animation['samplers'][channel['sampler']]
        if channel['target']['path'] != 'rotation' or sampler.get('interpolation','LINEAR') != 'LINEAR':
            raise ValueError('Expected inspected linear quaternion hinges')
        obj = objects[node['name']]
        base = Quaternion((node['rotation'][3], *node['rotation'][:3]))
        keys = []
        local_axis = None
        duration = values(sampler['input'])[-1][0]
        for time, q in zip(values(sampler['input']), values(sampler['output'])):
            delta = Quaternion((q[3], *q[:3])) @ base.inverted()
            if delta.w < 0: delta.negate()
            if delta.angle > .00001 and local_axis is None: local_axis = delta.axis.copy()
            keys.append((time[0]/duration, delta))
        local_axis = local_axis or Vector((1,0,0))
        parent = obj.parent.matrix_world.to_3x3() if obj.parent else Matrix.Identity(3)
        direction = axis(parent @ local_axis).normalized()
        hinges[obj.name] = {'pivot':normalized(axis(obj.matrix_world.translation)),
            'axis':list(direction), 'keys':[[t, q.angle * (-1 if q.axis.dot(local_axis)<0 else 1)] for t,q in keys]}
    faces = {'01_Front':0, '04_Back':1, '03_Right_spine':2, '02_Left_spine':3,
             'Top_lid':4, 'Bottom_lid':5}
    surfaces, payload = [], bytearray()
    for obj in meshes:
        chain=[]; parent=obj.parent
        while parent:
            if parent.name in hinges: chain.insert(0,hinges[parent.name])
            parent=parent.parent
        mesh=obj.data; mesh.calc_loop_triangles()
        uv=mesh.uv_layers.active.data
        for material_index, source_material in enumerate(mesh.materials):
            triangles=[t for t in mesh.loop_triangles if t.material_index==material_index]
            if not triangles: continue
            printed = source_material.name.startswith('Printed carton')
            cell=faces.get(obj.name, 4 if 'top' in obj.name.lower() else 5)
            all_uv=[uv[i].uv for t in triangles for i in t.loops]
            u0,u1=min(p.x for p in all_uv),max(p.x for p in all_uv)
            v0,v1=min(p.y for p in all_uv),max(p.y for p in all_uv)
            offset=len(payload)
            count=0
            normal_matrix=obj.matrix_world.to_3x3().inverted().transposed()
            for tri in triangles:
                for vertex,loop in zip(tri.vertices,tri.loops):
                    p=axis(obj.matrix_world @ mesh.vertices[vertex].co)
                    normal=axis(normal_matrix @ mesh.vertices[vertex].normal)
                    normal=Vector([normal[a]*half[a] for a in range(3)]).normalized()
                    puv=uv[loop].uv
                    u=(puv.x-u0)/(u1-u0) if u1>u0 else .5
                    v=(v1-puv.y)/(v1-v0) if v1>v0 else .5
                    # Missing flap printing extends the matching lid's edge
                    # colours; do not fabricate a complete scanned flap.
                    if obj.name not in faces: v=1
                    payload.extend(struct.pack('<8f',*normalized(p),*normal,(cell%3+u)/3,(cell//3+v)/2))
                    count+=1
            index_offset=len(payload)
            for i in range(count): payload.extend(struct.pack('<I',i))
            color=([1,1,1,1] if printed else [.74,.70,.62,1] if material_index==1 else [.57,.49,.36,1])
            surfaces.append({'node':obj.name,'name':source_material.name,'role':'label' if printed else 'shell',
                'vertexOffset':offset,'vertexCount':count,'indexOffset':index_offset,'indexCount':count,
                'atlasCell':cell if printed else None,'openingHinges':chain,
                'material':{'color':color,'textures':{},'sourceProperties':{'roughness':1,'metallic':0}}})
    result={'name':'gba-rigged-carton-v1','packagingGeometry':True,'privateImport':True,
        'motionKind':'packaging','bounds':[2,2,2],'sourceWidth':2,'labelAspect':1.5,
        'frontSign':1,'canOpen':True,'openingDurationMs':round(duration*1000),'maxOpenRadians':0,'sourceRootTransform':[1,0,0,0,1,0,0,0,1],
        'geometrySha256':hashlib.sha256(payload).hexdigest(),
        'sourceReference':{'author':'Darkaxt (owner-generated model)','url':'local:owner-rigged-carton',
            'licence':'local-import-only','sha256':hashlib.sha256(raw).hexdigest(),
            'adaptation':'Original thirteen-part carton, fitted faces, Open clip hinges, original printing removed; unavailable flap printing uses lid edge colours'},
        'surfaces':surfaces}
    args.output.mkdir(parents=True)
    (args.output/'model.mesh').write_bytes(payload)
    (args.output/'model.json').write_text(json.dumps(result,indent=2),encoding='utf8')
    print('CARTON_ADAPTED '+json.dumps({'triangles':sum(s['indexCount']//3 for s in surfaces),'surfaces':len(surfaces),'hinges':len(hinges),'sha256':result['geometrySha256']}))


if __name__=='__main__': main()
