"""Keep only the Dendy Junior console (and its inserted cartridge) from otztava's Dendy Junior
scene (Sketchfab c05cb0fb, CC BY) after normal/material clean-up; the result feeds
prepare_console_model.py. Writes a GLB plus six review renders.
An optional ALBEDO replaces the console's base colour atlas (the black Subor SB-225
from make_subor_sb225_texture.py uses the same body).
blender --background --python extract_dendy_junior.py -- SRC.blend OUT.glb RENDERDIR [ALBEDO]"""
import bpy, sys, math
from mathutils import Vector
args = sys.argv[sys.argv.index('--')+1:]
src, out, rdir = args[:3]
bpy.ops.wm.open_mainfile(filepath=src)
if len(args) > 3:
    atlas = bpy.data.images['Material_Base_color.png']
    atlas.filepath = args[3]; atlas.reload()
    if atlas.packed_file: atlas.unpack(method='REMOVE'); atlas.filepath = args[3]; atlas.reload()
scene = bpy.context.scene
body = [o for o in scene.objects if o.type=='MESH' and o.data.materials and o.data.materials[0].name=='dendy'][0]
for o in [o for o in scene.objects if o.type=='MESH' and o is not body]:
    bpy.data.objects.remove(o)          # loose cartridges K_2/K_3/k_3 and the wires
bpy.ops.object.select_all(action='DESELECT'); body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.separate(type='LOOSE'); bpy.ops.object.mode_set(mode='OBJECT')
def box(o):
    pts=[o.matrix_world@Vector(c) for c in o.bound_box]
    return [min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]
parts = [o for o in scene.objects if o.type=='MESH']
shell = max(parts, key=lambda o: len(o.data.polygons))
lo, hi = box(shell); m = (.006, .002)  # side jacks stand ~4 mm proud; the leaning controller is 3 mm past the back
kept = []
for o in parts:
    a, b = box(o)
    if all(lo[i]-m[i] <= a[i] and b[i] <= hi[i]+m[i] for i in range(2)) and a[2] < hi[2]: kept.append(o)  # nothing floating above the shell
    else: bpy.data.objects.remove(o)
print('KEPT', len(kept), 'of', len(parts), 'faces', sum(len(o.data.polygons) for o in kept))
bpy.ops.object.select_all(action='DESELECT')
for o in kept: o.select_set(True)
bpy.context.view_layer.objects.active = shell; bpy.ops.object.join(); shell.name = 'DendyJunior'
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB')
# review renders
lo, hi = box(shell); size = Vector(hi)-Vector(lo); centre = (Vector(hi)+Vector(lo))/2
print('DIMS', [round(v,4) for v in size])
scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
scene.render.resolution_x, scene.render.resolution_y = 1000, 750
scene.view_settings.view_transform = 'Standard'
w = bpy.data.worlds.new('w'); w.use_nodes = True
w.node_tree.nodes['Background'].inputs[0].default_value = (.55,.56,.6,1); w.node_tree.nodes['Background'].inputs[1].default_value = .6; scene.world = w
for rot, e in (((45,0,30),3.0), ((60,0,210),1.2)):
    s = bpy.data.objects.new('sun', bpy.data.lights.new('sun','SUN')); s.data.energy = e
    s.rotation_euler = [math.radians(v) for v in rot]; scene.collection.objects.link(s)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); scene.collection.objects.link(cam); scene.camera = cam
cam.data.clip_start, cam.data.clip_end = size.length/500, size.length*20
for i,(az,el) in enumerate(((-60,30),(-100,20),(60,30),(120,25),(-90,80),(180,10))):
    a, e = math.radians(az), math.radians(el)
    cam.location = centre + Vector((math.cos(a)*math.cos(e), math.sin(a)*math.cos(e), math.sin(e)))*size.length*1.3
    cam.rotation_euler = (centre-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath = f'{rdir}/view-{i}.png'; bpy.ops.render.render(write_still=True)
