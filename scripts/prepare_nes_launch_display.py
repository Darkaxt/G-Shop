"""Prepare the owner-supplied Sony TV as a calibrated private launch resource.

Blender --background --python-exit-code 1 --python this_file --
  --source supplied.glb --output absent-directory
Original geometry, UVs and source textures remain attributable and undistributed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
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
        raise ValueError('Preserve prior resources; choose an absent output')
    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
    if digest != 'f215d21d62d61b1c05bd2cfb4cd9bffa42df13b244cd3ee932efc33a707866db':
        raise ValueError('Expected the inspected supplied Sony KV-1300E')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    objects = [o for o in bpy.data.objects if o.type == 'MESH']
    if len(objects) != 13:
        raise ValueError('The inspected Sony component set differs')
    screen = bpy.data.objects.get('defaultMaterial.001')
    if screen is None or len(screen.data.vertices) != 121:
        raise ValueError('The supplied curved CRT screen differs')
    points = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    scale = 47.4 / (high.x - low.x)
    transform = Matrix.Scale(scale, 4) @ Matrix.Translation(
        (-(low.x + high.x) / 2, -low.y, -low.z))
    world = {o: transform @ o.matrix_world for o in objects}
    for index, obj in enumerate(objects):
        obj.data.transform(world[obj])
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.name = 'SonyCrtScreen' if obj == screen else f'SonyCrtPart{index:02}'
    # The atlas stays intact. Only the actual screen receives a separate runtime
    # material so power-on never makes the cabinet/printed controls emit light.
    material = screen.data.materials[0].copy()
    material.name = 'SonyCrtPhosphor'
    screen.data.materials[0] = material
    points = [v.co for v in screen.data.vertices]
    screen_low = [min(p[a] for p in points) for a in range(3)]
    screen_high = [max(p[a] for p in points) for a in range(3)]
    profile = {
        'schema': 1, 'target': 'sony-kv1300e', 'system': 'nes',
        'sourceUnits': 'centimetres', 'groundZ': 0,
        'screenNode': screen.name,
        'sourceScreenBounds': [screen_low, screen_high],
        'sourceScreenCenter': [(a + b) / 2 for a, b in zip(screen_low, screen_high)],
        'sourceScreenSize': [screen_high[0] - screen_low[0],
                             screen_high[2] - screen_low[2]],
        'sourceBounds': [[-23.7, 0, 0],
                         [23.7, (high.y - low.y) * scale,
                          (high.z - low.z) * scale]],
        'physicalWidthCm': 47.4,
        'scaleBasis': {
            'reference': 'Sony KV-1300E service manual, cover specifications',
            'url': 'https://archives.doctsf.com/documents/feuilleter_document.php?num_doc=98684',
            'cabinetDimensionsCm': [47.4, 31.8, 39.4],
            'policy': 'Uniform width calibration; source proportions retained',
            'uncertainty': 'Other dimensions are model-derived approximations; antenna height is included in the model bounds',
        },
        'sourceSha256': digest, 'sourceAuthor': 'shrednector',
        'sourceUrl': 'https://sketchfab.com/3d-models/309572a900d2491fb0f992dce6d6af0e',
        'adaptation': 'All original geometry/UV/PBR retained; uniform 474 mm cabinet-width calibration, grounded source frame, separate original curved screen material for launch power and zoom; originals retained',
    }
    args.output.mkdir(parents=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / 'source.blend'))
    glb = args.output / 'source.glb'
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB',
                              export_animations=False, export_extras=True,
                              export_yup=True)
    add_extras(glb, {'launchDisplay': profile})
    profile['derivedSha256'] = hashlib.sha256(glb.read_bytes()).hexdigest()
    (args.output / 'provenance.json').write_text(json.dumps(profile, indent=2))
    print('NES_DISPLAY_AUTHORED ' + json.dumps(profile))


if __name__ == '__main__':
    main()
