"""Inspect the actual converted six-face mesh with a classified resource pack.

Host geometry evidence only: Android shading, controls and lifecycle still need
native verification. Does not edit original sources or save Blender preferences.
"""
import argparse
import json
from pathlib import Path
import struct
import sys
import zipfile

import bpy
from mathutils import Vector


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--mesh', type=Path, required=True)
    parser.add_argument('--pack', type=Path, required=True)
    parser.add_argument('--game-id', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.output.exists():
        raise ValueError('Preserve existing inspection output')
    args.output.mkdir(parents=True)
    data, raw = json.loads(args.model.read_text()), args.mesh.read_bytes()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    with zipfile.ZipFile(args.pack) as archive:
        game = next(g for g in json.loads(archive.read('packaging.json'))['games']
                    if g['gameId'] == args.game_id)
        for face, surface in enumerate(data['surfaces']):
            role = surface['name']
            resource = next(r for r in game['resources'] if r['type'] == 'outer-box-' + role)
            image_path = args.output / (role + '.png')
            image_path.write_bytes(archive.read('images/' + resource['importReference']['sha256'] + '.png'))
            image = bpy.data.images.load(str(image_path))
            material = bpy.data.materials.new(role)
            material.use_nodes = True
            shader = material.node_tree.nodes.get('Principled BSDF')
            shader.inputs['Roughness'].default_value = 1
            shader.inputs['Metallic'].default_value = 0
            texture = material.node_tree.nodes.new('ShaderNodeTexImage')
            texture.image = image
            material.node_tree.links.new(texture.outputs['Color'], shader.inputs['Base Color'])
            vertices = [struct.unpack_from('<8f', raw, surface['vertexOffset'] + i * 32)
                        for i in range(surface['vertexCount'])]
            indices = struct.unpack_from('<' + 'I' * surface['indexCount'], raw, surface['indexOffset'])
            mesh = bpy.data.meshes.new(role)
            # App geometry is Y-up; Blender inspection uses Z-up. This changes
            # only the inspection scene, never the exported model or UVs.
            mesh.from_pydata([(v[0], -v[2] * .18 / 2, v[1]) for v in vertices], [],
                             [indices[i:i+3] for i in range(0, len(indices), 3)])
            uv = mesh.uv_layers.new()
            for polygon in mesh.polygons:
                for loop in polygon.loop_indices:
                    v = vertices[mesh.loops[loop].vertex_index]
                    uv.data[loop].uv = (v[6] * 3 - face % 3, 1 - (v[7] * 2 - face // 3))
            mesh.materials.append(material)
            obj = bpy.data.objects.new(role, mesh)
            bpy.context.scene.collection.objects.link(obj)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 16
    scene.render.threads_mode, scene.render.threads = 'FIXED', 2
    scene.render.resolution_x, scene.render.resolution_y = 1000, 750
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .5
    for name, position in [('key', (2, 4, 5)), ('fill', (-3, 1, -3))]:
        lamp = bpy.data.lights.new(name, 'AREA')
        lamp.energy, lamp.size = 350, 5
        obj = bpy.data.objects.new(name, lamp)
        scene.collection.objects.link(obj)
        obj.location = position
        obj.rotation_euler = (-obj.location).to_track_quat('-Z', 'Y').to_euler()
    camera = bpy.data.objects.new('inspection', bpy.data.cameras.new('inspection'))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type, camera.data.ortho_scale = 'ORTHO', 3.3
    for name, direction in [('front', (1.5, -4, 1.1)), ('back', (-1.5, 4, 1.1)),
                            ('bottom', (1.5, -4, -1.6))]:
        camera.location = Vector(direction)
        camera.rotation_euler = (-camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(args.output / (name + '.png'))
        bpy.ops.render.render(write_still=True)
    print('PACKAGING_INSPECTION ' + json.dumps({'triangles': sum(s['indexCount']//3 for s in data['surfaces']),
          'nativeVerified': False, 'output': str(args.output)}))


main()
