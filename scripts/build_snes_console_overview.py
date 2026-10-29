"""Adapt the owner's supplied SNES showcase, then use the normal private importer.

Run through the installed Blender gate. Source downloads are never modified.
The saved scene is metre-scale; only the private preview import is normalized.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import runpy
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

SOURCE_SHA = '4905e01b24108b83b5c8eb392477bdd00f5eff822c5eb5c43ee1763f082254a6'
PARENTS = {
    'Snes_Reworked-459939cf.glb': ('Manny Ruiz', '8f01e19957e1aca9f9a6d289b92dcbe758b7056ece94c567021170fd104a85de', 'CC BY 4.0'),
    'Super_Nintendo_Entertainment_System_SNES-1b76ea62.glb': ('Julian Reich', 'a4f04f339be4247f091cb63276726b28cf5914116bc664dd27b59e16aad3dbe8', 'Editorial (source declaration)'),
    'SNES-6dd14cfd.glb': ('Rusty Hardy', '2901f560a8a70c6368bb62c3531635d9ec81a9ceafdd38a8e3e184c9efd397f1', 'CC BY-NC-ND (source declaration)'),
    'SNES_PAL_-_Super_Mario_World-31f4914a.glb': ('Valeria Tarquinio', 'dbf01970512b1c578b751f1a55e5bc0d86ffa3959a1849144b412bcdbb19e45e', 'Unspecified in supplied export'),
}


def meshes(root):
    return [o for o in (root, *root.children_recursive) if o.type == 'MESH']


def bounds(objects):
    # Imported controller parts have rotated local boxes that exaggerate their
    # depth. Physical scale, placement and collision checks need real vertices.
    points = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    if not points:
        raise ValueError('Missing geometry')
    return (Vector([min(p[i] for p in points) for i in range(3)]),
            Vector([max(p[i] for p in points) for i in range(3)]))


def move(objects, offset):
    # Transform each mesh in world space, independent of imported parent pivots.
    transform = Matrix.Translation(offset)
    for obj in objects:
        obj.matrix_world = transform @ obj.matrix_world
    bpy.context.view_layer.update()


def place(objects, x, y):
    low, high = bounds(objects)
    offset = Vector((x, y, 0)) - Vector(((low.x + high.x) / 2,
                                       (low.y + high.y) / 2, low.z))
    move(objects, offset)
    return offset


def cable_ends(obj):
    # Use the two actual open tube rings, not a box centre guessed near a plug.
    bm = bmesh.new()
    try:
        bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
        remaining = {v for v in bm.verts if any(e.is_boundary for e in v.link_edges)}
        rings = []
        while remaining:
            seed = remaining.pop()
            component, stack = {seed}, [seed]
            while stack:
                vertex = stack.pop()
                for edge in vertex.link_edges:
                    neighbour = edge.other_vert(vertex)
                    if edge.is_boundary and neighbour in remaining:
                        remaining.remove(neighbour)
                        component.add(neighbour)
                        stack.append(neighbour)
            if len(component) != 10:
                raise ValueError('Supplied cable end topology changed')
            vertices = [obj.matrix_world @ v.co for v in sorted(component, key=lambda v: v.index)]
            center = sum(vertices, Vector()) / len(vertices)
            vectors = [v-center for v in vertices]
            normal = max((a.cross(b) for a in vectors for b in vectors), key=lambda v: v.length)
            normal.normalize()
            if max(abs(v.dot(normal)) for v in vectors) > .00001:
                raise ValueError('Cable attachment ring is not planar')
            rings.append((center, normal))
        if len(rings) != 2:
            raise ValueError('Expected exactly two measured cable ends')
        return rings
    finally:
        bm.free()


def surface_tree(objects):
    vertices, triangles = [], []
    for obj in objects:
        obj.data.calc_loop_triangles()
        offset = len(vertices)
        vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        triangles.extend(tuple(offset+i for i in triangle.vertices)
                         for triangle in obj.data.loop_triangles)
    return BVHTree.FromPolygons(vertices, triangles, all_triangles=True)


def cross_controller_clearance():
    checks = []
    for own, other in [('US', 'PAL'), ('PAL', 'US')]:
        wire = bpy.data.objects[own + '_Controller_Cable_MetreScale']
        pad = meshes(bpy.data.objects[other + '_Controller'])
        intersections = surface_tree([wire]).overlap(surface_tree(pad))
        checks.append({'cable': own, 'controller': other,
                       'intersectingTrianglePairs': len(intersections)})
        if intersections:
            raise ValueError('Cable intersects the other controller: ' + repr(checks[-1]))
    return checks


def controller_clearance(path, controller, end, radius):
    tree = surface_tree(controller)
    low, high = bounds(controller)
    minimum, checked = float('inf'), 0
    for point in path:
        # The last two cable diameters seat in the actual strain-relief opening.
        if (point-end).length <= radius*4:
            continue
        # Conservatively keep the route outside the entire controller footprint,
        # then measure distance to the actual transformed triangle surfaces.
        if (low.x-radius <= point.x <= high.x+radius and
                low.y-radius <= point.y <= high.y+radius):
            raise ValueError('Cable enters controller footprint: ' + repr({
                'point': list(point), 'bounds': [list(low), list(high)],
                'end': list(end)}))
        nearest = tree.find_nearest(point)
        if nearest[0] is None:
            raise ValueError('Controller surface clearance could not be measured')
        minimum = min(minimum, nearest[3])
        checked += 1
    if minimum < radius+.001:
        raise ValueError('Cable intersects or grazes controller surface: ' + str(minimum))
    return {'samples': checked, 'minimumSurfaceDistanceMetres': minimum,
            'cableRadiusMetres': radius, 'requiredSurfaceGapMetres': .001,
            'contactExclusionRadiusMetres': radius*4,
            'method': 'Transformed controller-triangle BVH plus conservative XY keepout; actual strain-relief contact only'}


def cable(name, start, end, start_direction, end_direction, material, controller, nominal=1.8288):
    # One C1 cubic spline, with hand-laid asymmetric folds rather than circular
    # equations or separately joined leads. Both measured connection rings stay
    # fixed while the slack's footprint is solved to the physical cable length.
    diameter = .0043
    center = Vector((.205, end.y-.020, diameter/2))
    layout = [(.080, .015, .00215), (.145, .040, .00215),
              (.225, .002, .00215), (.217, -.052, .00215),
              (.151, -.081, .00215), (.090, -.041, .0085),
              (.116, .010, .00215), (.182, .020, .00215),
              (.213, -.023, .00215), (.175, -.064, .00215),
              (.113, -.066, .00215), (.085, -.022, .009),
              (.130, .010, .00215), (.179, -.013, .00215),
              (.157, -.046, .00215), (.105, -.035, .00215)]
    # Slightly different folds for each controller, retaining one ground plane.
    asymmetry = 1 if name.startswith('US') else -1

    def controls(factor):
        # Leave the measured connector plane along its actual normal for 25mm.
        # A fixed global tangent followed immediately by slack caused a hairpin.
        lead = start + start_direction * .025
        landing = start + start_direction * .050 + Vector((.018, 0, 0))
        landing.z = diameter/2
        knots = [start, lead, landing]
        for i, (x, y, z) in enumerate(layout):
            point = Vector((x + .050 + .008*asymmetry*math.sin(i*.83), end.y+y, z))
            knots.append(Vector((center.x+(point.x-center.x)*factor,
                                 center.y+(point.y-center.y)*factor, z)))
        knots.extend([Vector((.085, end.y+.035, .00215)),
                      Vector((.030, end.y+.045, .0045)), end])
        handles = []
        for i, point in enumerate(knots):
            if i in (0, 1):
                tangent = start_direction * (.025/3)
            elif i == len(knots)-1:
                tangent = end_direction * .012
            else:
                tangent = (knots[i+1]-knots[i-1])/6
                tangent.z = 0
            handles.append((point-tangent, point+tangent))
        return knots, handles

    def points(factor):
        knots, handles = controls(factor)
        result = []
        for i, (a, d) in enumerate(zip(knots, knots[1:])):
            b, c = handles[i][1], handles[i+1][0]
            result.extend(a*(1-t)**3 + b*(3*t*(1-t)**2) +
                          c*(3*t*t*(1-t)) + d*t**3
                          for t in [j/32 for j in range(32)])
        return [*result, end]

    def length(p):
        return sum((b - a).length for a, b in zip(p, p[1:]))

    lo, hi = .3, 2.5
    for _ in range(50):
        mid = (lo + hi) / 2
        if length(points(mid)) < nominal:
            lo = mid
        else:
            hi = mid
    factor = (lo + hi)/2
    path = points(factor)
    if abs(length(path) - nominal) > .00001:
        raise ValueError('Cable length calibration failed')
    clearance = controller_clearance(path, controller, end, diameter/2)
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = diameter / 2
    curve.bevel_resolution = 2
    curve.resolution_u = 32
    spline = curve.splines.new('BEZIER')
    knots, handles = controls(factor)
    spline.bezier_points.add(len(knots)-1)
    for vertex, point, (left, right) in zip(spline.bezier_points, knots, handles):
        vertex.co = point
        vertex.handle_left_type = vertex.handle_right_type = 'FREE'
        vertex.handle_left, vertex.handle_right = left, right
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj.select_set(False)
    return {'object': name, 'lengthMetres': length(path), 'diameterMetres': diameter,
            'routing': 'Single C1 cubic spline; asymmetric hand-laid folds and raised crossings; no circular sections',
            'connectionRings': [list(start), list(end)],
            'connectionTangents': [list(start_direction), list(end_direction)],
            'straightConnectorLeadMetres': .025,
            'controllerClearance': clearance,
            'connectorLeadMaxLateralErrorMetres': max(
                (point-start-start_direction*(point-start).dot(start_direction)).length
                for point in path[:33]),
            'reference': 'https://xyab.com/products/controller-cable-snes',
            'policy': 'Nominal 72-inch replacement-cable reference; not an OEM factory specification'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if hashlib.sha256(args.source.read_bytes()).hexdigest() != SOURCE_SHA:
        raise ValueError('Review a changed source before adapting it')
    if args.output.exists():
        raise ValueError('Output must be absent; preserve the previous deliverable')
    args.output.mkdir(parents=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    original = {o.name for o in bpy.context.scene.objects if o.type == 'MESH'}
    staging = bpy.data.objects['Presentation_Staging']
    removed = [o.name for o in staging.children_recursive]
    for obj in list(staging.children_recursive):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(staging, do_unlink=True)
    bpy.context.view_layer.update()
    calibration, cables, supports = [], [], []
    for prefix, region, width, reference, x, angle in (
        ('US', 'North_American_SNES', .2032,
         'https://visualalchemy.tv/storage/pdf_name/7283_va.pdf', -.280, 10),
        ('PAL', 'PAL_SNES', .200,
         'https://www.nintendo.com/en-gb/Hardware/Nintendo-History/Super-Nintendo/Technical-Details/Technical-Details-627042.html', .280, -10),
    ):
        assembly = meshes(bpy.data.objects[region])
        console = meshes(bpy.data.objects[prefix + '_Console'])
        low, high = bounds(console)
        factor = width / (high.x - low.x)
        pivot = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
        transform = Matrix.Scale(factor, 4) @ Matrix.Translation(-pivot)
        for obj in assembly:
            obj.matrix_world = transform @ obj.matrix_world
        bpy.context.view_layer.update()
        body_low, body_high = bounds(console)
        pad = meshes(bpy.data.objects[prefix + '_Controller'])
        plug = meshes(bpy.data.objects[prefix + '_Controller_Plug'])
        plug_low, plug_high = bounds(plug)
        plug_center = (plug_low + plug_high) / 2
        old_cable = bpy.data.objects[prefix + '_Controller_Cable']
        (start, start_direction), (end, end_direction) = sorted(
            cable_ends(old_cable), key=lambda ring: (ring[0]-plug_center).length)
        if start_direction.dot(start-plug_center) < 0:
            start_direction.negate()
        pad_low, pad_high = bounds(pad)
        pad_scale = .144 / (pad_high.x - pad_low.x)
        pad_center = (pad_low + pad_high) / 2
        if end_direction.dot(pad_center-end) < 0:
            end_direction.negate()
        pad_transform = (Matrix.Translation(pad_center) @ Matrix.Scale(pad_scale, 4) @
                         Matrix.Translation(-pad_center))
        for obj in pad:
            obj.matrix_world = pad_transform @ obj.matrix_world
        bpy.context.view_layer.update()
        pad_offset = place(pad, 0, body_low.y - .125)
        end = pad_transform @ end + pad_offset
        material = old_cable.data.materials[0]
        assembly = [o for o in assembly if o != old_cable]
        bpy.data.objects.remove(old_cable, do_unlink=True)
        bpy.ops.object.select_all(action='DESELECT')
        cables.append(cable(prefix + '_Controller_Cable_MetreScale', start, end,
                            start_direction, end_direction, material, pad))
        stack = meshes(bpy.data.objects[prefix + '_Cartridge_Stack'])
        place(stack, -.19 if prefix == 'US' else .19, .045)
        if prefix == 'PAL':
            place(meshes(bpy.data.objects['PAL_Manual']), .195, .13)
        # Shared plane, inward-facing shallow arc. Include the replacement cable
        # in the same rigid regional transform without scaling it separately.
        retained = list(assembly)
        retained.append(bpy.data.objects[prefix + '_Controller_Cable_MetreScale'])
        transform = Matrix.Translation((x, .03, 0)) @ Matrix.Rotation(math.radians(angle), 4, 'Z')
        for obj in retained:
            obj.matrix_world = transform @ obj.matrix_world
        bpy.context.view_layer.update()
        for part, group in [('console', console), ('controller', pad), ('games', stack)]:
            support_low, support_high = bounds(group)
            supports.append({'region': prefix, 'part': part,
                             'boundsMetres': [list(support_low), list(support_high)]})
        calibration.append({'region': prefix, 'consoleWidthMetres': width,
                            'uniformSourceScale': factor, 'reference': reference,
                            'estimated': True, 'bodyBoundsBeforePlacement': [list(body_low), list(body_high)],
                            'controllerWidthMetres': .144,
                            'controllerScalePolicy': 'Common nominal 144mm assembly reference; estimated, not a measured OEM specimen'})
    cross_contacts = cross_controller_clearance()
    # Preserve per-part provenance already carried by the aggregate's extras.
    provenance = []
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH':
            continue
        filename = obj.get('source_filename')
        if filename and filename not in PARENTS:
            raise ValueError('Unreviewed parent: ' + filename)
        provenance.append({'object': obj.name, 'sourceFilename': filename,
                           'sourceObject': obj.get('source_object'),
                           'boundsMetres': [list(v) for v in bounds([obj])]})
    present = {o.name for o in bpy.context.scene.objects if o.type == 'MESH'}
    unexpected = original - present - set(removed) - {'US_Controller_Cable', 'PAL_Controller_Cable'}
    if unexpected:
        raise ValueError('Unexpected source omission: ' + repr(unexpected))
    low, high = bounds([o for o in bpy.context.scene.objects if o.type == 'MESH'])
    report = {'source': str(args.source), 'sourceSha256': SOURCE_SHA,
              'hiddenStaging': removed, 'physicalScale': calibration, 'cables': cables,
              'groundSupports': supports,
              'crossControllerClearance': cross_contacts,
              'sourceParents': [{'filename': f, 'author': v[0], 'sha256': v[1], 'licence': v[2]} for f, v in PARENTS.items()],
              'objects': provenance, 'boundsMetres': [list(low), list(high)],
              'scope': 'Static console selector only; no per-game launch or physical-printing acceptance'}
    (args.output / 'preparation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / 'SNES-console-overview.blend'))
    derivative = args.output / 'SNES-console-overview.glb'
    bpy.ops.export_scene.gltf(filepath=str(derivative), export_format='GLB',
                              export_animations=False, export_cameras=False, export_extras=True)
    sys.argv = ['prepare_console_model.py', '--', '--source', str(derivative),
                '--output', str(args.output / 'imports' / 'consoles' / 'snes'),
                '--system', 'snes', '--author', 'Owner-supplied showcase; per-part creators in preparation.json',
                '--source-url', args.source.as_uri(), '--physical-width-metres', str(high.x-low.x),
                '--dimensions-reference', 'Metre-scale dual assembly; preparation.json records per-console references',
                '--dimensions-estimated', '--scratch-directory', str(args.scratch),
                '--overview-max-triangles', '135000', '--overview-texture-size', '1024']
    runpy.run_path(str(Path(__file__).with_name('prepare_console_model.py')), run_name='__main__')
    manifest_path = args.output / 'imports/consoles/snes/model.json'
    manifest = json.loads(manifest_path.read_text())
    # Soft contact shadows use the same authored footprints and normalization.
    # These are footprint approximations, not ray-traced lighting geometry.
    center = (low+high)/2
    scale = manifest['sourceWidth']/(high.x-low.x)
    manifest['groundSupports'] = [
        [(entry['boundsMetres'][0][0]-center.x)*scale,
         (-entry['boundsMetres'][1][1]+center.y)*scale,
         (entry['boundsMetres'][1][0]-center.x)*scale,
         (-entry['boundsMetres'][0][1]+center.y)*scale]
        for entry in supports]
    manifest['sourceReference']['showcasePreparation'] = report
    manifest['sourceReference']['adaptation'] = 'US/PAL shared metre scale; staging removed, controllers grounded in front, nominal measured-length coils right; bounded selector geometry/textures'
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'output': str(args.output), 'meshBytes': (manifest_path.parent/'model.mesh').stat().st_size,
                      'surfaces': len(manifest['surfaces']), 'textures': len(manifest['textureFiles'])}))


if __name__ == '__main__':
    main()
