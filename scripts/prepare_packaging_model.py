"""Blender adapter for a reviewed cardboard mesh and six replaceable game faces.

Run Blender --background --factory-startup --python this_file -- --source ...
Original mesh vertices/creases are retained; source print/lighting is not reused.
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
    parser.add_argument('--source-url', required=True)
    parser.add_argument('--author', required=True)
    parser.add_argument('--licence', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Preserve existing model output; use a new generation')
    args.output.mkdir(parents=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    points = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    center, extent = (low + high) / 2, high - low
    # A closed box's shortest dimension is depth. The two printed axes become
    # portrait width/height; per-console aspect is applied by the viewer later.
    axes = sorted(range(3), key=lambda a: extent[a], reverse=True)
    axis_y, axis_x, axis_z = axes
    ordered = [axis_x, axis_y, axis_z]
    inversions = sum(ordered[i] > ordered[j] for i in range(3) for j in range(i + 1, 3))
    handedness = -1 if inversions % 2 else 1
    def point(p):
        p = p - center
        return Vector((2 * p[axis_x] / extent[axis_x],
            2 * p[axis_y] / extent[axis_y], handedness * 2 * p[axis_z] / extent[axis_z]))
    groups = {name: [] for name in ['front', 'back', 'left', 'right', 'top', 'bottom']}
    for obj in objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        for triangle in mesh.loop_triangles:
            vertices = [point(obj.matrix_world @ mesh.vertices[i].co) for i in triangle.vertices]
            normal = (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).normalized()
            axis = max(range(3), key=lambda a: abs(normal[a]))
            role = (('right' if normal.x > 0 else 'left') if axis == 0 else
                ('top' if normal.y > 0 else 'bottom') if axis == 1 else
                ('front' if normal.z > 0 else 'back'))
            for p in vertices:
                if role == 'front': u, v = (p.x + 1) / 2, (1 - p.y) / 2
                elif role == 'back': u, v = (1 - p.x) / 2, (1 - p.y) / 2
                elif role == 'left': u, v = (p.z + 1) / 2, (1 - p.y) / 2
                elif role == 'right': u, v = (1 - p.z) / 2, (1 - p.y) / 2
                elif role == 'top': u, v = (p.x + 1) / 2, (1 - p.z) / 2
                else: u, v = (p.x + 1) / 2, (p.z + 1) / 2
                face = list(groups).index(role)
                groups[role].append([*p, *normal,
                    ((face % 3) + max(0, min(1, u))) / 3,
                    ((face // 3) + max(0, min(1, v))) / 2])
    data, surfaces = bytearray(), []
    for role, vertices in groups.items():
        if not vertices:
            raise ValueError('Source does not contain all six box directions')
        offset = len(data)
        for v in vertices:
            data.extend(struct.pack('<8f', *v))
        indices = len(data)
        for i in range(len(vertices)):
            data.extend(struct.pack('<I', i))
        surfaces.append({'node': 'cardboard', 'name': role, 'role': 'label',
            'vertexOffset': offset, 'vertexCount': len(vertices),
            'indexOffset': indices, 'indexCount': len(vertices), 'hinged': False,
            'material': {'color': [.34, .34, .34, 1],
                'sourceProperties': {'roughness': 1, 'metallic': 0}, 'textures': {}}})
    manifest = {'name': 'cardboard-scan-v1', 'packagingGeometry': True,
        'motionKind': 'packaging', 'bounds': [2, 2, 2], 'sourceWidth': 2,
        'labelAspect': 1.5, 'frontSign': 1, 'canOpen': False,
        'sourceRootTransform': [1, 0, 0, 0, 1, 0, 0, 0, 1],
        'geometrySha256': hashlib.sha256(data).hexdigest(),
        'sourceReference': {'url': args.source_url, 'author': args.author,
            'licence': args.licence, 'sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
            'adaptation': 'axis-normalized original mesh; six planar face UVs; source textures removed'},
        'sourceBounds': [list(low), list(high)], 'axes': [axis_x, axis_y, axis_z],
        'surfaces': surfaces}
    (args.output / 'cardboard.mesh').write_bytes(data)
    (args.output / 'cardboard.json').write_text(json.dumps(manifest, indent=2))
    print('PACKAGING_ADAPTED ' + json.dumps({'sourceBounds': manifest['sourceBounds'],
        'axes': manifest['axes'], 'triangles': sum(len(v) for v in groups.values()) // 3,
        'faces': {name: len(v) // 3 for name, v in groups.items()},
        'sha256': manifest['geometrySha256']}))


main()
