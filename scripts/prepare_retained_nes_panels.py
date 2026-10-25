"""Carry unchanged selected NintAndBox cartons into the normal resource lane.

This prepares original panels, not game identities or a replacement model. Native
ownership, modification/printing gates, publication and visual acceptance remain
mandatory. New reconstructed cohorts do not implicitly cover retained cartons.
"""
import argparse
import copy
import hashlib
import io
import json
from pathlib import Path

from PIL import Image
from prepare_nes_box_catalogue import source_region_code
from prepare_packaging_resources import BOX_FACES, png


def digest(body):
    return hashlib.sha256(body).hexdigest()


def _source_file(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('Retained panel path leaves its source library')
    return path


def prepare(catalogue, library, runtime, output, *, filenames=None, panel_review=None):
    library, output = Path(library), Path(output)
    if catalogue.get('schemaVersion') != 1 or catalogue.get('system') != 'nes':
        raise ValueError('Expected the selected NES catalogue')
    source_file = library / 'reports/catalogue-full.json'
    source_body = source_file.read_bytes()
    sources = {r['id']: r for r in json.loads(source_body)['editions']}
    config_body = (library / 'reports/reproduction-configs.json').read_bytes()
    configs = {r['id']: r for r in json.loads(config_body)}
    selected = {r['id']: r for r in catalogue['editions']}
    output.mkdir(exist_ok=False)
    images = output / 'images'
    images.mkdir()
    candidates, held = [], []
    prepared_models = {}
    for filename, ids in catalogue['bindings'].items():
        if filenames is not None and filename not in filenames:
            continue
        model_id = ids[0]
        entry = selected[model_id]
        source = sources.get(model_id)
        if source is None:
            held.append({'filename': filename, 'modelId': model_id,
                         'reason': 'selected-model-not-in-retained-source-catalogue'})
            continue
        native = runtime['models'].get(model_id)
        if native is None or native['manifestSha256'] != entry['manifestSha256']:
            raise ValueError('Selected native manifest changed: ' + model_id)
        if (source['platform'] != 'NES - Famicom' or
                source['editionFolder'] != entry['sourceEditionFolder'] or
                source['status'] != 'verified-animated-edition' or
                native.get('sourceReference', {}).get('sha256') != source['modelSha256']):
            raise ValueError('Selected native model differs from retained source: ' + model_id)
        if model_id not in prepared_models:
            if digest(_source_file(library, source['model']).read_bytes()) != source['modelSha256']:
                raise ValueError('Retained model digest changed: ' + model_id)
            cfg = configs[model_id]
            region = source_region_code(source)
            languages = ['en'] if any(code in source['editionFolder'].split('\\')[-1]
                for code in ('USA', 'UKV', 'GBR')) else ['und']
            resources, evidence = [], {}
            review = (panel_review or {}).get(model_id)
            if review and (review.get('manifestSha256') != entry['manifestSha256'] or
                           not review.get('reason') or not review.get('nativeAssembledEvidence')):
                raise ValueError('Reviewed native panel mapping changed: ' + model_id)
            for face in BOX_FACES:
                mapping = review.get('faces', {}).get(face, {}) if review else {}
                panel_name = mapping.get('sourcePanel', face)
                rotation = mapping.get('clockwiseDegrees', 0)
                if rotation not in (0, 90, 180, 270):
                    raise ValueError('Panel rotation must be orthogonal')
                if face == 'bottom' and not cfg['panels'].get(face):
                    panel_name = 'bottom_' + source.get('bottomLidSheet', 'front')
                panel = cfg['panels'].get(panel_name)
                if panel is None:
                    raise ValueError('Retained selected carton lacks a required panel: ' + model_id + '/' + face)
                raw = _source_file(library, panel['file']).read_bytes()
                source_hash = digest(raw)
                if mapping and mapping.get('sourceSha256') != source_hash:
                    raise ValueError('Reviewed source panel digest changed: ' + model_id + '/' + face)
                original = source['printedFaceProvenance'].get(panel_name)
                if (source_hash != panel['cropSha256'] or original is None or
                        original['cropSha256'] != source_hash or
                        source_hash not in native['textureFiles'].values()):
                    raise ValueError('Retained panel digest differs from native texture: ' + model_id + '/' + face)
                with Image.open(io.BytesIO(raw)) as image:
                    rect = [0, 0, image.width, image.height]
                if rotation:
                    with Image.open(io.BytesIO(raw)) as image:
                        rotated = io.BytesIO()
                        image.rotate(-rotation, expand=True).save(rotated, format='PNG')
                    body = png(rotated.getvalue())
                else:
                    body = png(raw)
                body_hash = digest(body)
                path = images / (body_hash + '.png')
                if path.exists():
                    if digest(path.read_bytes()) != body_hash:
                        raise ValueError('Prepared image changed')
                else:
                    path.write_bytes(body)
                resources.append({'type': 'outer-box-' + face, 'region': region,
                    'importReference': {'sourceId': 'nintandbox',
                        'assetId': source_hash + '/' + face,
                        'sourceUrl': 'https://www.nintandbox.org/',
                        'sourceSha256': source_hash, 'sha256': body_hash,
                        'panel': rect, 'rotationDegrees': rotation,
                        'sourceRegion': region, 'sourceLanguages': languages,
                        'reconstruction': 'regionalPackaging' if region else 'composite'}})
                evidence[face] = {'sourcePanel': panel_name, 'source': original,
                                  'preparedSha256': body_hash}
                if mapping:
                    evidence[face]['nativePanelReview'] = review
            for face, role in [('front', 'box-2D'), ('back', 'box-2D-back'), ('right', 'box-2D-side')]:
                resources.append({**next(r for r in resources if r['type'] == 'outer-box-' + face), 'type': role})
            prepared_models[model_id] = {'resources': resources, 'panelSourceEvidence': evidence}
        candidate = {'filename': filename, 'modelId': model_id,
                     'title': source['game'], 'platform': 'nes',
                     'bindingEvidenceType': 'retainedNintandboxCatalogue',
                     'manifestSha256': entry['manifestSha256'],
                     'sourceModelSha256': source['modelSha256'],
                     'sourceEditionFolder': source['editionFolder'],
                     'completePanelSet': True, **copy.deepcopy(prepared_models[model_id])}
        candidate['key'] = digest(json.dumps([filename, model_id, entry['manifestSha256']],
                                            ensure_ascii=False, separators=(',', ':')).encode())
        candidates.append(candidate)
    result = {'sourceCatalogueSha256': digest(source_body),
              'sourceConfigsSha256': digest(config_body),
              'candidates': candidates, 'held': held,
              'published': False, 'nativeAccepted': False,
              'canonicalOwnershipBound': False}
    (output / 'preparation.json').write_text(json.dumps(result, indent=2), encoding='utf8')
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--catalogue', type=Path, required=True)
    parser.add_argument('--source-library', type=Path, required=True)
    parser.add_argument('--runtime-receipt', type=Path, required=True)
    parser.add_argument('--binding-list', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--panel-review', type=Path,
                        help='Hash-bound source-role/orientation review of the actual native faces')
    args = parser.parse_args()
    runtime = json.loads(args.runtime_receipt.read_text(encoding='utf8'))
    if runtime['catalogueSha256'] != digest(args.catalogue.read_bytes()):
        raise ValueError('Native capture belongs to another selected catalogue')
    rows = json.loads(args.binding_list.read_text(encoding='utf8'))['selectedBindingsOutsideHandoff']
    result = prepare(json.loads(args.catalogue.read_text(encoding='utf8')),
        args.source_library, runtime, args.output, filenames={r['filename'] for r in rows},
        panel_review=json.loads(args.panel_review.read_text(encoding='utf8')) if args.panel_review else None)
    print(json.dumps({'preparedSelectedBindings': len(result['candidates']),
        'held': len(result['held']), 'published': False, 'nativeAccepted': False}), flush=True)


if __name__ == '__main__':
    main()
