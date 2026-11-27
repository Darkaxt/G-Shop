"""Build the Subor SB-225B keyboard computer from make_subor_sb225b_textures.py output.

A photo-proportioned, original reconstruction: a light grey 101-key case with a
sloped key deck, a raised rear ledge holding the cartridge slot (white flap behind
an inserted yellow "Обучающий картридж"), the indicator panel with its power
button, and the two Subor joysticks cabled to the case sides. Keys are tapered
low-poly caps sharing one legend atlas. Front is -Y, like the NES builders.
Each joystick cord is solved to its documented length (see CABLE_TARGET), coiled
beside its pad and checked for clearance; the receipts are written to
OUT.cables.json for the installed model.json (sourceReference.cableReceipts).
Writes OUT.glb, OUT.blend and six review renders; feeds prepare_console_model.py.

blender --background --factory-startup --python build_subor_sb225b.py -- TEXDIR OUT.glb RENDERDIR
"""
import importlib.util
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

spec = importlib.util.spec_from_file_location(
    'nes_parts', Path(__file__).with_name('build_nes_cartridge_models.py'))
parts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parts)


def linear(rgb):
    return tuple(((c / 255 + .055) / 1.055) ** 2.4 if c / 255 > .04045 else c / 255 / 12.92 for c in rgb)


def image_material(name, path, roughness=.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(str(path))
    tex.image.name = f'{name} texture'
    bsdf = nodes['Principled BSDF']
    m.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = roughness
    return m


def mesh_object(name, verts, faces, uvs, mat):
    """faces index verts; uvs gives one (u, v) per face corner, in face order."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    layer = mesh.uv_layers.new(name='UVMap')
    for poly, face_uv in zip(mesh.polygons, uvs):
        for li, uv in zip(poly.loop_indices, face_uv):
            layer.data[li].uv = uv
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def planar(name, rects, z_of, mat, to_uv):
    """Flat textured quads over world (x0, y0, x1, y1) rectangles, following z_of(y)."""
    verts, faces, uvs = [], [], []
    for x0, y0, x1, y1 in rects:
        base = len(verts)
        corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        verts += [(x, y, z_of(y)) for x, y in corners]
        faces.append(tuple(range(base, base + 4)))
        uvs.append([to_uv(x, y) for x, y in corners])
    return mesh_object(name, verts, faces, uvs, mat)


def cylinder(name, location, radius, depth, mat, rotation=(0, 0, 0), vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth,
                                        location=location, rotation=rotation)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat)
    return o


def keycaps(layout, deck_z, mat):
    body, unit = layout['body'], layout['body']['unit']
    left, back = -23 * unit / 2, body['keysBack']
    gap, inset, rise, travel = .0011, .0017, .0016, .0085
    verts, faces, uvs = [], [], []
    for k in layout['keys']:
        x0 = left + k['x'] * unit + gap
        x1 = left + (k['x'] + k['w']) * unit - gap
        y1 = back - k['y'] * unit - gap
        y0 = back - (k['y'] + k['h']) * unit + gap
        bottom = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        top = [(x0 + inset, y0 + inset * 1.4), (x1 - inset, y0 + inset * 1.4),
               (x1 - inset, y1 - inset * .8), (x0 + inset, y1 - inset * .8)]
        base = len(verts)
        verts += [(x, y, deck_z(y) + rise) for x, y in bottom]
        verts += [(x, y, deck_z(y) + rise + travel) for x, y in top]
        u0, v0, u1, v1 = k['uv']
        faces.append((base + 4, base + 5, base + 6, base + 7))
        uvs.append([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
        side = layout['sideSwatches'][k['colour']]
        for i in range(4):
            j = (i + 1) % 4
            faces.append((base + i, base + j, base + 4 + j, base + 4 + i))
            uvs.append([side] * 4)
    return mesh_object('Keycaps', verts, faces, uvs, mat)


def body_shell(body, case, deck_z):
    w, d = body['width'], body['depth']
    lf, lb = body['ledgeFront'], body['ledgeBack']
    df = body['keysFront'] - .004
    top = .047
    profile = [(-d / 2, 0), (-d / 2, .019), (-d / 2 + .002, .0235), (df - .002, deck_z(df) - .0003),
               (df, deck_z(df)), (lf - .001, deck_z(lf - .001)), (lf, top - .0015), (lf + .0015, top),
               (lb, top), (d / 2, top - .002), (d / 2, 0)]
    # parts.prism extrudes an (x, z) outline along y; build along x by a quarter turn.
    shell = parts.prism('SB-225B case', [(y, z) for y, z in profile], -w / 2, w / 2, case, .0012)
    shell.rotation_euler.z = math.pi / 2
    bpy.ops.object.select_all(action='DESELECT')
    shell.select_set(True)
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    # prism's y runs front->back; after +90 deg about z it maps to -x: mirror-free since symmetric.
    return shell

# Joystick cables (docs/agent-skills/gshop-console-integration: wired props).
# No factory figure for the SB-225B's fixed joystick cord was found. The nearest
# documented Subor part is the replacement rectangular joystick for hardwired
# Subor consoles (internal 5-pin connector), listed with a 115 cm cable.
CABLE_TARGET = 1.15
CABLE_DIAMETER = .0036
CABLE_REFERENCE = ('https://dendy-sega.kupit-ukraina.com.ua/aksessuary/dlya-dendy-8-bit/'
                   'dendy-junior-subor')
CABLE_REFERENCE_NOTE = ('Replacement Subor joystick for hardwired consoles (internal 5-pin '
    'connector), listed "Длина кабеля: 115 см"; not a measurement of an original SB-225B '
    'cord. Other Dendy/Subor pads are listed at 110-190 cm, so take +/-20 cm.')


def bezier(a, b, c, d, n=24):
    return [a*(1-t)**3 + b*3*t*(1-t)**2 + c*3*t*t*(1-t) + d*t**3 for t in (i/n for i in range(n))]


def polyline_length(points):
    return sum((q - p).length for p, q in zip(points, points[1:]))


def cable_path(sign, jack, end, coil_centre, radius, turns=2.75):
    """Jack lead -> ground -> flat stacked coil beside the pad -> pad strain relief.

    Built for the right-hand pad (sign=+1) and mirrored in x for the left one.
    The coil is wound anticlockwise (seen from above) for the right pad, entering on its
    inner side heading forward and leaving across its top towards the pad; each turn
    lies on the one before, so the exit crosses over the entry lead.
    """
    r = CABLE_DIAMETER / 2
    def m(v): return Vector((v.x * sign, v.y, v.z))
    out = Vector((1, 0, 0))
    start = Vector((abs(jack.x), jack.y, jack.z))
    lead = start + out * .025                       # straight off the jack normal
    c = Vector((abs(coil_centre.x), coil_centre.y, 0))
    a0, a1 = math.pi, math.pi + turns * 2 * math.pi
    def coil(a):
        k = (a - a0) / (a1 - a0)
        rr = radius * (1 - .04 * k)                  # hand-wound: slightly tighter
        return Vector((c.x + rr * math.cos(a), c.y + rr * math.sin(a),
                       r + k * turns * CABLE_DIAMETER * 1.05))
    entry, exit_ = coil(a0), coil(a1)
    pts = [start + (lead - start) * (i / 6) for i in range(6)]
    pts += bezier(lead, lead + out * .04, entry + Vector((0, .07, 0)), entry, 40)
    steps = int(turns * 96)
    pts += [coil(a0 + (a1 - a0) * i / steps) for i in range(steps)]
    e = Vector((abs(end.x), end.y, end.z))
    pts += bezier(exit_, exit_ + Vector((-.05, 0, 0)), e + Vector((0, .05, 0)), e, 40)
    pts.append(e)
    return [m(p) for p in pts]


def clearance(points, objects, exempt, r):
    """Minimum gap from the cable centreline to the transformed object triangles."""
    verts, tris = [], []
    for obj in objects:
        mesh = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        mesh.calc_loop_triangles()
        base = len(verts)
        verts.extend(obj.matrix_world @ v.co for v in mesh.vertices)
        tris.extend(tuple(base + i for i in t.vertices) for t in mesh.loop_triangles)
    tree = BVHTree.FromPolygons(verts, tris, all_triangles=True)
    gap, checked = float('inf'), 0
    for p in points:
        if any((p - q).length <= allowance for q, allowance in exempt):
            continue
        hit = tree.find_nearest(p)
        gap = min(gap, hit[3])
        checked += 1
    if gap < r + .001:
        raise ValueError(f'Joystick cable grazes {[o.name for o in objects]}: {gap:.4f} m')
    return {'samples': checked, 'minimumSurfaceDistanceMetres': round(gap, 5)}


def self_clearance(points, r):
    """Non-adjacent cable samples stay a diameter apart (stacked turns touch at most)."""
    worst = float('inf')
    for i in range(0, len(points), 3):
        for j in range(i + 12, len(points), 3):
            if polyline_length(points[i:j + 1]) < 6 * r:
                continue
            worst = min(worst, (points[i] - points[j]).length)
    if worst < 2 * r * .98:
        raise ValueError(f'Joystick cable passes through itself: {worst:.4f} m')
    return round(worst, 5)


def joystick_cables(pads, case, cord, width, pad_size):
    pw, pd, ph = pad_size
    receipts = []
    for i, pad in enumerate(pads):
        sign = 1 if pad.location.x > 0 else -1
        jack = Vector((sign * width / 2, 0, .015))
        end = Vector((pad.location.x, pad.location.y + pd / 2, ph / 2))
        centre = Vector((sign * (abs(pad.location.x) + pw / 2 + .12), pad.location.y - .004 * sign, 0))
        lo, hi = .02, .09
        for _ in range(60):
            mid = (lo + hi) / 2
            if polyline_length(cable_path(sign, jack, end, centre, mid)) < CABLE_TARGET: lo = mid
            else: hi = mid
        path = cable_path(sign, jack, end, centre, (lo + hi) / 2)
        measured = polyline_length(path)
        if abs(measured - CABLE_TARGET) > 1e-4:
            raise ValueError('Joystick cable length calibration failed')
        r = CABLE_DIAMETER / 2
        own = clearance(path, [pad], [(end, 4 * r)], r)
        other = clearance(path, [p for p in pads if p is not pad], [], r)
        body = clearance(path, [case], [(jack, 4 * r)], r)
        if min(p.z for p in path) < r - 1e-6:
            raise ValueError('Joystick cable sinks below the desk')
        curve = bpy.data.curves.new(f'Joystick {i + 1} cable', 'CURVE')
        curve.dimensions, curve.bevel_depth, curve.bevel_resolution = '3D', r, 2
        spline = curve.splines.new('POLY')
        spline.points.add(len(path) - 1)
        for point, p in zip(spline.points, path):
            point.co = (*p, 1)
        obj = bpy.data.objects.new(f'Joystick {i + 1} cable', curve)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(cord)
        receipts.append({
            'cable': obj.name, 'nominalCableLengthCm': CABLE_TARGET * 100,
            'measuredCableLengthCm': round(measured * 100, 3),
            'lengthMeasurement': 'Arc length of the transformed tube centreline (polyline that is the mesh path), scene metres',
            'lengthReference': CABLE_REFERENCE, 'lengthReferenceNote': CABLE_REFERENCE_NOTE,
            'lengthUncertaintyCm': 20, 'cableDiameterMm': CABLE_DIAMETER * 1000,
            'coilTurns': 2.75, 'jack': [round(v, 4) for v in jack],
            'strainRelief': [round(v, 4) for v in end],
            'routing': '25 mm straight lead along the case-side jack normal, down to the desk, '
                       'a flat stacked coil beside the pad, then into the pad\'s rear strain relief',
            'clearance': {'ownPad': own, 'otherPad': other, 'case': body,
                          'selfMinimumCentreDistanceMetres': self_clearance(path, r),
                          'requiredSurfaceGapMetres': .001,
                          'contactAllowance': 'Only the jack and strain-relief junctions, 4 cable radii each'}})
    return receipts


def main():
    tex, out_glb, renders = sys.argv[sys.argv.index('--') + 1:][:3]
    tex, out_glb, renders = Path(tex), Path(out_glb), Path(renders)
    layout = json.loads((tex / 'layout.json').read_text(encoding='utf-8'))
    body = layout['body']
    bpy.ops.wm.read_factory_settings(use_empty=True)
    case = parts.material('SB-225B light grey case', linear((203, 201, 189)), .55)
    black = parts.material('Slot interior', (.012, .012, .014), .7)
    white = parts.material('Slot flap', linear((236, 234, 226)), .45)
    yellow = parts.material('Cartridge yellow', linear((236, 196, 30)), .38)
    pad_grey = parts.material('Joystick case', linear((198, 196, 186)), .5)
    rubber = parts.material('Joystick buttons', linear((176, 170, 150)), .45)
    cord = parts.material('Cable', (.02, .02, .022), .6)
    key_mat = image_material('SB-225B keycaps', tex / 'keys.png', .42)
    deck_mat = image_material('SB-225B deck print', tex / 'deck.png', .55)
    ledge_mat = image_material('SB-225B ledge print', tex / 'ledge.png', .55)
    label_mat = image_material('Learning cartridge label', tex / 'cart-label.png', .35)
    pad_mat = image_material('Joystick face plates', tex / 'pad.png', .45)

    df, lf = body['keysFront'] - .004, body['ledgeFront']
    slope = .010 / (lf - df)
    deck_z = lambda y: .0265 + (y - df) * slope
    w = body['width']
    shell = body_shell(body, case, deck_z)

    # Cartridge slot through the ledge, its dark interior and the hinged white flap.
    slot_y, slot_d = .072, .022
    sx0, sx1 = body['slot']
    cutter = parts.box('Slot cutter', (0, slot_y, .040), (sx1 - sx0, slot_d, .030), black, 0)
    bpy.context.view_layer.objects.active = shell
    mod = shell.modifiers.new('Cartridge slot', 'BOOLEAN')
    mod.operation, mod.object = 'DIFFERENCE', cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    parts.box('Slot well', (0, slot_y, .0245), (sx1 - sx0, slot_d, .001), black, 0)
    flap = parts.box('Slot flap', (0, slot_y + slot_d / 2 + .004, .047 + .016), (sx1 - sx0 + .002, .0025, .032), white, .0008)
    flap.rotation_euler.x = math.radians(-9)

    top = .047
    planar('Deck print', [(-w / 2 + .003, df, w / 2 - .003, lf - .0012)], lambda y: deck_z(y) + .0002,
           deck_mat, lambda x, y: (x / w + .5, (y - df) / (lf - df)))
    lb = body['ledgeBack']
    l0, l1 = lf + .0016, lb - .0004
    y_s0, y_s1 = slot_y - slot_d / 2, slot_y + slot_d / 2
    ledge_rects = [(-w / 2 + .003, l0, sx0, l1), (sx1, l0, w / 2 - .003, l1),
                   (sx0, l0, sx1, y_s0), (sx0, y_s1, sx1, l1)]
    planar('Ledge print', ledge_rects, lambda y: top + .0002, ledge_mat,
           lambda x, y: (x / w + .5, (y - lf) / (lb - lf)))

    keycaps(layout, deck_z, key_mat)
    unit, left = body['unit'], -23 * body['unit'] / 2
    by = body['keysBack'] - unit / 2 + .001
    cylinder('Power button', (left + 22.5 * unit, by, deck_z(by) + .0025), .0055, .005,
                   parts.material('Power button', linear((222, 220, 210)), .35))

    # Inserted learning cartridge (second-issue label facing the user).
    parts.box('Learning cartridge', (0, slot_y, .053), (.108, .017, .070), yellow, .0025)
    for x in (-.0525, .0525):
        parts.box('Cartridge grip', (x, slot_y, .066), (.006, .0185, .040), yellow, .0015)
    lx, lz0, lz1 = .032, .049, .084
    ly = slot_y - .0085 - .0003
    mesh_object('Cartridge label', [(-lx, ly, lz0), (lx, ly, lz0), (lx, ly, lz1), (-lx, ly, lz1)],
                [(0, 1, 2, 3)], [[(0, 0), (1, 0), (1, 1), (0, 1)]], label_mat)

    # Two joysticks in front of the case, cabled to its sides.
    pw, pd, ph = .118, .052, .016
    pads = []
    dpad = parts.material('D-pad', linear((180, 176, 156)), .45)
    for i, cx in enumerate((-.120, .120)):
        cy, cz = -.165, ph / 2
        pads.append(parts.box(f'Joystick {i + 1}', (cx, cy, cz), (pw, pd, ph), pad_grey, .006))
        fw, fd = pw - .008, pd - .006
        u0 = i * .5
        planar(f'Joystick {i + 1} face', [(cx - fw / 2, cy - fd / 2, cx + fw / 2, cy + fd / 2)],
               lambda y: ph + .0002, pad_mat,
               lambda x, y, cx=cx, cy=cy, u0=u0: (u0 + .5 * ((x - cx) / fw + .5), (y - cy) / fd + .5))
        dx, dy = cx + (.18 - .5) * fw, cy + (.5 - 123 / 224) * fd
        for dims in ((.017, .0055, .004), (.0055, .017, .004)):
            parts.box('D-pad', (dx, dy, ph + .002), dims, dpad, .0008)
        for bx in (376, 450):
            for byy in (62, 152):
                x = cx + (bx / 512 - .5) * fw
                y = cy + (.5 - byy / 224) * fd
                cylinder('Joystick button', (x, y, ph + .0015), .0052, .003, rubber)
    receipts = joystick_cables(pads, shell, cord, w, (pw, pd, ph))
    out_glb.parent.mkdir(parents=True, exist_ok=True)
    out_glb.with_suffix('.cables.json').write_text(json.dumps(receipts, indent=2, ensure_ascii=False),
                                                   encoding='utf-8')
    print('CABLES', json.dumps([(r['cable'], r['measuredCableLengthCm'], r['clearance']) for r in receipts]))

    for o in list(bpy.context.scene.objects):
        if o.type == 'CURVE':
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.convert(target='MESH')
    out_glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out_glb.with_suffix('.blend')))
    bpy.ops.export_scene.gltf(filepath=str(out_glb), export_format='GLB')
    tris = sum(len(p.vertices) - 2 for o in bpy.context.scene.objects if o.type == 'MESH' for p in o.data.polygons)
    print('TRIANGLES', tris)
    review(renders)


def review(renders):
    scene = bpy.context.scene
    meshes = [o for o in scene.objects if o.type == 'MESH']
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    size, centre = hi - lo, (hi + lo) / 2
    print('DIMS', [round(v, 4) for v in size])
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 1200, 800
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('w')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.55, .56, .6, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .6
    scene.world = world
    for rot, energy in (((45, 0, -30), 3.0), ((60, 0, 150), 1.2)):
        sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
        sun.data.energy = energy
        sun.rotation_euler = [math.radians(v) for v in rot]
        scene.collection.objects.link(sun)
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.clip_start, cam.data.clip_end = size.length / 500, size.length * 20
    for i, (az, el, dist) in enumerate(((-90, 35, 1.1), (-60, 30, 1.1), (-120, 20, 1.1),
                                        (90, 30, 1.1), (-90, 85, 1.0), (-75, 30, .45))):
        a, e = math.radians(az), math.radians(el)
        target = centre if i < 5 else Vector((.06, .06, .04))
        cam.location = target + Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e))) * size.length * dist
        cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(renders / f'view-{i}.png')
        bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    main()
