"""Verify text in assembled carton panels, including their actual mesh UVs.

Requires Pillow and the installed Windows OCR language. Keeps source imports
unchanged. An uncertain OCR result is a review requirement, never a pass or an
instruction to rotate artwork/geometry automatically.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import unicodedata

from PIL import Image


def visible_panel(model, mesh, *, side):
    if hashlib.sha256(mesh).hexdigest() != model['geometrySha256']:
        raise ValueError('Carton geometry digest differs')
    sign = 1 if side == 'front' else -1
    candidates = []
    for index, surface in enumerate(model['surfaces']):
        texture = surface['material'].get('textures', {}).get('albedo')
        if not texture or surface['material']['color'][3] < .99:
            continue
        points = [struct.unpack_from('<8f', mesh, surface['vertexOffset'] + i * 32)
                  for i in range(surface['vertexCount'])]
        if not points or any(p[5] * sign < .999 for p in points):
            continue
        low = [min(p[a] for p in points) for a in range(3)]
        high = [max(p[a] for p in points) for a in range(3)]
        width, height = high[0] - low[0], high[1] - low[1]
        if width <= 0 or height <= 0 or high[2] - low[2] > .0001:
            continue
        # Derive the source UV affine map from a real nondegenerate triangle.
        first = None
        for at in range(0, surface['indexCount'], 3):
            indices = struct.unpack_from('<3I', mesh, surface['indexOffset'] + at * 4)
            tri = [points[i] for i in indices]
            a, b, c = tri
            determinant = (b[0]-a[0])*(c[1]-a[1]) - (c[0]-a[0])*(b[1]-a[1])
            if abs(determinant) > 1e-10:
                first = tri
                break
        if first is None:
            continue
        a, b, c = first
        def uv(x, y):
            s = ((x-a[0])*(c[1]-a[1])-(y-a[1])*(c[0]-a[0])) / determinant
            t = ((b[0]-a[0])*(y-a[1])-(b[1]-a[1])*(x-a[0])) / determinant
            return [a[k]+s*(b[k]-a[k])+t*(c[k]-a[k]) for k in (6, 7)]
        if any(max(abs(u-v) for u,v in zip(uv(p[0],p[1]),p[6:8])) > .0001 for p in points):
            continue
        # Looking at the rear reverses the horizontal view axis, not vertical up.
        x = low[0] if sign == 1 else high[0]
        start = uv(x, high[1])
        right = uv(x + sign * width, high[1])
        bottom = uv(x, low[1])
        if any(not math.isfinite(v) or v < -.001 or v > 1.001
               for corner in [start, right, bottom] for v in corner):
            continue
        candidates.append({'surfaceIndex': index, 'surfaceName': surface.get('name'),
            'texture': texture, 'physicalWidth': width, 'physicalHeight': height,
            'uvCorners': [start, right, bottom], 'side': side,
            'area': width * height, 'depth': sign * high[2]})
    if not candidates:
        raise ValueError(f'No established planar printed {side} panel')
    return max(candidates, key=lambda p: (p['area'], p['depth']))


def assembled_panel(root, model, mesh, panel, *, maximum=1024):
    if hashlib.sha256(mesh).hexdigest() != model['geometrySha256']:
        raise ValueError('Carton geometry digest differs')
    name = panel['texture']
    if Path(name).name != name:
        raise ValueError('Texture must remain inside the model directory')
    body = (root / name).read_bytes()
    if hashlib.sha256(body).hexdigest() != model['textureFiles'][name]:
        raise ValueError('Carton texture digest differs')
    with Image.open(root / name) as source:
        if source.width * source.height > 64_000_000:
            raise ValueError('Carton image exceeds decode budget')
        source = source.convert('RGB')
        ratio = panel['physicalWidth'] / panel['physicalHeight']
        width, height = (maximum, max(2, round(maximum / ratio))) if ratio >= 1 else (
            max(2, round(maximum * ratio)), maximum)
        start, right, bottom = panel['uvCorners']
        coefficients = []
        for axis, extent in [(0, source.width - 1), (1, source.height - 1)]:
            coefficients.extend([(right[axis]-start[axis])*extent/(width-1),
                (bottom[axis]-start[axis])*extent/(height-1), start[axis]*extent])
        return source.transform((width, height), Image.Transform.AFFINE,
            coefficients, resample=Image.Resampling.BICUBIC)


def words(text):
    text = unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode().lower()
    return set(re.findall(r'[a-z]{3,}', text))


def orientation_evidence(records, *, title):
    brands = words('Nintendo Entertainment System Konami Capcom Bandai Taito '
        'Namco Tecmo Sunsoft Camerica Codemasters Mattel Jaleco Game Boy Advance')
    expected = words(title) - words('the and for with from')
    candidates = []
    for angle in [0, 90, 180, 270]:
        detected = words(records[angle].get('text', ''))
        anchors = detected & (brands | expected)
        candidates.append({'clockwiseDegrees': angle, 'anchors': sorted(anchors),
            'score': sum(len(word) for word in anchors),
            'text': records[angle].get('text', ''),
            'textAngle': records[angle].get('textAngle')})
    ordered = sorted(candidates, key=lambda row: (-row['score'], row['clockwiseDegrees']))
    best, second = ordered[:2]
    established = best['score'] >= 6 and best['score'] - second['score'] >= 4
    status = ('upright' if best['clockwiseDegrees'] == 0 else 'rotated') if established else 'uncertain'
    return {'status': status,
        'clockwiseCorrectionDegrees': best['clockwiseDegrees'] if established else None,
        'method': 'Relative orthogonal OCR with exact title/brand anchors; engine supplies no confidence',
        'candidates': candidates}


def verify(model_dir, output, *, title, language='en-US', manifest_name='model.json'):
    output.mkdir(parents=True, exist_ok=False)
    if Path(manifest_name).name != manifest_name:
        raise ValueError('Manifest must remain inside the model directory')
    manifest_path = model_dir / manifest_name
    model = json.loads(manifest_path.read_text(encoding='utf8'))
    mesh = (model_dir / 'model.mesh').read_bytes()
    report = {'schemaVersion': 1, 'modelManifestSha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
        'geometrySha256': model['geometrySha256'], 'textureFiles': model['textureFiles'],
        'expectedTitle': title, 'language': language, 'panels': {},
        'animation': {'canOpen': model.get('canOpen'),
            'sourceClips': model.get('sourceReference', {}).get('sourceAnimationClips', []),
            'verifiedMaxError': model.get('animationVerifiedMaxError'),
            'scope': 'Existing Blender source-animation comparison; OCR does not verify hinges'}}
    paths, prepared = [], {}
    for side in ['front', 'back']:
        try:
            panel = visible_panel(model, mesh, side=side)
            rendered = assembled_panel(model_dir, model, mesh, panel)
        except ValueError as error:
            report['panels'][side] = {'status': 'uncertain', 'reason': str(error)}
            continue
        records = {}
        # Busy illustrated covers can hide small publisher/seal lettering from
        # whole-page OCR. Also inspect source-bound top/bottom strips, without
        # repainting pixels or substituting a different source image.
        views = {'full': rendered,
            'top': rendered.crop((0,0,rendered.width,max(2,round(rendered.height*.3)))),
            'bottom': rendered.crop((0,round(rendered.height*.7),rendered.width,rendered.height))}
        for angle in [0, 90, 180, 270]:
            records[angle] = []
            for view, image in views.items():
                path = output / f'{side}-{angle:03d}{"" if view=="full" else "-"+view}.png'
                image.rotate(-angle, expand=True).save(path)
                paths.append(str(path.resolve()))
                records[angle].append(path)
        prepared[side] = (panel, records)
    request = output / 'ocr-input.json'
    request.write_text(json.dumps(paths), encoding='utf8')
    if paths:
        process = subprocess.run(['powershell.exe', '-NoProfile', '-File',
            str(Path(__file__).with_name('read_packaging_text.ps1')),
            '-ImageManifest', str(request.resolve()), '-LanguageTag', language],
            capture_output=True, check=True)
        (output/'ocr.ndjson').write_bytes(process.stdout)
        ocr = {str(Path(row['path']).resolve()):row for row in
            (json.loads(line) for line in process.stdout.decode('utf-8-sig').splitlines() if line.strip())}
        if set(ocr) != set(paths):
            raise ValueError('OCR response membership differs from requested images')
        for side, (panel, records) in prepared.items():
            evidence = orientation_evidence({angle:{'text':' '.join(
                ocr[str(path.resolve())]['text'] for path in samples)}
                for angle,samples in records.items()}, title=title)
            report['panels'][side] = {**panel, **evidence,
                'assembledImageSha256': hashlib.sha256(records[0][0].read_bytes()).hexdigest(),
                'ocrViews': [{'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
                    for samples in records.values() for path in samples]}
    animation = report['animation']
    opening_valid = (animation['canOpen'] is True and
        {'Open','Close'} <= set(animation['sourceClips']) and
        isinstance(animation['verifiedMaxError'], (int,float)) and
        math.isfinite(animation['verifiedMaxError']) and animation['verifiedMaxError'] <= .0001)
    report['status'] = 'verified' if (opening_valid and
        all(p['status'] == 'upright' for p in report['panels'].values()) and
        len(report['panels']) == 2) else 'review-required'
    (output/'report.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--title', required=True)
    parser.add_argument('--language', default='en-US')
    parser.add_argument('--manifest-name', default='model.json')
    args = parser.parse_args()
    report = verify(args.model_dir,args.output,title=args.title,language=args.language,
        manifest_name=args.manifest_name)
    print(json.dumps({'status':report['status'], 'panels':{
        side:{key:row.get(key) for key in ['status','clockwiseCorrectionDegrees']}
        for side,row in report['panels'].items()}}))
    if report['status'] != 'verified':
        raise SystemExit(2)


if __name__ == '__main__':
    main()
