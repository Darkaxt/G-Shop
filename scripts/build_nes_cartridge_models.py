"""Blender authoring of reusable NES retail shell references.

Run Blender --background --factory-startup --python this_file -- --output DIR.
Photo proportions/details: https://www.thelegendofnes.com/cartridge-design and
its original unlicensed publisher photographs. Dimensions of nonstandard shells
and internal PCB electronics are illustrative, not measured per-game replicas.
No game artwork or reference photographs are embedded in these models.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
import bmesh
from mathutils import Vector


STYLES = ['nintendo-3-gray', 'nintendo-5-gray', 'nintendo-3-gold',
          'nintendo-5-gold', 'tengen', 'camerica-gold', 'camerica-silver',
          'dreams-blue', 'dreams-black', 'ave-square', 'ave-angle',
          'active-clear', 'aladdin']


def material(name, color, roughness=.45, metallic=0, transmission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Transmission Weight'].default_value = transmission
    bsdf.inputs['IOR'].default_value = 1.49
    m['runtime'] = json.dumps({'color': [*color, 1], 'textures': {},
        'sourceProperties': {'roughness': roughness, 'metallic': metallic,
            'transmission': transmission, 'ior': 1.49, 'thickness': .015}})
    return m


def box(name, location, dimensions, mat, bevel=.0006):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    o = bpy.context.object
    o.name = name
    o.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = o.modifiers.new('Moulded edge radius', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat)
    return o


def prism(name, outline, front, back, mat, bevel=.0007):
    n = len(outline)
    vertices = [(x,y,z) for y in (front,back) for x,z in outline]
    faces = [tuple(range(n-1,-1,-1)), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    if bevel:
        mod = obj.modifiers.new('Moulded perimeter', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def screw(x,z,y,mat,slotmat, prefix='Back'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=.0022,
        depth=.0009, location=(x,y,z), rotation=(math.pi/2,0,0))
    o = bpy.context.object
    o.name = prefix+' recessed fastener'
    o.data.materials.append(mat)
    box(prefix+' screw slot', (x,y+.00048,z), (.003,.00015,.00045),slotmat,.0001)


def label(x,z,width,height,y,mat):
    o = prism('Replaceable game label', [(x-width/2,z-height/2),
        (x+width/2,z-height/2),(x+width/2,z+height/2),(x-width/2,z+height/2)],
        y,y+.00008,mat,.00015)
    o['replaceableLabel'] = True
    o['labelRect'] = [x-width/2,z-height/2,width,height]
    return o


def pcb(width,height,bottom,board,pins,chips):
    box('PCB reference board',(0,0,bottom+height/2),(width,.0018,height),board,.0004)
    for side in (-1,1):
        for i in range(36):
            x=(i-17.5)*width/38
            box('72-pin connector contact',(x,side*.00105,bottom+.0045),
                (width/52,.00015,.008),pins,.00008)
    for i,(x,z) in enumerate([(-width*.22,bottom+height*.55),(width*.22,bottom+height*.69)]):
        box('Illustrative IC '+str(i),(x,-.002,z),(width*.31,.003,height*.22),chips,.0005)
        for j in range(8):
            for sign in (-1,1):
                box('IC leg',(x+sign*width*.17,-.0018,z+(j-3.5)*height*.021),
                    (.004,.0004,height*.01),pins,.00005)


def cartridge(style):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    black = material('Recesses',(.025,.029,.033),.64)
    metal = material('Fastener metal',(.46,.48,.49),.27,.85)
    board = material('Illustrative PCB green',(.025,.21,.10),.47)
    pins = material('Connector gold',(.71,.46,.12),.25,.8)
    paper = material('Dynamic game label',(.82,.80,.74),.75)
    color = ((.43,.44,.46) if style.startswith('nintendo') else
        (.63,.38,.075) if style.endswith('gold') else
        (.63,.65,.67) if style.endswith('silver') else
        (.16,.46,.76) if style=='dreams-blue' else
        (.72,.78,.81) if style=='active-clear' else (.045,.05,.06))
    if style.startswith('nintendo') and style.endswith('gold'): color=(.63,.38,.075)
    shell=material('Shell '+style,color,.10 if style=='active-clear' else .31 if 'gold' in style or 'silver' in style else .46,
        .77 if 'gold' in style or 'silver' in style else 0,
        1 if style=='active-clear' else 0)
    width,height,depth=.120,.133,.017
    outline=[(-.060,.010),(-.054,.010),(-.054,0),(.054,0),(.054,.010),
        (.060,.010),(.060,.133),(-.060,.133)]
    if style=='tengen':
        height=.130
        outline=[(-.060,0),(.060,0),(.060,.102),(.054,.102),(.054,.130),(-.054,.130),(-.054,.102),(-.060,.102)]
    elif style.startswith('camerica'):
        outline=[(-.060,0),(-.043,0),(-.043,.009),(.043,.009),(.043,0),(.060,0),(.060,.106),(.052,.106),(.052,.133),(-.052,.133),(-.052,.106),(-.060,.106)]
    elif style.startswith('ave'):
        outline=[(-.060,.012),(-.054,.012),(-.054,0),(.054,0),(.054,.012),(.060,.012),(.060,.133)]
        outline += [(-.047,.133),(-.060,.120)] if style=='ave-angle' else [(-.060,.133)]
    elif style.startswith('dreams'):
        outline=[(-.060,0),(.060,0),(.060,.110),(.053,.133),(-.053,.133),(-.060,.110)]
    elif style=='active-clear':
        outline=[(-.060,.009),(-.054,.009),(-.054,0),(.054,0),(.054,.009),(.060,.009),(.060,.104),(.053,.104),(.053,.133),(-.053,.133),(-.053,.104),(-.060,.104)]
    elif style=='aladdin':
        outline=[(-.060,0),(-.047,0),(-.039,.022),(.039,.022),(.047,0),(.060,0),(.060,.092),(.049,.106),(.049,.133),(-.049,.133),(-.049,.106),(-.060,.092)]
    # Separate thin covers and perimeter walls leave a real internal cavity.
    front=prism('Front shell half',outline,-depth/2,-depth/2+.0013,shell)
    back=prism('Back shell half',outline,depth/2-.0013,depth/2,shell)
    for (x1,z1),(x2,z2) in zip(outline,outline[1:]+outline[:1]):
        if max(z1,z2)<.012: continue
        dx,dz=x2-x1,z2-z1
        o=box('Perimeter wall',((x1+x2)/2,0,(z1+z2)/2),
              (.0015,depth-.0015,math.hypot(dx,dz)),shell,.0003)
        o.rotation_euler.y=math.atan2(dx,dz)
    pcb(.094,.079,.004,board,pins,black)
    if style.startswith('nintendo'):
        for i in range(31):
            box('Front grip rib',(-.027,-.0091,.025+i*.00325),(.024,.001,.0015),shell,.0003)
        for x in (-.056,.056):
            box('Side guide rail',(x,-.009,.072),(.002,.001,.116),shell,.00035)
        # Three-screw uses two lower corners and one central rear screw.
        positions=[(-.052,.019),(.052,.019),(0,.061)]
        if '-5-' in style: positions=[(-.052,.019),(.052,.019),(-.052,.119),(.052,.119),(0,.061)]
        else:
            for x in (-.053,.053): box('Upper retention hook',(x,0,.132),(.007,.009,.003),shell,.0004)
        for x,z in positions: screw(x,z,.0091,metal,black)
        label(.018,.079,.071,.096,-.00925,paper)
        for i in range(5): box('Rear grip rib',(.029,.009,.121-i*.003),(.025,.0007,.0014),shell,.0002)
    elif style.startswith('camerica'):
        label(0,.073,.067,.090,-.00925,paper)
        for i in range(6): box('Lower horizontal grip',(0,-.009,.016+i*.0023),(.067,.0009,.0012),shell,.0002)
        for i in range(4):
            width=.012+i*.011
            box('Upper triangular grip',(0,-.009,.126-i*.004),
                (width,.0009,.0012),shell,.0002)
        box('Back compatibility-switch recess',(0,.009,.026),(.024,.0006,.013),black,.001)
        box('Compatibility switch lever',(-.006,.010,.026),(.006,.002,.010),shell,.0005)
        for x in (-.05,.05): screw(x,.018,.009,metal,black)
    elif style=='tengen':
        label(0,.048,.092,.089,-.00925,paper)
        for i in range(3):
            prism('Moulded arrow grip '+str(i),[(-.008-i*.007,.108-i*.006),
                (.008+i*.007,.108-i*.006),(0,.118-i*.006)],-.009,-.0084,shell,.0003)
        for x in (-.056,.056):
            for j in range(8): box('Side grip',(x,0,.022+j*.008),(.002,.015,.002),shell,.0003)
        for x in (-.05,.05): screw(x,.018,.009,metal,black)
    elif style.startswith('ave'):
        label(0,.076,.071,.090,-.00925,paper)
        for i in range(7):
            w=.02+i*.006
            box('Lower tapered grip',(0,-.009,.015+i*.0022),(w,.0009,.0012),shell,.0002)
    elif style=='active-clear':
        label(0,.079,.069,.077,-.00925,paper)
        for x,z in [(-.048,.015),(.048,.015),(0,.112)]: screw(x,z,.0091,metal,black)
        for i in range(7):
            box('PCB reference trace',(-.02+i*.006,-.0011,.041+i*.004),(.048,.00012,.0004),pins,.00005)
    elif style=='aladdin':
        # The base and miniature are separate objects with their own contours.
        cut=box('Temporary receptacle cutter',(0,0,.056),(.080,.030,.045),black,0)
        for obj in (front,back):
            bpy.context.view_layer.objects.active=obj
            mod=obj.modifiers.new('Compact cartridge receptacle','BOOLEAN')
            mod.operation='DIFFERENCE'; mod.object=cut
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cut,do_unlink=True)
        mini=prism('Removable compact cartridge',[(-.037,.029),(.037,.029),(.034,.082),(-.034,.082)],-.010,.008,shell,.0015)
        mini['separateRemovablePart']=True
        label(0,.058,.064,.039,-.0103,paper)
        box('Base badge',(0,-.009,.111),(.082,.0006,.024),black,.002)
    else:
        label(0,.076,.080,.089,-.00925,paper)
        for x in (-.052,.052):
            for i in range(8): box('Moulded side grip',(x,-.009,.024+i*.010),(.007,.001,.003),shell,.0005)
    return paper


def export_runtime(directory, style):
    directory.mkdir(parents=True,exist_ok=False)
    bpy.ops.wm.save_as_mainfile(filepath=str(directory/'source.blend'))
    bpy.ops.export_scene.gltf(filepath=str(directory/'source.glb'), export_format='GLB')
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    def axis(v): return Vector((v.x,v.z,-v.y))
    points=[axis(o.matrix_world@v.co) for o in objects for v in o.data.vertices]
    low=Vector([min(p[a] for p in points) for a in range(3)])
    high=Vector([max(p[a] for p in points) for a in range(3)])
    center=(low+high)/2; scale=2/max(high-low)
    groups={}
    aspect=1
    for obj in objects:
        mesh=obj.data; mesh.calc_loop_triangles()
        normal_matrix=obj.matrix_world.to_3x3().inverted().transposed()
        is_label=obj.get('replaceableLabel',False)
        if is_label:
            lx,lz,lw,lh=obj['labelRect']; aspect=lw/lh
        for tri in mesh.loop_triangles:
            mat=obj.material_slots[tri.material_index].material
            role='label' if is_label and (normal_matrix@tri.normal).y < -.9 else 'body'
            verts=groups.setdefault((mat.name,role),[])
            for index in tri.vertices:
                original=obj.matrix_world@mesh.vertices[index].co
                p=(axis(original)-center)*scale
                n=axis(normal_matrix@tri.normal).normalized()
                uv=((original.x-lx)/lw,(lz+lh-original.z)/lh) if role=='label' else (0,0)
                verts.append((*p,*n,*uv))
    payload=bytearray(); surfaces=[]
    for (name,role),vertices in groups.items():
        start=len(payload)
        for v in vertices: payload.extend(struct.pack('<8f',*v))
        indices=len(payload)
        for i in range(len(vertices)): payload.extend(struct.pack('<I',i))
        surfaces.append({'name':name,'node':name,'role':role,'singleSided':False,
            'physicalMaterial':'source',
            'vertexOffset':start,'vertexCount':len(vertices),'indexOffset':indices,
            'indexCount':len(vertices),'material':json.loads(bpy.data.materials[name]['runtime'])})
    manifest={'name':'nes-retail-'+style,'system':'nes','cartridgeStyle':style,
        'privateImport':True,'cartridgeGeometry':True,'motionKind':'pushClick',
        'bounds':list((high-low)*scale),'sourceWidth':(high.x-low.x)*scale,
        'labelAspect':aspect,'frontSign':1,'textureFiles':{},
        'geometrySha256':hashlib.sha256(payload).hexdigest(),'surfaces':surfaces,
        'sourceReference':{'author':'G-Shop original parametric reference models',
            'url':'https://www.thelegendofnes.com/cartridge-design',
            'licence':'local-import-only',
            'originalLicence':'Original parametric geometry; private reference use',
            'sha256':hashlib.sha256((directory/'source.glb').read_bytes()).hexdigest(),
            'limitations':'Nonstandard proportions are photograph-derived; PCB/components are illustrative, not a claimed per-ROM board.'}}
    (directory/'model.mesh').write_bytes(payload)
    (directory/'model.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    return {'style':style,'triangles':sum(len(v)//3 for v in groups.values()),'surfaces':len(surfaces),'geometrySha256':manifest['geometrySha256']}


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    receipts=[]
    for style in STYLES:
        cartridge(style)
        receipts.append(export_runtime(args.output/style,style))
        print('NES_SHELL_AUTHORED '+json.dumps(receipts[-1]),flush=True)
    (args.output/'authoring-receipts.json').write_text(json.dumps(receipts,indent=2),encoding='utf-8')


if __name__=='__main__': main()
