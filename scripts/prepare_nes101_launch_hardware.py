"""Articulate the supplied jonesy85 NES-101 as a private launch derivative.

Blender --background --python-exit-code 1 --python this_file --
  --source supplied-toploader.glb --output absent-directory
The original scene, UVs, materials and matching controller remain attributable.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_nes_launch_hardware import add_extras


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Preserve authored resources; select an absent output')
    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
    if digest != '712dec6638d0199fe14d10931f923dbd049b2e0e315a2eeb03cb5d367492e167':
        raise ValueError('Expected the inspected jonesy85 NES-101 source')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    objects = [o for o in bpy.data.objects if o.type == 'MESH']
    if {o.name for o in objects} != {f'ToploaderPart{i:02}' for i in range(13)}:
        raise ValueError('NES-101 source components differ')
    # Apply the original hierarchy once, retaining world geometry in Z-up cm.
    transforms = {o: Matrix.Scale(100, 4) @ o.matrix_world for o in objects}
    for obj in objects:
        obj.data.transform(transforms[obj])
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
    body = bpy.data.objects['ToploaderPart04']
    roots = list(range(len(body.data.vertices)))

    def root(i):
        while roots[i] != i:
            roots[i] = roots[roots[i]]
            i = roots[i]
        return i

    # UV seams duplicate vertices. Join only their connectivity for identifying
    # the existing disconnected flap; do not weld or retessellate source meshes.
    positions = {}
    for vertex in body.data.vertices:
        key = tuple(round(float(v), 4) for v in vertex.co)
        if key in positions:
            roots[root(vertex.index)] = root(positions[key])
        else:
            positions[key] = vertex.index
    for edge in body.data.edges:
        a, b = map(root, edge.vertices)
        roots[b] = a
    groups = {}
    for vertex in body.data.vertices:
        groups.setdefault(root(vertex.index), []).append(vertex.index)
    flap_ids = [ids for ids in groups.values() if len(ids) == 48]
    if len(groups) != 2 or len(flap_ids) != 1:
        raise ValueError('Expected the inspected separate 48-vertex dust flap')
    flap_ids = set(flap_ids[0])
    flap = body.copy()
    flap.data = body.data.copy()
    flap.name = 'Nes101SlotFlap'
    bpy.context.collection.objects.link(flap)
    for obj, remove_flap in [(body, True), (flap, False)]:
        mesh = bmesh.new()
        mesh.from_mesh(obj.data)
        mesh.verts.ensure_lookup_table()
        bmesh.ops.delete(mesh, geom=[v for v in mesh.verts
                                    if (v.index in flap_ids) == remove_flap],
                         context='VERTS')
        mesh.to_mesh(obj.data)
        mesh.free()
    points = [v.co.copy() for v in flap.data.vertices]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    pivot = Vector(((low.x + high.x) / 2, high.y, high.z))
    flap.data.transform(Matrix.Translation(-pivot))
    flap.location = pivot
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1, 25
    flap.rotation_mode = 'XYZ'
    for name, start, end in [('Open', 0, math.pi / 2),
                             ('Close', math.pi / 2, 0)]:
        flap.animation_data_create()
        flap.animation_data.action = bpy.data.actions.new(name)
        for frame, angle in [(1, start), (25, end)]:
            flap.rotation_euler = (angle, 0, 0)
            flap.keyframe_insert(data_path='rotation_euler', frame=frame)
        action = flap.animation_data.action
        track = flap.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.extrapolation = 'NOTHING'
        track.mute = True
        flap.animation_data.action = None
    flap.rotation_euler = (0, 0, 0)
    hand = [bpy.data.objects[f'ToploaderPart{i:02}'] for i in (0, 1, 5, 9)]
    case = bpy.data.objects['ToploaderPart09']
    center = Vector([(min(v.co[a] for v in case.data.vertices) +
                      max(v.co[a] for v in case.data.vertices)) / 2
                     for a in range(3)])
    floor = min(v.co.z for v in bpy.data.objects['ToploaderPart12'].data.vertices)
    bottom = min(v.co.z for o in hand for v in o.data.vertices)
    translation = Matrix.Translation((-center.x, -18 - center.y, floor - bottom))
    for obj in hand:
        obj.data.transform(translation)
    jack = Vector((0, max(v.co.y for v in case.data.vertices) - .03,
                   (min(v.co.z for v in case.data.vertices) +
                    max(v.co.z for v in case.data.vertices)) / 2))
    original = bpy.data.objects['ToploaderPart03']
    material = original.data.materials[0]
    bpy.data.objects.remove(original, do_unlink=True)
    def cable_route(radius):
        path = [(2.5, -10.92, .9), (6, -13, floor + 1.0),
                (12, -12, floor + 1.0), (28 - radius - .5, -8, floor + .9)]
        for i in range(73):
            angle = math.pi + i * math.tau * 3 / 72
            r = radius + .6 * i * 3 / 72
            path.append((28 + r * math.cos(angle),
                         -8 + .75 * r * math.sin(angle), floor + .12))
        path.extend([(14, -16, floor + .12), (8, -16, floor + .12),
                     (3, -15, floor + .3), (0, jack.y + 1.3, jack.z), tuple(jack)])
        return path
    curve = bpy.data.curves.new('NES-101 right-side cord', 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 12
    curve.bevel_depth = .12
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    cord = bpy.data.objects.new('ToploaderPart03', curve)
    bpy.context.collection.objects.link(cord)
    curve.materials.append(material)
    def fit_route(radius):
        path = cable_route(radius)
        curve.splines.clear()
        spline = curve.splines.new('BEZIER')
        spline.bezier_points.add(len(path) - 1)
        for point, position in zip(spline.bezier_points, path):
            point.co = position
            point.handle_left_type = point.handle_right_type = 'AUTO'
        bpy.context.view_layer.update()
        for point in spline.bezier_points:
            handles = [point.handle_left.copy(), point.handle_right.copy()]
            for handle in handles:
                handle.z = max(floor + .12, handle.z)
                if abs(point.co.z - floor - .12) < 1e-6:
                    handle.z = point.co.z
            point.handle_left_type = point.handle_right_type = 'FREE'
            point.handle_left, point.handle_right = handles
        return spline, path
    low_radius, high_radius = 6.0, 18.0
    target_length = 230.0
    while high_radius - low_radius > .000001:
        radius = (low_radius + high_radius) / 2
        spline, path = fit_route(radius)
        length = spline.calc_length(resolution=256)
        if abs(length - target_length) < .005: break
        if length < target_length: low_radius = radius
        else: high_radius = radius
    measured_length = spline.calc_length(resolution=512)
    if abs(measured_length - target_length) > .05:
        raise ValueError('Dogbone cable centerline differs from its physical target')
    bpy.ops.object.select_all(action='DESELECT')
    cord.select_set(True)
    bpy.context.view_layer.objects.active = cord
    bpy.ops.object.convert(target='MESH')
    cable_bottom = min(v.co.z for v in cord.data.vertices)
    controller_bottom = min(v.co.z for o in hand for v in o.data.vertices)
    if min(cable_bottom, controller_bottom) < floor - .0001:
        raise ValueError('NES-101 controller or cable penetrates support plane')
    profile = {
        'schema': 1, 'target': 'nes-top-loader', 'system': 'nes',
        'compatibleMedia': 'nes-72-pin', 'sourceUnits': 'centimetres',
        'insertionMode': 'vertical', 'bodyWidthCm': 15,
        'lidNode': flap.name, 'trayNodes': [], 'powerLedNode': None,
        'powerNode': 'ToploaderPart06', 'controllerPort': 1,
        'controllerNodes': [o.name for o in hand] + ['ToploaderPart03', 'ToploaderPart10'],
        'controllerLayout': {'groundZ': floor, 'jack': list(jack),
                             'cablePath': path, 'cableSide': 'right',
                             'controllerPosition': 'centered-front',
                             'controllerBottomZ': controller_bottom,
                             'cableBottomZ': cable_bottom,
                             'nominalCableLengthCm': target_length,
                             'measuredCableLengthCm': measured_length,
                             'coilTurns': 3, 'cableDiameterCm': .24,
                             'referenceUrl': 'https://www.neogaf.com/threads/nes-famicom-appreciation-thread.537429/page-95',
                             'reference': 'Firsthand comparison of USA NES-039 dogbone and original NES leads, within about 1 cm; rounded 2.3 m modeling target, not a factory specification or an AV Famicom cable claim'},
        'lidPivot': list(pivot), 'lidOpenRadians': math.pi / 2,
        'sourceSlotEntry': [pivot.x, (low.y + high.y) / 2 + .05, 17],
        'sourceSlotInserted': [pivot.x, (low.y + high.y) / 2 + .05, 9],
        'sourceSlotSeated': [pivot.x, (low.y + high.y) / 2 + .05, 9],
        'sourceDustFlapBounds': [list(low), list(high)],
        'slotCalibration': 'Insertion axis 0.05 cm rearward of flap center; actual case/curved-shell triangle clearance, not a flap AABB safety inset',
        'sourceSha256': digest, 'sourceAuthor': 'jonesy85',
        'sourceUrl': 'https://sketchfab.com/3d-models/6bc1a3bc1de84892b2a8537cf7cdf8cd',
        'adaptation': 'Existing dust flap separated at original seams and hinged; original UV/PBR and player-1 plug retained; dogbone grounded centered in front, cord routed right; original collector retained',
    }
    args.output.mkdir(parents=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / 'source.blend'))
    glb = args.output / 'source.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB',
                              export_animations=True, export_animation_mode='NLA_TRACKS',
                              export_extras=True, export_yup=True)
    add_extras(glb, {'launchHardware': profile})
    profile['derivedSha256'] = hashlib.sha256(glb.read_bytes()).hexdigest()
    (args.output / 'provenance.json').write_text(json.dumps(profile, indent=2), encoding='utf8')
    print('NES101_LAUNCH_AUTHORED ' + json.dumps(profile))


if __name__ == '__main__':
    main()
