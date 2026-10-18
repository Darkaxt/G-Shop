"""Bounded geometry inventory of acquired Nintendo-era DVD case candidates.

No model is exported or marked native-verified. Missing external textures do not
establish visual suitability; this pass establishes actual parts and animation.
"""
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

root = Path(sys.argv[sys.argv.index('--') + 1])
result = []
for relative in ['dvdps2wii-case/dvd case.fbx', 'dvdgame-case/case.fbx']:
    source = root / relative
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.fbx_import(filepath=str(source))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    inventory = []
    for obj in meshes:
        points = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        inventory.append({'name': obj.name, 'parent': obj.parent.name if obj.parent else None,
            'vertices': len(obj.data.vertices), 'polygons': len(obj.data.polygons),
            'uvLayers': len(obj.data.uv_layers),
            'materials': [s.material.name if s.material else None for s in obj.material_slots],
            'bounds': [[min(p[a] for p in points) for a in range(3)],
                       [max(p[a] for p in points) for a in range(3)]]})
    result.append({'source': relative, 'meshes': inventory,
        'armatures': sum(o.type == 'ARMATURE' for o in bpy.context.scene.objects),
        'animationClips': len(bpy.data.actions), 'nativeVerified': False,
        'openingVerified': False})
output = root / 'geometry.json'
if output.exists():
    raise ValueError('Preserve prior inventory')
output.write_text(json.dumps(result, indent=2))
print('CASE_INSPECTION ' + json.dumps(result))
