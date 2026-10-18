"""Convert the owner's Brochure book 01 export for local manual rendering.

Blender --background --factory-startup --python this_file -- --source FILE --output DIR
No original printing/textures are copied and no redistribution grant is inferred.
The source has no animation: the front cover is adapted to the viewer's manual hinge.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    raw = args.source.read_bytes()
    size, _ = struct.unpack_from('<II', raw, 12)
    asset = json.loads(raw[20:20+size])['asset']['extras']['sketchfab']
    if asset['uid'] != 'be822ca5f3d4461c8f5d8c02b7bcbaa8':
        raise ValueError('This adapter requires the inspected Brochure book 01 source')
    if args.output.exists():
        raise ValueError('Preserve existing conversion; choose a new output generation')
    args.output.mkdir(parents=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if len(objects) != 3:
        raise ValueError('Source parts differ from the inspected staples/cover/pages')
    points = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    center, half = (low+high)/2, (high-low)/2
    groups = {}
    for object_index, obj in enumerate(objects):
        mesh = obj.data
        mesh.calc_loop_triangles()
        for tri in mesh.loop_triangles:
            vertices = [obj.matrix_world @ mesh.vertices[i].co for i in tri.vertices]
            physical_normal = (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).normalized()
            # Blender Z is thickness; app Y is page height, Z points to the cover.
            vertices = [Vector(((p.x-center.x)/half.x,
                                (p.y-center.y)/half.y,
                                (p.z-center.z)/half.z)) for p in vertices]
            normal = (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).normalized()
            # Classify physical paper before normalizing thickness. Normalizing
            # the thin source first makes its curved print look like edge walls.
            hinged = object_index == 1 and physical_normal.z > .5
            face = None
            if object_index == 1 and abs(physical_normal.z) > .5:
                face = 0 if hinged else 1
            elif object_index == 2 and abs(physical_normal.z) > .5:
                face = 3  # First inside sheet remains with the page block.
            copies = [(face, vertices, normal)]
            if hinged:
                # A thin cover needs different artwork on its two physical
                # sides. Reverse winding + per-surface culling prevents the
                # mirrored outside cover from appearing inside when opened.
                copies.append((2, [p-Vector((0,0,.002)) for p in reversed(vertices)], -normal))
            for printed_face, points, direction in copies:
                key = (object_index, printed_face, hinged)
                target = groups.setdefault(key, [])
                for p in points:
                    u, v = (p.x+1)/2, (1-p.y)/2
                    if printed_face in (1, 2): u = 1-u
                    cell = printed_face or 0
                    target.append([*p, *direction,
                        (cell % 3 + max(0,min(1,u)))/3,
                        (cell // 3 + max(0,min(1,v)))/2])
    output, surfaces = bytearray(), []
    for (part, face, hinged), vertices in groups.items():
        offset = len(output)
        for v in vertices: output.extend(struct.pack('<8f', *v))
        indices = len(output)
        for i in range(len(vertices)): output.extend(struct.pack('<I', i))
        surfaces.append({'node':['staples','cover','pages'][part],
            'name':f'{part}-{face}-{int(hinged)}',
            'atlasCell':face,
            'role':'label' if face is not None else 'shell',
            'vertexOffset':offset,'vertexCount':len(vertices),
            'indexOffset':indices,'indexCount':len(vertices),
            'hinged':hinged,'pivot':[-1,0,0],'spinAxis':[0,1,0],
            'singleSided':hinged,
            'material':{'color':([.42,.42,.42,1] if part == 0 else [.8,.78,.73,1]),
                'sourceProperties':{'roughness':1,'metallic':0},'textures':{}}})
    data = {'name':'brochure-booklet-v1','packagingGeometry':True,'privateImport':True,
        'motionKind':'packaging','bounds':[2,2,2],'sourceWidth':2,'labelAspect':1.5,
        'frontSign':1,'canOpen':True,'maxOpenRadians':math.pi*.85,
        'sourceRootTransform':[1,0,0,0,1,0,0,0,1],
        'geometrySha256':hashlib.sha256(output).hexdigest(),
        'originalTriangles':77756,
        'sourceReference':{'url':asset['source_url'],'author':asset['author'],
            'licence':'local-import-only','sourceLicence':asset.get('license'),
            'sha256':hashlib.sha256(raw).hexdigest(),
            'adaptation':'Original staples/cover/pages; fitted axes; replacement page UVs; front-cover hinge; original textures removed'},
        'surfaces':surfaces}
    (args.output/'booklet.mesh').write_bytes(output)
    (args.output/'booklet.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
    print('BOOKLET_ADAPTED '+json.dumps({'triangles':sum(s['indexCount']//3 for s in surfaces),
        'surfaces':len(surfaces),'hingedSurfaces':sum(s['hinged'] for s in surfaces),
        'geometrySha256':data['geometrySha256'],'sourceSha256':data['sourceReference']['sha256']}))


if __name__ == '__main__': main()
