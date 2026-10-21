"""Articulate the supplied Rusty Hardy NES for a private launch import.

Run with Blender --background --python-exit-code 1 --python this_file --
  --source isolated-console.glb --output absent-directory

The collector and original isolated console remain unchanged. This authoring step
retains source UVs/materials and saves an editable derivative, reversible lid
actions and its source receipt. It does not distribute the imported artwork.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector


def add_extras(path, extras):
    raw = path.read_bytes()
    size, tag = struct.unpack_from('<II', raw, 12)
    if raw[:4] != b'glTF' or tag != 0x4e4f534a:
        raise ValueError('Expected exported binary glTF')
    data = json.loads(raw[20:20 + size])
    data.setdefault('extras', {}).update(extras)
    encoded = json.dumps(data, separators=(',', ':')).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    tail = raw[20 + size:]
    path.write_bytes(struct.pack('<4sII', b'glTF', 2, 20 + len(encoded) + len(tail))
                     + struct.pack('<II', len(encoded), tag) + encoded + tail)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Preserve existing authored resources; use an absent output')
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    objects = [o for o in bpy.data.objects if o.type == 'MESH']
    lid_name = 'NES|NES_Lid|Dupli|1_Lid_0'
    lid = bpy.data.objects.get(lid_name)
    tray = [o for o in objects if o.name.startswith('NES|NES_Cart_Bed|')]
    led = [o for o in objects if o.name.endswith('7_LED_0')]
    if lid is None or len(tray) != 2 or len(led) != 1:
        raise ValueError('Expected inspected NES lid, tray and power LED objects')
    console = [o for o in objects if o.name.startswith('NES|')]
    controller = [o for o in objects if not o.name.startswith('NES|')]
    if len(console) != 27 or len(controller) != 12:
        raise ValueError('NES source geometry differs from the inspected console')
    # Keep the source plug seated in player 1. Level the controller against its
    # actual planar underside, then route a fresh cable along the right side.
    # The original collector/cable remains in the unmodified parent source.
    cord = bpy.data.objects['Controller_Cord_Cord_0']
    case = next(o for o in controller if 'NES_Cotroller_Case.002' in o.name
                and 'Base_Light' in o.name)
    hand = [o for o in controller if o.name.startswith('NES_Controller|')]
    points = [case.matrix_world @ v.co for v in case.data.vertices]
    center = Vector([(min(p[a] for p in points) + max(p[a] for p in points)) / 2
                     for a in range(3)])
    bottom = max((f for f in case.data.polygons if f.normal.z < -.9),
                 key=lambda f: f.area)
    normal = -(case.matrix_world.to_3x3().inverted().transposed() @ bottom.normal).normalized()
    eigen = np.linalg.eigh(np.cov(np.array([list(p) for p in points]).T))[1][:, -1]
    right = Vector(eigen.tolist())
    right = (right - normal * right.dot(normal)).normalized()
    if right.x < 0:
        right.negate()
    up = normal.cross(right).normalized()
    level = Matrix((right, up, normal)).to_4x4()
    transform = Matrix.Translation((0.0, -21.0, 0)) @ level @ Matrix.Translation(-center)
    for obj in hand:
        obj.matrix_world = transform @ obj.matrix_world
    floor = min((o.matrix_world @ v.co).z for o in console
                if 'NES_Feet|' in o.name for v in o.data.vertices)
    bottom_z = min((o.matrix_world @ v.co).z for o in hand for v in o.data.vertices)
    for obj in hand:
        obj.matrix_world.translation.z += floor - bottom_z
    body = [case.matrix_world @ v.co for v in case.data.vertices]
    jack = Vector((0, max(p.y for p in body) - .08,
                   (max(p.z for p in body) + min(p.z for p in body)) / 2))
    cable_path = [
        (6.54, -14.28, 2.92), (9.0, -15.6, 1.7),
        (15.0, -15.5, floor + .22), (22, -14.0, floor + .18),
        (25.0, -9.0, floor + .18), (22.0, -3.5, floor + .18),
        (16.5, -5.0, floor + .18), (15.5, -12.5, floor + .18),
        (10.5, -17.0, floor + .18), (3.5, -17.7, floor + .22),
        (jack.x, jack.y + 1.35, jack.z), tuple(jack),
    ]
    cable_material = cord.data.materials[0]
    cord_name = cord.name
    bpy.data.objects.remove(cord, do_unlink=True)
    curve = bpy.data.curves.new('Right-side controller cable', 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 12
    curve.bevel_depth = .18
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(cable_path) - 1)
    for point, position in zip(spline.bezier_points, cable_path):
        point.co = position
        point.handle_left_type = point.handle_right_type = 'AUTO'
    cord = bpy.data.objects.new(cord_name, curve)
    bpy.context.collection.objects.link(cord)
    curve.materials.append(cable_material)
    bpy.context.view_layer.update()
    # Automatic handles can dip a cable below the support plane between knots.
    # Bound the Bezier control hull, rather than clipping the resulting tube.
    for point in spline.bezier_points:
        left, right_handle = point.handle_left.copy(), point.handle_right.copy()
        for handle in (left, right_handle):
            handle.z = max(floor + .18, handle.z)
            if abs(point.co.z - (floor + .18)) < 1e-6:
                handle.z = point.co.z
        point.handle_left_type = point.handle_right_type = 'FREE'
        point.handle_left, point.handle_right = left, right_handle
    bpy.ops.object.select_all(action='DESELECT')
    cord.select_set(True)
    bpy.context.view_layer.objects.active = cord
    bpy.ops.object.convert(target='MESH')
    cable_bottom = min((cord.matrix_world @ v.co).z for v in cord.data.vertices)
    controller_bottom = min((o.matrix_world @ v.co).z for o in hand
                            for v in o.data.vertices)
    if min(cable_bottom, controller_bottom) < floor - .0001:
        raise ValueError('Controller or cable penetrates the support plane')
    retained = [o for o in bpy.data.objects if o.type == 'MESH']
    controller = [o for o in retained if not o.name.startswith('NES|')]
    # The supplied lid is open, with an L-shaped face/return. Its large face is
    # horizontal, not a diagonal flap. The hinge is at the rear lower return.
    # Closing by 88.728 degrees seats the face in the front aperture; this was
    # checked against the actual source geometry and rendered closed/open poses.
    pivot = Vector((-2.05, -6.60, 8.57))
    angle = math.radians(88.728)
    world = lid.matrix_world.copy()
    lid.data.transform(Matrix.Translation(-pivot) @ world)
    lid.matrix_world = Matrix.Translation(pivot)
    lid.rotation_mode = 'XYZ'
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 1, 25
    for name, start, end in [('Open', angle, 0.0), ('Close', 0.0, angle)]:
        lid.animation_data_create()
        lid.animation_data.action = bpy.data.actions.new(name)
        for frame, value in [(1, start), (25, end)]:
            lid.rotation_euler = (value, 0, 0)
            lid.keyframe_insert(data_path='rotation_euler', frame=frame)
        action = lid.animation_data.action
        track = lid.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.extrapolation = 'NOTHING'
        lid.animation_data.action = None
        track.mute = True
    lid.rotation_euler = (angle, 0, 0)
    for obj in list(bpy.data.objects):
        if obj.type == 'MESH' and obj not in retained:
            bpy.data.objects.remove(obj, do_unlink=True)
    # Keep authoring calibration in source Z-up centimetres. The existing
    # importer converts anchors using its own exact centering and uniform scale.
    bed = next(o for o in tray if o.name.endswith('Cart_Bed_0'))
    support = max((f for f in bed.data.polygons if f.normal.z > .99),
                  key=lambda f: f.area)
    tray_pitch = math.atan2(support.normal.y, support.normal.z)
    floor_faces = [f for f in bed.data.polygons
                   if f.normal.z > .99 and f.area > 6]
    rear = max((bed.matrix_world @ bed.data.vertices[v].co
                for f in floor_faces for v in f.vertices), key=lambda p: p.y)
    profile = {
        'schema': 1, 'target': 'nes-front-loader', 'system': 'nes',
        'compatibleMedia': 'nes-72-pin', 'sourceUnits': 'centimetres',
        'lidNode': lid_name, 'trayNodes': [o.name for o in tray],
        'powerLedNode': led[0].name,
        'controllerNodes': [o.name for o in controller],
        'controllerPort': 1,
        'controllerLayout': {'groundZ': floor, 'jack': list(jack),
                             'cablePath': cable_path, 'cableSide': 'right',
                             'controllerPosition': 'centered-front',
                             'controllerBottomZ': controller_bottom,
                             'cableBottomZ': cable_bottom},
        'lidPivot': list(pivot), 'lidOpenRadians': -angle,
        # The large bed faces, rather than its enclosing fences/underside,
        # establish the raised tray plane (approximately five degrees).
        'sourceSlotEntry': [-2.05, -20, 5.3 + 18 * math.tan(tray_pitch)],
        'sourceSlotInserted': [-2.05, -2, 5.3],
        'sourceSlotSeated': [-2.05, -2, 4.0],
        'sourceTrayPivot': [-2.05, rear.y, rear.z],
        'insertionPitch': -tray_pitch,
        'trayPressRadians': tray_pitch,
        'sourceSha256': source_hash,
        'sourceAuthor': 'Rusty Hardy',
        'sourceUrl': 'https://sketchfab.com/3d-models/ad1ba0a577c44f47be224084eea5965d',
        'adaptation': 'Matching player-1 plug retained; controller levelled onto ground centred in front; cable rerouted to right; calibrated reversible front lid; original collector and textures retained',
    }
    args.output.mkdir(parents=True)
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / 'source.blend'))
    target = args.output / 'source.glb'
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB',
        export_animations=True, export_animation_mode='NLA_TRACKS',
        export_frame_range=False, export_force_sampling=True,
        export_nla_strips_merged_animation_name='Open', export_extras=True)
    add_extras(target, {'launchHardware': profile})
    receipt = {**profile, 'derivedSha256': hashlib.sha256(target.read_bytes()).hexdigest(),
               'retainedMeshes': [o.name for o in retained]}
    (args.output / 'provenance.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
    print('NES_LAUNCH_AUTHORED ' + json.dumps(receipt))


if __name__ == '__main__':
    main()
