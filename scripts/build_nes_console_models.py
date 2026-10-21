"""Private NES-001 extraction and photo-proportioned NES-101 reference model.

Blender --background --python this_file -- --source original.glb --output DIR
Original scene stays unchanged; no third-party geometry enters the public APK.
NES-101 proportions follow the collector photograph, not an engineering scan.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

spec=importlib.util.spec_from_file_location('nes_parts',Path(__file__).with_name('build_nes_cartridge_models.py'))
parts=importlib.util.module_from_spec(spec); spec.loader.exec_module(parts)


def cylinder(name,location,radius,depth,mat,rotation=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=radius,depth=depth,
        location=location,rotation=rotation)
    o=bpy.context.object; o.name=name; o.data.materials.append(mat)
    bevel=o.modifiers.new('Moulded rim','BEVEL'); bevel.width=.0008; bevel.segments=3
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return o


def text(body,location,size,mat,rotation=(0,0,0)):
    data=bpy.data.curves.new('Moulded identification','FONT')
    data.body=body; data.size=size; data.align_x='CENTER'; data.extrude=.00004
    o=bpy.data.objects.new(body,data); bpy.context.collection.objects.link(o)
    o.location=location; o.rotation_euler=rotation; o.data.materials.append(mat)
    return o


def save(path):
    path.parent.mkdir(parents=True,exist_ok=True)
    for o in list(bpy.context.scene.objects):
        if o.type in ('CURVE','FONT'):
            bpy.ops.object.select_all(action='DESELECT'); o.select_set(True)
            bpy.context.view_layer.objects.active=o; bpy.ops.object.convert(target='MESH')
    bpy.ops.wm.save_as_mainfile(filepath=str(path.with_suffix('.blend')))
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB')


def top_loader(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ivory=parts.material('NES-101 ivory',(.72,.70,.64),.42)
    dark=parts.material('Dark lower shell',(.085,.087,.09),.51)
    black=parts.material('Ports and recesses',(.018,.019,.022),.62)
    red=parts.material('Power and A-B red',(.62,.015,.025),.33)
    metal=parts.material('Connector metal',(.50,.52,.53),.25,.8)
    parts.box('Lower housing',(0,0,.009),(.177,.153,.018),dark,.006)
    parts.box('Upper housing',(0,0,.024),(.175,.151,.028),ivory,.009)
    parts.box('Left control terrace',(-.036,-.022,.038),(.098,.103,.021),ivory,.005)
    parts.box('Right controller terrace',(.054,-.022,.042),(.064,.104,.030),ivory,.007)
    barrel=cylinder('Raised rear cartridge saddle',(0,.043,.041),.026,.153,ivory,(0,math.pi/2,0))
    cutter=parts.box('Slot cutter',(0,.043,.065),(.122,.010,.037),black,0)
    bpy.context.view_layer.objects.active=barrel
    mod=barrel.modifiers.new('Real cartridge slot','BOOLEAN'); mod.operation='DIFFERENCE'; mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter,do_unlink=True)
    parts.box('Cartridge slot interior',(0,.043,.046),(.120,.008,.019),black,.0005)
    for x in (-.045,.045):
        parts.box('Controller port recess',(x,-.075,.022),(.032,.004,.019),black,.002)
        for i in range(7):
            cylinder('Controller socket contact',(x+(i%4-1.5)*.005,-.077,.020+(i//4)*.005),
                     .0012,.0018,metal,(math.pi/2,0,0))
    cylinder('Power switch',(-.049,-.032,.048),.010,.031,red,(0,math.pi/2,0))
    cylinder('Reset button',(-.022,-.032,.048),.010,.021,dark,(0,math.pi/2,0))
    text('POWER',(-.049,-.031,.0585),.004,ivory)
    text('RESET',(-.022,-.031,.0585),.004,ivory)
    text('Nintendo',(.054,-.007,.058),.007,dark)
    text('Nintendo\nENTERTAINMENT\nSYSTEM',(-.032,-.060,.050),.005,dark)
    for x in (-.067,.067):
        for y in (-.054,.054): cylinder('Rubber foot',(x,y,.001),.008,.002,black)
    for i in range(14):
        parts.box('Rear ventilation slot',(-.060+i*.009,.074,.020),(.005,.002,.014),black,.0003)
    cylinder('RF output',(.052,.079,.020),.0055,.010,metal,(math.pi/2,0,0))
    cylinder('Power jack',(.069,.079,.020),.004,.008,black,(math.pi/2,0,0))
    # Dogbone controller front is first built upright, then laid face up.
    before=set(bpy.context.scene.objects)
    outline=[]
    for i in range(17):
        angle=math.pi/2+math.pi*i/16
        outline.append((-.043+.026*math.cos(angle),.026+.026*math.sin(angle)))
    outline.append((0,.009))
    for i in range(17):
        angle=-math.pi/2+math.pi*i/16
        outline.append((.043+.026*math.cos(angle),.026+.026*math.sin(angle)))
    outline.append((0,.043))
    parts.prism('NES-003 dogbone controller',outline,-.008,.008,ivory,.003)
    for dim in [(.009,.002,.028),(.028,.002,.009)]:
        parts.box('D-pad',(-.043,-.010,.026),dim,black,.001)
    for x,z in [(.034,.019),(.051,.032)]:
        cylinder('Controller A-B button',(x,-.010,z),.006,.004,red,(math.pi/2,0,0))
    for x in (-.010,.010): parts.box('Select-start',(x,-.010,.019),(.011,.003,.004),dark,.002)
    text('Nintendo',(0,-.010,.040),.006,red,(math.pi/2,0,0))
    parent=bpy.data.objects.new('Dogbone placement',None); bpy.context.collection.objects.link(parent)
    for o in set(bpy.context.scene.objects)-before-{parent}: o.parent=parent
    parent.rotation_euler.x=-math.pi/2; parent.location=(0,-.160,.012)
    curve=bpy.data.curves.new('Controller cable','CURVE'); curve.dimensions='3D'; curve.bevel_depth=.0017; curve.bevel_resolution=2
    spline=curve.splines.new('BEZIER'); spline.bezier_points.add(3)
    for p,v in zip(spline.bezier_points,[(-.045,-.079,.022),(-.097,-.116,.008),(-.080,-.188,.008),(0,-.134,.012)]):
        p.co=v; p.handle_left_type=p.handle_right_type='AUTO'
    cord=bpy.data.objects.new('Controller cable',curve); bpy.context.collection.objects.link(cord); cord.data.materials.append(black)
    save(path)


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--source',type=Path,required=True); parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if args.output.exists(): raise ValueError('Choose an absent authoring output')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    removed=[]
    for obj in list(bpy.context.scene.objects):
        if obj.type=='MESH' and not obj.name.startswith(('NES|NES_','NES_Controller|','Controller_Plug|','Controller_Cord')):
            removed.append(obj.name); bpy.data.objects.remove(obj,do_unlink=True)
    save(args.output/'front-loader/source.glb')
    top_loader(args.output/'top-loader/source.glb')
    (args.output/'provenance.json').write_text(json.dumps({
        'front-loader':{'author':'Rusty Hardy','source':'https://sketchfab.com/3d-models/ad1ba0a577c44f47be224084eea5965d','adaptation':'Private isolated console/controller; original full scene retained','excludedSceneProps':removed},
        'top-loader':{'author':'G-Shop original photo-proportioned reference','source':'https://www.thelegendofnes.com/ntsc-pal','limitations':'Photo-proportioned exterior; no claim of engineering-exact dimensions or internal electronics.'}},indent=2),encoding='utf-8')


if __name__=='__main__': main()
