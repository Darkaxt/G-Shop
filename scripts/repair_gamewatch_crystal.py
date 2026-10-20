"""Repair owner reconstruction's rear battery solids crossing a Crystal window.

Run in Blender. Originals remain untouched; export an independently versioned GLB.
The source glass aperture defines the cut, without adding simulated LCD artwork.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Preserve original and previous reconstruction outputs')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    glass = bpy.data.objects.get('See_through_LCD_glass')
    if glass is None:
        raise ValueError('Expected inspected Crystal Screen reconstruction')
    points = [glass.matrix_world @ v.co for v in glass.data.vertices]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    targets = [bpy.data.objects.get(n) for n in ('Rear_battery_cover', 'Battery_latch')]
    if any(o is None for o in targets):
        raise ValueError('Source differs from the diagnosed battery assembly')
    before = {o.name: len(o.data.polygons) for o in targets}
    # The existing shell and printed surround already have this window. The
    # generic rear battery assembly was the only geometry placed across it.
    bpy.ops.mesh.primitive_cube_add(location=((low.x+high.x)/2, 0, (low.z+high.z)/2))
    cutter = bpy.context.object
    cutter.name = 'Temporary_aperture_tool'
    cutter.dimensions = (high.x-low.x, .05, high.z-low.z)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for obj in targets:
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new('Keep source Crystal aperture clear', 'BOOLEAN')
        modifier.operation = 'DIFFERENCE'
        modifier.solver = 'EXACT'
        modifier.object = cutter
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    # Ray-test a grid inside the actual aperture against every opaque object.
    # This proves the cause is removed rather than hidden by glass/shader alpha.
    hits = []
    for ix in range(1, 20):
        for iz in range(1, 12):
            point = Vector((low.x+(high.x-low.x)*ix/20, -.1,
                            low.z+(high.z-low.z)*iz/12))
            for obj in list(bpy.context.scene.objects):
                if obj.type != 'MESH' or obj == glass or not obj.data.polygons:
                    continue
                inverse = obj.matrix_world.inverted()
                hit, _, _, _ = obj.ray_cast(inverse @ point,
                    (inverse.to_3x3() @ Vector((0, 1, 0))).normalized())
                if hit:
                    hits.append({'object': obj.name, 'ray': list(point)})
    if hits:
        raise ValueError(f'Opaque geometry still obstructs aperture: {hits[:5]}')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Empty latch entirely inside the aperture has no physical surviving part.
    for obj in targets:
        if not obj.data.polygons:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.export_scene.gltf(filepath=str(args.output), export_format='GLB',
                              export_animations=False, export_yup=True)
    receipt = {'blender': bpy.app.version_string,
        'originalSha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
        'repairedSha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
        'cause': 'Generic rear battery cover and latch cross the clear LCD aperture',
        'repair': 'Boolean subtract the existing glass aperture from those rear solids',
        'apertureBoundsBlender': [list(low), list(high)],
        'originalTargetPolygons': before, 'clearGridRays': 209,
        'opaqueHitsAfter': len(hits), 'gameplayAdded': False}
    args.output.with_suffix('.repair.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
    print('CRYSTAL_REPAIRED ' + json.dumps(receipt))


if __name__ == '__main__':
    main()
