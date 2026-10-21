"""Extend the owner's NES collector scene without replacing its original props.

Blender --background --python this_file -- --original FILE --models PACKAGE
  --output FILE.glb. New consoles retain their own controller/cable arrangement.
All source assets and the resulting scene remain private imports.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector


def main():
    p=argparse.ArgumentParser(); p.add_argument('--original',type=Path,required=True)
    p.add_argument('--models',type=Path,required=True); p.add_argument('--output',type=Path,required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    if a.output.exists(): raise ValueError('Preserve the previous authored scene')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(a.original))
    original={o.name:o.matrix_world.copy() for o in bpy.context.scene.objects}
    case=[o for o in bpy.context.scene.objects if o.type=='MESH' and 'NES|NES_Top|' in o.name]
    points=[o.matrix_world@v.co for o in case for v in o.data.vertices]
    scale=(max(v.x for v in points)-min(v.x for v in points))/.260
    additions=[('Toploader_Nintendo_Entertainment_System-6bc1a3bc.glb',(-66,68),-.22),
        ('Famicom-2aac53b9.glb',(66,68),.22),
        ('Famicom-b3b43b5f.glb',(0,100),0)]
    sources=[]
    for filename,(x,y),yaw in additions:
        before=set(bpy.context.scene.objects)
        source=a.models/'consoles'/filename
        bpy.ops.import_scene.gltf(filepath=str(source))
        added=set(bpy.context.scene.objects)-before
        group=bpy.data.objects.new('Added console '+filename,None)
        bpy.context.collection.objects.link(group)
        for obj in added:
            if obj.parent not in added: obj.parent=group
        group.scale=(scale,)*3
        group.rotation_euler.z=yaw
        group.location=(x,y,0)
        sources.append({'file':filename,'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'placement':[x,y,0],'yaw':yaw,'scale':scale,
            'identity':'Dendy-compatible clone' if 'b3b43b5f' in filename else filename})
    bpy.context.view_layer.update()
    for name,matrix in original.items():
        assert all(abs(x-y)<1e-7 for x,y in zip(sum((list(r) for r in matrix),[]),
            sum((list(r) for r in bpy.data.objects[name].matrix_world),[]))),name
    a.output.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(a.output.with_suffix('.blend')))
    bpy.ops.export_scene.gltf(filepath=str(a.output),export_format='GLB')
    receipt={'originalSha256':hashlib.sha256(a.original.read_bytes()).hexdigest(),
        'originalObjects':len(original),'originalPlacementsPreserved':True,
        'addedConsoles':sources,'meshObjects':sum(o.type=='MESH' for o in bpy.context.scene.objects)}
    a.output.with_suffix('.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    print('NES_SCENE_EXTENDED '+json.dumps(receipt))


if __name__=='__main__': main()
