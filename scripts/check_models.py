"""Host-side readiness check for the private 3D model tree (MODEL-CURATION-01).

Validates a models tree in the device layout (`RShop/models/...`) without the APK:
every model.json/booklet.json manifest has its mesh (geometry hash, surface and
index ranges), its textures (present, receipted, hash-matched) and records which
motion data it carries; catalogues (NES boxes, Game & Watch variants) resolve;
and every model key the app code expects is present.

Streams all hashing; never loads a mesh whole except for index-range checks on
meshes up to 20 MiB (the app's own limit).

usage: python -I scripts/check_models.py ROOT [--json OUT] [--repo REPO]
"""
import argparse
import hashlib
import json
import os
import re
import struct
import sys

# Fixed keys the app resolves (console_model.dart, gba_cartridge_model.dart,
# packaging_model.dart, nes_media_catalogue.dart). NES cartridge styles are read
# from lib/models/nes_cartridge_model.dart so this list cannot drift from code.
FIXED = [
    'consoles/nes', 'consoles/nes/variants/front-loader',
    'consoles/nes/variants/top-loader', 'consoles/nes/variants/famicom',
    'consoles/nes/variants/dendy', 'consoles/nes/launch/front-loader',
    'consoles/nes/launch/top-loader', 'consoles/nes/launch/display',
    'consoles/gameandwatch', 'consoles/gba', 'cartridges/gba',
    'cartridges/gba/boktai', 'cartridges/gba/twisted-us', 'cartridges/gba/yoshi-us',
    'cartons/gba', 'cartons/gba/boktai', 'cartons/gba/twisted-us',
    'cartons/gba/yoshi-us', 'consoles/snes',
]
MOTION_KEYS = ('poseCenters', 'openingDurationMs', 'launch', 'launchCalibration',
               'keyframes', 'animation', 'animations', 'insertion', 'cartridgeSlot',
               'lid', 'flap', 'selectorScene')


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def check_manifest(directory, name):
    path = os.path.join(directory, name + '.json')
    issues = []
    result = {'issues': issues}
    if os.path.getsize(path) > 1 << 20:
        issues.append('manifest over 1 MiB')
        return result
    try:
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
    except ValueError as e:
        issues.append(f'invalid json: {e}')
        return result
    if not isinstance(data, dict) or 'surfaces' not in data:
        return None
    mesh = os.path.join(directory, data.get('meshFile') or name + '.mesh')
    if not os.path.exists(mesh):
        mesh = os.path.join(directory, name + '.mesh')
    surfaces = data['surfaces']
    if not os.path.exists(mesh):
        issues.append('mesh missing')
    else:
        size = os.path.getsize(mesh)
        want = data.get('geometrySha256') or data.get('meshSha256')
        if size > 20 << 20:
            issues.append('mesh over 20 MiB')
        elif not want:
            issues.append('no geometry hash')
        else:
            with open(mesh, 'rb') as f:
                body = f.read()
            if hashlib.sha256(body).hexdigest() != want:
                issues.append('mesh hash mismatch')
            for s in surfaces:
                vo, vc, io, ic = (s.get(k, -1) for k in
                                  ('vertexOffset', 'vertexCount', 'indexOffset', 'indexCount'))
                if vo < 0 or vc <= 0 or io < vo + vc * 32 or ic <= 0 or ic % 3 or io + ic * 4 > size:
                    issues.append('invalid surface range')
                    break
                if max(struct.unpack_from(f'<{ic}I', body, io)) >= vc:
                    issues.append('triangle index out of range')
                    break
    receipts = data.get('textureFiles') or {}
    refs = set()
    for s in surfaces:
        refs.update(((s.get('material') or {}).get('textures') or {}).values())
    textures = refs | set(receipts)
    missing = sorted(t for t in textures if not os.path.exists(os.path.join(directory, t)))
    if missing:
        issues.append(f'textures missing: {", ".join(missing[:5])}')
    if receipts:
        unreceipted = sorted(t for t in refs if t not in receipts)
        if unreceipted:
            issues.append(f'textures without receipt: {len(unreceipted)}')
        bad = sorted(t for t, h in receipts.items()
                     if os.path.exists(os.path.join(directory, t))
                     and sha(os.path.join(directory, t)) != h)
        if bad:
            issues.append(f'texture hash mismatch: {", ".join(bad[:5])}')
    motion = [k for k in MOTION_KEYS if k in data]
    if any(s.get('openingHinges') for s in surfaces):
        motion.append('openingHinges')
    if any(s.get('pivot') for s in surfaces):
        motion.append('pivots')
    result.update(surfaces=len(surfaces),
                  triangles=sum(s.get('indexCount', 0) // 3 for s in surfaces),
                  textures=len(textures), motion=motion)
    return result


def nes_styles(repo):
    path = os.path.join(repo, 'lib', 'models', 'nes_cartridge_model.dart')
    with open(path, encoding='utf-8') as f:
        source = f.read()
    block = source[source.index('static const labels = {'):]
    block = block[:block.index('};')]
    return re.findall(r"^\s*'([a-z0-9-]+)':", block, re.M)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root')
    parser.add_argument('--json')
    parser.add_argument('--repo', default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    args = parser.parse_args()
    root = os.path.abspath(args.root)
    models = {}
    for directory, dirs, files in os.walk(root):
        dirs.sort()
        for name in ('model', 'booklet'):
            if name + '.json' in files:
                checked = check_manifest(directory, name)
                if checked is not None:
                    key = os.path.relpath(directory, root).replace('\\', '/')
                    models['booklet' if name == 'booklet' else key] = checked
    problems = []
    for key, checked in sorted(models.items()):
        for issue in checked['issues']:
            problems.append(f'{key}: {issue}')
    expected = FIXED + ['booklet'] + [f'cartridges/nes/{s}' for s in nes_styles(args.repo)]
    for key in expected:
        if key not in models:
            problems.append(f'{key}: expected by the app but absent')
    catalogue = os.path.join(root, 'boxes', 'nes', 'catalogue.json')
    if os.path.exists(catalogue):
        with open(catalogue, encoding='utf-8') as f:
            data = json.load(f)
        ids = set()
        for edition in data['editions']:
            ids.add(edition['id'])
            manifest = os.path.join(root, 'boxes', 'nes', edition['id'], 'model.json')
            if not os.path.exists(manifest):
                problems.append(f'boxes/nes/{edition["id"]}: catalogue edition absent')
            elif edition.get('manifestSha256') and sha(manifest) != edition['manifestSha256']:
                problems.append(f'boxes/nes/{edition["id"]}: manifest hash differs from catalogue')
        bindings = data['bindings'].items() if isinstance(data['bindings'], dict) else data['bindings']
        for archive, editions in bindings:
            for edition in editions:
                if edition not in ids:
                    problems.append(f'boxes/nes catalogue: {archive} binds unknown {edition}')
    else:
        problems.append('boxes/nes/catalogue.json: absent')
    for kind in ('handhelds', 'boxes'):
        variants = os.path.join(root, kind, 'gameandwatch', 'variants.json')
        if not os.path.exists(variants):
            continue
        with open(variants, encoding='utf-8') as f:
            groups = json.load(f)['groups']
        for group in groups:
            for model in group['models']:
                key = f'{kind}/gameandwatch/{model["directory"]}'
                if key not in models:
                    problems.append(f'{key}: listed in variants.json but absent')
    summary = {}
    for key in models:
        top = key.split('/')[:2]
        summary['/'.join(top)] = summary.get('/'.join(top), 0) + 1
    for group, count in sorted(summary.items()):
        print(f'{group}: {count} model(s)')
    with_motion = sum(1 for m in models.values() if m.get('motion'))
    print(f'TOTAL models={len(models)} with_motion={with_motion} problems={len(problems)}')
    for problem in problems:
        print('PROBLEM', problem)
    if args.json:
        with open(args.json, 'w', encoding='utf-8') as f:
            json.dump({'models': models, 'problems': problems}, f, indent=1)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
