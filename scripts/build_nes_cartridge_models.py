"""Blender authoring of reusable NES retail shell references.

Run Blender --background --factory-startup --python this_file -- --output DIR.
Photo proportions/details: https://www.thelegendofnes.com/cartridge-design and
its original unlicensed publisher photographs. The Dendy shell (the yellow
60-pin Famicom-format cartridge sold in Russia; Subor carts share it) follows
owner-supplied photographs and public listing photos of real cartridges. Dimensions of nonstandard shells
and internal PCB electronics are illustrative, not measured per-game replicas.
No game artwork or reference photographs are embedded in these models; the
Dendy back panel texture is a flat redraw (scripts/make_dendy_back_panel.py)
unless --back-panel supplies a privately built one (with --back-panel-credit).
The Dendy board is modelled from scripts/dendy_pcb.py (a measured layout of a
photographed Dendy DIP board); pass its rendered artwork with --pcb-textures.
--shell-wear optionally gives the Dendy shell worn plastic from
scripts/make_dendy_shell_wear.py; that artwork is photo-derived (CC BY), so the
output then stays in the private model store.
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dendy_pcb  # noqa: E402  (layout only; its PIL renderer is not used here)


BACK_PANEL = Path(__file__).resolve().parent / 'assets' / 'dendy-back-panel.png'
BACK_PANEL_CREDIT = None
PCB_TEXTURES = None
SHELL_WEAR = None
SHELL_WEAR_CREDIT = ('Worn plastic taken from the cartridge textures of "Dendy Junior" by otztava '
                     '(Sketchfab c05cb0fb636c4384a854e171b5f66e10, CC BY 4.0): scratches, scuffs '
                     'and grime as a ratio over the shell colour (scripts/make_dendy_shell_wear.py)')
PCB_CREDIT = ('Board modelled on "Dendy cartridge PCBs.jpg" by Nzeemin (Wikimedia Commons, '
              'CC BY-SA 3.0); geometry and artwork redrawn from measurements, no photo pixels')
STYLES = ['nintendo-3-gray', 'nintendo-5-gray', 'nintendo-3-gold',
          'nintendo-5-gold', 'tengen', 'camerica-gold', 'camerica-silver',
          'dreams-blue', 'dreams-black', 'ave-square', 'ave-angle',
          'active-clear', 'aladdin', 'dendy-yellow']


def material(name, color, roughness=.45, metallic=0, transmission=0, textures=None):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Transmission Weight'].default_value = transmission
    bsdf.inputs['IOR'].default_value = 1.49
    srgb = [12.92*v if v <= .0031308 else 1.055*v**(1/2.4)-.055 for v in color]
    m['runtime'] = json.dumps({'color': [*srgb, 1], 'textures': textures or {},
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


def pcb(width,height,bottom,board,pins,chips,contacts=36):
    box('PCB reference board',(0,0,bottom+height/2),(width,.0018,height),board,.0004)
    for side in (-1,1):
        for i in range(contacts):
            x=(i-(contacts-1)/2)*width/(contacts+2)
            box('72-pin connector contact',(x,side*.00105,bottom+.0045),
                (width/52,.00015,.008),pins,.00008)
    for i,(x,z) in enumerate([(-width*.22,bottom+height*.55),(width*.22,bottom+height*.69)]):
        box('Illustrative IC '+str(i),(x,-.002,z),(width*.31,.003,height*.22),chips,.0005)
        for j in range(8):
            for sign in (-1,1):
                box('IC leg',(x+sign*width*.17,-.0018,z+(j-3.5)*height*.021),
                    (.004,.0004,height*.01),pins,.00005)


class Parts:
    """Many small cuboids/cylinders per material, emitted as one object each."""

    def __init__(self):
        self.meshes = {}

    def _add(self, mat, verts, faces):
        v, f = self.meshes.setdefault(mat, ([], []))
        base = len(v)
        v.extend(verts)
        f.extend(tuple(i + base for i in face) for face in faces)

    def box(self, mat, centre, dims, rotation=None):
        hx, hy, hz = (d / 2 for d in dims)
        corners = [Vector((sx*hx, sy*hy, sz*hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        if rotation is not None: corners = [rotation @ c for c in corners]
        c = Vector(centre)
        self._add(mat, [tuple(c + k) for k in corners],
                  [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)])

    def segment(self, mat, a, b, width, thick):
        """A flat strip (lead) from a to b."""
        a, b = Vector(a), Vector(b)
        rot = (b - a).normalized().to_track_quat('Z', 'Y').to_matrix()
        self.box(mat, (a + b) / 2, (width, thick, (b - a).length), rot)

    def cylinder(self, mat, centre, axis, radius, length, segments=12, radius2=None):
        rot = Vector(axis).normalized().to_track_quat('Z', 'Y').to_matrix()
        r2 = radius if radius2 is None else radius2
        ring = [(math.cos(2*math.pi*i/segments), math.sin(2*math.pi*i/segments)) for i in range(segments)]
        verts = [rot @ Vector((x*r, y*r, z)) for z, r in ((-length/2, radius), (length/2, r2)) for x, y in ring]
        c = Vector(centre)
        faces = [tuple(range(segments-1, -1, -1)), tuple(range(segments, 2*segments))]
        faces += [(i, (i+1) % segments, (i+1) % segments + segments, i + segments) for i in range(segments)]
        self._add(mat, [tuple(c + v) for v in verts], faces)

    def emit(self, prefix):
        out = []
        for mat, (verts, faces) in self.meshes.items():
            mesh = bpy.data.meshes.new(prefix)
            mesh.from_pydata(verts, [], faces)
            mesh.update()
            obj = bpy.data.objects.new(prefix + ' - ' + mat.name, mesh)
            bpy.context.collection.objects.link(obj)
            obj.data.materials.append(mat)
            out.append(obj)
        self.meshes = {}
        return out


def atlas(obj, rect, mirrored, image_path):
    """Planar x/z projection of an artwork rectangle onto every face of obj."""
    x0, z0, w, h = rect
    obj['atlas'] = [x0, z0, w, h, 1.0 if mirrored else 0.0]
    while obj.data.uv_layers: obj.data.uv_layers.remove(obj.data.uv_layers[0])
    uv = obj.data.uv_layers.new(name='UVMap')
    for loop in obj.data.loops:
        co = obj.matrix_world @ obj.data.vertices[loop.vertex_index].co
        u = (x0 + w - co.x) / w if mirrored else (co.x - x0) / w
        uv.data[loop.index].uv = (u, (co.z - z0) / h)
    mat = obj.data.materials[0]
    if not any(n.type == 'TEX_IMAGE' for n in mat.node_tree.nodes):
        image = mat.node_tree.nodes.new('ShaderNodeTexImage')
        image.image = bpy.data.images.load(str(image_path))
        mat.node_tree.links.new(image.outputs['Color'],
            mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])


def wear_dendy_shell():
    """Project the worn-plastic albedo (make_dendy_shell_wear.py) onto the yellow shell.

    Every shell-material part takes the front image, except the parts on the back
    half, which take the back image mirrored (seen from behind). The images carry
    the shell colour, so the material colour becomes white.
    """
    front = bpy.data.materials['Shell dendy-yellow']
    back = front.copy(); back.name = 'Shell dendy-yellow back'
    for m, texture in ((front, 'texture-03.png'), (back, 'texture-04.png')):
        runtime = json.loads(m['runtime'])
        runtime.update(color=[1, 1, 1, 1], textures={'albedo': texture})
        m['runtime'] = json.dumps(runtime)
        m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (1, 1, 1, 1)
    for obj in [o for o in bpy.context.scene.objects
                if o.type == 'MESH' and o.data.materials and o.data.materials[0] == front]:
        centre = sum((obj.matrix_world @ Vector(c) for c in obj.bound_box), Vector()) / 8
        behind = centre.y > .001
        if behind: obj.data.materials[0] = back
        atlas(obj, (-.053, 0, .106, .068), behind,
              SHELL_WEAR / f"dendy-shell-wear-{'back' if behind else 'front'}.png")


def dendy_board(bottom, black):
    """The photographed Dendy DIP board (scripts/dendy_pcb.py), both faces detailed."""
    L = dendy_pcb.layout()
    mm = .001
    def P(x, z, y=0): return (x*mm, y, bottom + z*mm)
    t = L['thickness']*mm
    front_y, back_y = -t/2, t/2
    rect = (-L['width']/2*mm, bottom, L['width']*mm, L['height']*mm)
    front_png = PCB_TEXTURES/'dendy-pcb-front.png'
    core = material('Dendy PCB laminate edge', (.035, .24, .17), .55)
    face = material('Dendy PCB component side', (1, 1, 1), .5,
        textures={'albedo': 'texture-01.png'})
    rear = material('Dendy PCB solder side', (1, 1, 1), .5,
        textures={'albedo': 'texture-02.png'})
    tin = material('Dendy PCB tin', (.64, .64, .60), .32, .9)
    glass = material('Dendy PCB diode glass', (.55, .13, .03), .15)
    beige = material('Dendy PCB resistor body', (.60, .47, .32), .55)
    bands = {'brown': (.20, .08, .03), 'black': (.02, .02, .02), 'red': (.55, .03, .02),
             'gold': (.62, .45, .14)}
    band_mats = {k: material('Dendy PCB band '+k, c, .45, .6 if k == 'gold' else 0)
                 for k, c in bands.items()}
    outline = [(x*mm, bottom + z*mm) for x, z in L['outline']]
    prism('Dendy PCB laminate', outline, front_y + .00005, back_y - .00005, core, .0001)
    skin = prism('Dendy PCB component side', outline, front_y, front_y + .00005, face, 0)
    atlas(skin, rect, False, front_png)
    skin = prism('Dendy PCB solder side', outline, back_y - .00005, back_y, rear, 0)
    atlas(skin, rect, True, PCB_TEXTURES/'dendy-pcb-back.png')

    metal = Parts()
    z0, z1 = L['fingerZ']
    for x in L['fingers']:
        for y in (front_y - .00002, back_y + .00002):
            metal.box(tin, P(x, (z0+z1)/2, y), (L['fingerWidth']*mm, .00004, (z1-z0)*mm))
    packages = Parts()
    for chip in L['chips']:
        (cx, cz), (length, width) = chip['at'], chip['size']
        height = 3.9 if chip.get('rom') else 3.3
        yc = front_y - (.6 + height/2)*mm          # 0.6 mm standoff above the board
        packages.box(face, P(cx, cz, yc), (length*mm, height*mm, width*mm))
        shoulder_y = yc + height*.12*mm
        for x, z in dendy_pcb.pin_positions(chip):
            side = 1 if z > cz else -1
            edge = cz + side*width/2
            # Shoulder out of the body, the wide upper lead, then the narrow tail
            # through the board under its solder fillet.
            metal.box(tin, P(x, (edge + z)/2 + side*.1, shoulder_y), (1.2*mm, .25*mm, (abs(z - edge) + .45)*mm))
            knee = front_y - .35*mm
            metal.box(tin, P(x, z, (shoulder_y + knee)/2), (1.2*mm, abs(knee - shoulder_y), .25*mm))
            metal.box(tin, P(x, z, (knee + back_y + .9*mm)/2), (.5*mm, back_y + .9*mm - knee, .25*mm))
    for part in L['discretes']:
        (bx, bz), holes = part['at'], part['holes']
        if part['kind'] == 'disc':
            r, th = part['d']/2*mm, part['t']*mm
            yc = front_y - 1.6*mm - th/2
            packages.cylinder(face, P(bx, bz, yc), (0, 1, 0), r, th, 28)
            for hx, hz in holes:
                knee = P(hx, hz, front_y - 1.4*mm)
                metal.segment(tin, P(hx, hz, back_y + .9*mm), knee, .5*mm, .5*mm)
                metal.segment(tin, knee, P(bx + (hx-bx)*.45, bz + (hz-bz)*.45, yc), .5*mm, .5*mm)
            continue
        (ax, az), (qx, qz) = holes
        d = part['d']*mm
        yc = front_y - .25*mm - d/2
        along = Vector((qx - ax, 0, qz - az)).normalized()
        body = glass if part['kind'] == 'diode' else beige
        centre = Vector(P(bx, bz, yc))
        a = centre - along*part['length']/2*mm
        b = centre + along*part['length']/2*mm
        metal.cylinder(body, centre, along, d/2, part['length']*mm, 16)
        if part['kind'] == 'diode':
            metal.cylinder(black, b - along*.6*mm, along, d/2 + .00004, .6*mm, 16)
        else:
            for k, colour in enumerate(part['bands']):
                at = a + along*(.9 + k*1.1 + (.6 if k == 3 else 0))*mm
                metal.cylinder(band_mats[colour], at, along, d/2 + .00004, .45*mm, 16)
        for (hx, hz), end in (((ax, az), a), ((qx, qz), b)):
            hole = Vector(P(hx, hz, yc))
            metal.segment(tin, end, hole, .5*mm, .5*mm)
            metal.segment(tin, hole, Vector(P(hx, hz, back_y + .9*mm)), .5*mm, .5*mm)
    for x, z, dia in L['holes']:                  # solder fillets on every leaded hole
        if dia > 1.4:
            metal.cylinder(tin, P(x, z, back_y + .25*mm), (0, 1, 0), .8*mm, .5*mm, 10, .35*mm)
    for obj in packages.emit('Dendy PCB packages'):
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new('Moulded package edge', 'BEVEL')
        mod.width, mod.segments, mod.limit_method = .00025, 2, 'ANGLE'
        bpy.ops.object.modifier_apply(modifier=mod.name)
        atlas(obj, rect, False, front_png)
    metal.emit('Dendy PCB parts')


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
        (.72,.78,.81) if style=='active-clear' else
        (.76,.30,.01) if style=='dendy-yellow' else (.045,.05,.06))
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
    elif style=='dendy-yellow':
        # Famicom-format body, the 60-pin edge on a narrower bottom tab.
        width,height,depth=.106,.068,.018
        outline=[(-.046,0),(.046,0),(.046,.006),(.053,.006),(.053,.068),
            (-.053,.068),(-.053,.006),(-.046,.006)]
    elif style=='aladdin':
        outline=[(-.060,0),(-.047,0),(-.039,.022),(.039,.022),(.047,0),(.060,0),(.060,.092),(.049,.106),(.049,.133),(-.049,.133),(-.049,.106),(-.060,.092)]
    # Separate thin covers and perimeter walls leave a real internal cavity.
    front=prism('Front shell half',outline,-depth/2,-depth/2+.0013,shell)
    back=prism('Back shell half',outline,depth/2-.0013,depth/2,shell)
    for (x1,z1),(x2,z2) in zip(outline,outline[1:]+outline[:1]):
        # The bottom stays open over the contacts (the Dendy shell only there).
        if (z1==z2==0) if style=='dendy-yellow' else max(z1,z2)<.012: continue
        dx,dz=x2-x1,z2-z1
        o=box('Perimeter wall',((x1+x2)/2,0,(z1+z2)/2),
              (.0015,depth-.0015,math.hypot(dx,dz)),shell,.0003)
        o.rotation_euler.y=math.atan2(dx,dz)
    if style=='dendy-yellow': dendy_board(.0005,black)
    else: pcb(.094,.079,.004,board,pins,black)
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
    elif style=='dendy-yellow':
        f,b=-depth/2,depth/2
        label(0,.0355,.088,.051,f-.00015,paper)
        # Three ribs across the top, front and back, wrapping round both sides.
        for z in (.0625,.0645,.0665):
            for y in (f-.0003,b+.0003):
                box('Top rib',(0,y,z),(.104,.0006,.0009),shell,.0002)
            for x in (-.0533,.0533):
                box('Top side rib',(x,0,z),(.0006,depth-.001,.0009),shell,.0002)
        # Ribbed strips beside the label, and the hatched top-left corner.
        for x in (-.0505,-.0490,.0490,.0505):
            box('Side strip rib',(x,f-.0003,.034),(.0006,.0006,.050),shell,.0002)
        hatch=box('Hatched corner',(-.046,f-.0002,.0645),(.008,.0004,.0055),shell,.0002)
        for i in range(5):
            o=box('Corner hatch line',(-.0492+i*.0016,f-.0005,.0645),(.0005,.0004,.0062),shell,.0001)
            o.rotation_euler.y=math.radians(40)
        # The back panel: moulded care text under Steepler's warranty sticker,
        # printed as one texture inside a raised frame; no screws.
        for x,z,w,h in [(0,.0095,.090,.0008),(0,.0585,.090,.0008),
                        (-.0446,.034,.0008,.049),(.0446,.034,.0008,.049)]:
            box('Back panel frame',(x,b+.0003,z),(w,.0006,h),shell,.0002)
        print_mat=material('Dendy back panel print',(1,1,1),.6,
            textures={'albedo':'texture-00.png'})
        x0,z0,pw,ph=-.044,.010,.088,.048
        panel=prism('Back panel print',[(x0,z0),(x0+pw,z0),(x0+pw,z0+ph),(x0,z0+ph)],
            b,b+.0001,print_mat,0)
        panel['textureRect']=[x0,z0,pw,ph]
        # The same mapping in the source scene, so source.glb carries the print.
        uv=panel.data.uv_layers.new(name='UVMap')
        for loop in panel.data.loops:
            co=panel.data.vertices[loop.vertex_index].co
            uv.data[loop.index].uv=((x0+pw-co.x)/pw,1-(z0+ph-co.z)/ph)
        nodes=print_mat.node_tree.nodes
        image=nodes.new('ShaderNodeTexImage')
        image.image=bpy.data.images.load(str(BACK_PANEL))
        print_mat.node_tree.links.new(image.outputs['Color'],
            nodes['Principled BSDF'].inputs['Base Color'])
    else:
        label(0,.076,.080,.089,-.00925,paper)
        for x in (-.052,.052):
            for i in range(8): box('Moulded side grip',(x,-.009,.024+i*.010),(.007,.001,.003),shell,.0005)
    if style=='dendy-yellow' and SHELL_WEAR: wear_dendy_shell()
    return paper


# Assembly inspection, matching the supplied reference shells: Explode keys at
# 0/.3/.65/1.35 s with movement factors 0/0/.1/1; Assemble plays it backwards.
INSPECTION_TIMES=(0,.3,.65,1.35)
INSPECTION_FACTORS=(0,0,.10,1)
BOARD_PARTS=('PCB reference board','72-pin connector contact','Illustrative IC','IC leg','Dendy PCB')


def inspection_offset(obj):
    """Exploded displacement in Blender metres: covers apart, board lifted, screws out."""
    if obj.name.startswith(BOARD_PARTS): return Vector((0,0,.012))
    if 'screw' in obj.name.lower(): return Vector((0,.05,0))
    centre=sum((obj.matrix_world@Vector(c) for c in obj.bound_box),Vector())/8
    # The front cover carries the label and front mouldings; walls stay with the back.
    return Vector((0,-.03 if centre.y<-.001 else .03,0))


def export_runtime(directory, style):
    directory.mkdir(parents=True,exist_ok=False)
    inspect=style!='aladdin'
    for o in bpy.context.scene.objects:
        if o.type=='MESH' and inspect: o['inspectionOffset']=list(inspection_offset(o))
    bpy.ops.wm.save_as_mainfile(filepath=str(directory/'source.blend'))
    bpy.ops.export_scene.gltf(filepath=str(directory/'source.glb'), export_format='GLB')
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    def axis(v): return Vector((v.x,v.z,-v.y))
    offsets={o.name:Vector(o.get('inspectionOffset',(0,0,0))) for o in objects}
    factors=INSPECTION_FACTORS if inspect else (0,)
    poses=[[axis(o.matrix_world@v.co+offsets[o.name]*f) for o in objects for v in o.data.vertices]
           for f in factors]
    # Frame the whole exploded envelope, as prepare_console_model.py does.
    points=[p for pose in poses for p in pose]
    low=Vector([min(p[a] for p in points) for a in range(3)])
    high=Vector([max(p[a] for p in points) for a in range(3)])
    center=(low+high)/2; scale=2/max(high-low)
    groups={}
    aspect=1
    for obj in objects:
        mesh=obj.data; mesh.calc_loop_triangles()
        normal_matrix=obj.matrix_world.to_3x3().inverted().transposed()
        is_label=obj.get('replaceableLabel',False)
        printed=obj.get('textureRect')
        mapped=obj.get('atlas')
        if is_label:
            lx,lz,lw,lh=obj['labelRect']; aspect=lw/lh
        for tri in mesh.loop_triangles:
            mat=obj.material_slots[tri.material_index].material
            role='label' if is_label and (normal_matrix@tri.normal).y < -.9 else 'body'
            verts=groups.setdefault((mat.name,role,tuple(offsets[obj.name])),[])
            for index in tri.vertices:
                original=obj.matrix_world@mesh.vertices[index].co
                p=(axis(original)-center)*scale
                n=axis(normal_matrix@tri.normal).normalized()
                if role=='label': uv=((original.x-lx)/lw,(lz+lh-original.z)/lh)
                elif mapped:
                    ax,az,aw,ah,mirrored=mapped
                    uv=(((ax+aw-original.x) if mirrored else (original.x-ax))/aw,(az+ah-original.z)/ah)
                elif printed and (normal_matrix@tri.normal).y > .9:
                    # Seen from behind, so the image runs from +x to -x.
                    px,pz,pw,ph=printed
                    uv=((px+pw-original.x)/pw,(pz+ph-original.z)/ph)
                else: uv=(0,0)
                verts.append((*p,*n,*uv))
    textures={}
    files={'texture-00.png':BACK_PANEL}
    if PCB_TEXTURES:
        files.update({'texture-01.png':PCB_TEXTURES/'dendy-pcb-front.png',
                      'texture-02.png':PCB_TEXTURES/'dendy-pcb-back.png'})
    if SHELL_WEAR:
        files.update({'texture-03.png':SHELL_WEAR/'dendy-shell-wear-front.png',
                      'texture-04.png':SHELL_WEAR/'dendy-shell-wear-back.png'})
    for m in bpy.data.materials:
        for name in (json.loads(m['runtime'])['textures'].values() if 'runtime' in m else ()):
            if name not in textures:
                body=files[name].read_bytes()
                (directory/name).write_bytes(body)
                textures[name]=hashlib.sha256(body).hexdigest()
    payload=bytearray(); surfaces=[]
    duration=INSPECTION_TIMES[-1]
    for (name,role,offset),vertices in groups.items():
        start=len(payload)
        for v in vertices: payload.extend(struct.pack('<8f',*v))
        indices=len(payload)
        for i in range(len(vertices)): payload.extend(struct.pack('<I',i))
        motion=[{'keys':[[t/duration,*(axis(Vector(offset)*f)*scale)]
            for t,f in zip(INSPECTION_TIMES,INSPECTION_FACTORS)]}] if inspect else []
        part=('' if not inspect else ' (board)' if offset[2]>0 else ' (front)' if offset[1]<0
              else ' (fasteners)' if offset[1]>.04 else ' (back)')
        surfaces.append({'name':name,'node':name+part,'role':role,'singleSided':False,
            'physicalMaterial':'source','openingTranslations':motion,
            'vertexOffset':start,'vertexCount':len(vertices),'indexOffset':indices,
            'indexCount':len(vertices),'material':json.loads(bpy.data.materials[name]['runtime'])})
    manifest={'name':'nes-retail-'+style,'system':'nes','cartridgeStyle':style,
        'privateImport':True,'cartridgeGeometry':True,'motionKind':'pushClick',
        'bounds':list((high-low)*scale),'sourceWidth':(high.x-low.x)*scale,
        'labelAspect':aspect,'frontSign':1,'textureFiles':textures,
        'geometrySha256':hashlib.sha256(payload).hexdigest(),'surfaces':surfaces,
        'sourceReference':{'author':'G-Shop original parametric reference models',
            'url':'https://en.wikipedia.org/wiki/Dendy_(console)' if style.startswith('dendy')
                else 'https://www.thelegendofnes.com/cartridge-design',
            'licence':'local-import-only',
            'originalLicence':'Original parametric geometry; private reference use',
            'sha256':hashlib.sha256((directory/'source.glb').read_bytes()).hexdigest(),
            'limitations':'Nonstandard proportions are photograph-derived; PCB/components are illustrative, not a claimed per-ROM board.'}}
    if inspect:
        manifest.update(assemblyInspection=True,inspectionDurationMs=round(duration*1000),
            animationVerifiedMaxError=0,
            poseCenters=[[t/duration,*((Vector([(min(p[a] for p in pose)+max(p[a] for p in pose))/2
                for a in range(3)])-center)*scale)] for t,pose in zip(INSPECTION_TIMES,poses)])
        manifest['sourceReference']['previewAnimationPolicy']={'inspection':['Explode','Assemble']}
    if textures and BACK_PANEL_CREDIT:
        manifest['sourceReference']['textureCredit']=BACK_PANEL_CREDIT
    if style=='dendy-yellow':
        manifest['sourceReference']['boardCredit']=PCB_CREDIT
        if SHELL_WEAR: manifest['sourceReference']['wearCredit']=SHELL_WEAR_CREDIT
        manifest['sourceReference']['limitations']=('Shell proportions are photograph-derived. '
            'The board follows one photographed Dendy DIP board (outline, fingers, packages, '
            'markings, discretes, supply bands, silkscreen); fine routing and the solder side '
            'are interpreted, and it is not the board of any particular game.')
    (directory/'model.mesh').write_bytes(payload)
    (directory/'model.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    return {'style':style,'triangles':sum(len(v)//3 for v in groups.values()),'surfaces':len(surfaces),'geometrySha256':manifest['geometrySha256']}


def main():
    global BACK_PANEL, BACK_PANEL_CREDIT, PCB_TEXTURES, SHELL_WEAR
    parser=argparse.ArgumentParser(); parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--styles',nargs='*',choices=STYLES,default=STYLES)
    parser.add_argument('--back-panel',type=Path,default=BACK_PANEL)
    parser.add_argument('--back-panel-credit')
    parser.add_argument('--pcb-textures',type=Path,
        help='Directory with dendy-pcb-front.png/back.png from scripts/dendy_pcb.py')
    parser.add_argument('--shell-wear',type=Path,
        help='Directory with dendy-shell-wear-front.png/back.png (private, photo-derived)')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    BACK_PANEL, BACK_PANEL_CREDIT=args.back_panel, args.back_panel_credit
    PCB_TEXTURES=args.pcb_textures
    SHELL_WEAR=args.shell_wear
    if 'dendy-yellow' in args.styles and not PCB_TEXTURES:
        parser.error('dendy-yellow needs --pcb-textures (render them with scripts/dendy_pcb.py)')
    receipts=[]
    for style in args.styles:
        cartridge(style)
        receipts.append(export_runtime(args.output/style,style))
        print('NES_SHELL_AUTHORED '+json.dumps(receipts[-1]),flush=True)
    (args.output/'authoring-receipts.json').write_text(json.dumps(receipts,indent=2),encoding='utf-8')


if __name__=='__main__': main()
