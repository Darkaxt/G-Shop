"""Read-only inspection of the owner's S25 GBA GLB in Blender background mode.

Does not save a modified model, install add-ons, or alter Blender preferences.
Images and the report are retained private reference evidence, not app assets.
"""

import hashlib
import json
from pathlib import Path

import bpy
from mathutils import Vector


SOURCE = Path("D:/Downloads/Gameboy_Advance_Cartridge-25bd1b56.glb")
EXPECTED_SHA256 = "17d1fa5c2cc20954afccdb6b809bd585ab65175ffe36e0c587534f526c0baec1"
OUTPUT = Path(
    "E:/R-Shop Reference Assets/Sketchfab/25bd1b56c5b94d59884abd077156bde4/inspection-20261018"
)


def bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    low = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    high = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return low, high


def inspect():
    before = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if before != EXPECTED_SHA256:
        raise ValueError("Owner GLB changed; inspect its new identity before rendering")
    if OUTPUT.exists() and any(OUTPUT.iterdir()):
        raise ValueError("Inspection output already exists; refusing evidence overwrite")
    OUTPUT.mkdir(parents=True, exist_ok=True)

    # Only the factory-startup scene is cleared. No user blend file is opened.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 4 or bpy.data.actions:
        raise ValueError("Unexpected source mesh or animation inventory")
    report = {
        "blender": bpy.app.version_string,
        "source_sha256": before,
        "source_bytes": SOURCE.stat().st_size,
        "meshes": [
            {
                "name": obj.name,
                "vertices": len(obj.data.vertices),
                "polygons": len(obj.data.polygons),
                "world_bounds": [list(value) for value in bounds([obj])],
                "materials": [slot.material.name for slot in obj.material_slots],
                "uv_layers": len(obj.data.uv_layers),
            }
            for obj in meshes
        ],
        "images": [
            {"name": img.name, "size": list(img.size), "has_data": img.has_data}
            for img in bpy.data.images if img.type == "IMAGE"
        ],
        "animation_clips": len(bpy.data.actions),
        "renders": [],
        "native_verified": False,
        "opening_verified": False,
    }
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
    scene.render.film_transparent = False
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.16, 0.16, 0.16, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6

    low, high = bounds(meshes)
    center = (low + high) * 0.5
    span = (high - low).length
    for name, offset, energy in [
        ("Inspection key", (1, -2, 3), 70),
        ("Inspection fill", (-2, 1, 2), 40),
    ]:
        lamp = bpy.data.lights.new(name, "AREA")
        lamp.energy = energy * span * span
        lamp.shape = "DISK"
        lamp.size = span * 2
        obj = bpy.data.objects.new(name, lamp)
        scene.collection.objects.link(obj)
        obj.location = center + Vector(offset) * span
        obj.rotation_euler = (center - obj.location).to_track_quat("-Z", "Y").to_euler()
    camera = bpy.data.objects.new("Inspection camera", bpy.data.cameras.new("Inspection camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    for name, group, direction in [
        ("assembly-front", meshes, (0.25, -2, 0.45)),
        ("assembly-back", meshes, (-0.25, 2, 0.45)),
        ("cartridge-front", [obj for obj in meshes if "Cartridge" in obj.name], (0.12, -2, 0.2)),
    ]:
        for obj in meshes:
            obj.hide_render = obj not in group
        view_low, view_high = bounds(group)
        target = (view_low + view_high) * 0.5
        extent = (view_high - view_low).length
        camera.location = target + Vector(direction).normalized() * extent * 3
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = extent * 1.65
        scene.render.filepath = str(OUTPUT / (name + ".png"))
        bpy.ops.render.render(write_still=True)
        report["renders"].append(name + ".png")

    report["source_unchanged"] = hashlib.sha256(SOURCE.read_bytes()).hexdigest() == before
    if not report["source_unchanged"]:
        raise ValueError("Source identity changed during inspection")
    (OUTPUT / "inspection.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("S25_GBA_INSPECTION " + json.dumps(report))


inspect()
