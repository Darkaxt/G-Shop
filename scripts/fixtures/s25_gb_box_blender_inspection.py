"""Private GB box reference inspection; no model export or user preferences."""

import hashlib
import json
from pathlib import Path

import bpy
from mathutils import Vector

ARCHIVE = Path("D:/Downloads/game-boy-super-mario-land-box.zip")
SOURCE = Path("E:/R-Shop Reference Assets/Sketchfab/b4515d780a3b4b02a50d20bdec70a5a0/source-20261018/source/SUPER MARIO LAND.fbx")
OUTPUT = SOURCE.parents[1] / "inspection"
EXPECTED = "a6fd3d101679d430365f002a8e7a16c84333dc0f6ae9d9ca74f10717578661a8"

assert hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() == EXPECTED
assert not OUTPUT.exists(), "Preserve existing inspection evidence"
OUTPUT.mkdir()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
# The legacy import_scene.fbx rejects ASCII; Blender's native importer reads it.
bpy.ops.wm.fbx_import(filepath=str(SOURCE))
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
assert len(meshes) == 1 and not bpy.data.actions
points = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
low = Vector(tuple(min(p[a] for p in points) for a in range(3)))
high = Vector(tuple(max(p[a] for p in points) for a in range(3)))
center, span = (low + high) / 2, (high - low).length
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.render.threads_mode = "FIXED"
scene.render.threads = 2
scene.render.resolution_x = 1000
scene.render.resolution_y = 700
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
for name, offset in [("key", (1, -2, 3)), ("fill", (-2, 1, 2))]:
    light = bpy.data.lights.new(name, "AREA")
    light.energy, light.size = 70 * span * span, span * 2
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = center + Vector(offset) * span
    obj.rotation_euler = (center - obj.location).to_track_quat("-Z", "Y").to_euler()
camera = bpy.data.objects.new("inspection", bpy.data.cameras.new("inspection"))
scene.collection.objects.link(camera)
scene.camera = camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = span * 1.5
for name, direction in [("front", (0.3, -2, 0.3)), ("back", (-0.3, 2, 0.3))]:
    camera.location = center + Vector(direction).normalized() * span * 3
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(OUTPUT / f"{name}.png")
    bpy.ops.render.render(write_still=True)
report = {
    "archive_sha256": EXPECTED,
    "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    "blender": bpy.app.version_string,
    "meshes": [{"name": o.name, "vertices": len(o.data.vertices),
                "polygons": len(o.data.polygons), "uv_layers": len(o.data.uv_layers)} for o in meshes],
    "images": [{"name": i.name, "size": list(i.size), "has_data": i.has_data}
               for i in bpy.data.images if i.type == "IMAGE"],
    "animation_clips": len(bpy.data.actions),
    "native_verified": False,
    "opening_verified": False,
    "source_unchanged": hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() == EXPECTED,
}
(OUTPUT / "inspection.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print("S25_GB_INSPECTION " + json.dumps(report))
