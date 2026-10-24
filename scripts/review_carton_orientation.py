"""Resolve uncertain OCR with an explicit visual review of hash-bound UV panels.

Keeps the original OCR report and candidate manifest. Known rotation, missing
animation or changed evidence cannot be waived by a visual-review receipt.
"""
import argparse
import copy
import hashlib
import io
import json
import math
from pathlib import Path

from verify_carton_orientation import assembled_panel, visible_panel


def reviewed_report(report, review, *, original_report_sha256):
    animation=report.get('animation',{})
    error=animation.get('verifiedMaxError')
    panels=report.get('panels',{})
    if (report.get('status')!='review-required' or set(panels)!={'front','back'} or
            any(p.get('status') not in {'upright','uncertain'} for p in panels.values()) or
            animation.get('canOpen') is not True or
            not {'Open','Close'}<=set(animation.get('sourceClips',[])) or
            type(error) not in {int,float} or not math.isfinite(error) or error>.0001):
        raise ValueError('Only uncertain OCR with verified opening can receive visual review')
    uncertain={side for side,panel in panels.items() if panel['status']=='uncertain'}
    if (not uncertain or review.get('version')!=1 or
            review.get('originalReportSha256')!=original_report_sha256 or
            review.get('modelManifestSha256')!=report.get('modelManifestSha256') or
            review.get('geometrySha256')!=report.get('geometrySha256') or
            not isinstance(review.get('reviewer'),str) or not review['reviewer'].strip() or
            not isinstance(review.get('panels'),dict) or set(review['panels'])!=uncertain):
        raise ValueError('Visual review does not own this complete uncertain evidence')
    result=copy.deepcopy(report)
    for side in uncertain:
        observation=review['panels'][side];digest=panels[side].get('assembledImageSha256')
        if (not isinstance(digest,str) or len(digest)!=64 or
                observation.get('assembledImageSha256')!=digest or
                type(observation.get('clockwiseCorrectionDegrees')) is not int or
                observation['clockwiseCorrectionDegrees']!=0 or
                not isinstance(observation.get('reason'),str) or
                len(observation['reason'].strip())<20):
            raise ValueError('Visual observation must describe the unchanged upright assembled panel')
        result['panels'][side].update(ocrStatus='uncertain',status='upright',
            clockwiseCorrectionDegrees=0,visualReview=observation)
    result.update(status='verified',originalOcrReportSha256=original_report_sha256,
        visualReviewer=review['reviewer'])
    return result


def accept_review(model_dir, review_path, *, report_path=None):
    model_dir=Path(model_dir)
    manifest_path=model_dir/'model.pending.json'
    raw=manifest_path.read_bytes();model=json.loads(raw)
    report_path=Path(report_path) if report_path is not None else model_dir/'text-orientation/report.json'
    if not report_path.resolve().is_relative_to(model_dir.resolve()):
        raise ValueError('Orientation evidence must stay inside its candidate import')
    report_body=report_path.read_bytes();report=json.loads(report_body)
    review_body=Path(review_path).read_bytes();review=json.loads(review_body)
    if (hashlib.sha256(raw).hexdigest()!=report['modelManifestSha256'] or
            model['geometrySha256']!=report['geometrySha256'] or
            model['textureFiles']!=report['textureFiles'] or
            model.get('canOpen') is not True or
            model.get('animationVerifiedMaxError')!=report['animation']['verifiedMaxError'] or
            model.get('sourceReference',{}).get('sourceAnimationClips')!=report['animation']['sourceClips']):
        raise ValueError('The converted model differs from the reviewed evidence')
    mesh=(model_dir/'model.mesh').read_bytes()
    if hashlib.sha256(mesh).hexdigest()!=model['geometrySha256']:
        raise ValueError('The reviewed geometry changed')
    for name,digest in model['textureFiles'].items():
        if Path(name).name!=name or hashlib.sha256((model_dir/name).read_bytes()).hexdigest()!=digest:
            raise ValueError('The reviewed texture changed')
    for side,panel in report['panels'].items():
        actual=visible_panel(model,mesh,side=side)
        if actual['surfaceIndex']!=panel['surfaceIndex']:
            raise ValueError('The reviewed visible surface changed')
        image=assembled_panel(model_dir,model,mesh,actual)
        output=io.BytesIO();image.save(output,format='PNG')
        if hashlib.sha256(output.getvalue()).hexdigest()!=panel['assembledImageSha256']:
            raise ValueError('The assembled panel differs from the inspected image')
        for view in panel.get('ocrViews',[]):
            if Path(view['file']).name!=view['file'] or hashlib.sha256((report_path.parent/view['file']).read_bytes()).hexdigest()!=view['sha256']:
                raise ValueError('Original OCR view evidence changed')
    result=reviewed_report(report,review,original_report_sha256=hashlib.sha256(report_body).hexdigest())
    result['visualReviewReceiptSha256']=hashlib.sha256(review_body).hexdigest()
    destination=report_path.parent/'visual-review-report.json'
    report_bytes=json.dumps(result,indent=2).encode('utf8')
    model['cartonTextOrientation']={'status':'verified','reportSha256':hashlib.sha256(report_bytes).hexdigest(),
        'validatedBaseManifestSha256':report['modelManifestSha256'],'geometrySha256':model['geometrySha256'],
        'frontSurfaceIndex':report['panels']['front']['surfaceIndex'],
        'backSurfaceIndex':report['panels']['back']['surfaceIndex'],'clockwiseCorrectionDegrees':0,
        'evidence':destination.relative_to(model_dir).as_posix()}
    if destination.exists() or (model_dir/'model.json').exists():
        raise FileExistsError('Preserve the existing accepted model/review')
    with destination.open('xb') as stream:stream.write(report_bytes)
    with (model_dir/'model.json').open('x',encoding='utf8') as stream:json.dump(model,stream,indent=2)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-dir',type=Path,required=True)
    parser.add_argument('--review',type=Path,required=True)
    parser.add_argument('--report',type=Path,
        help='Retained recheck report inside this candidate; default text-orientation/report.json')
    args=parser.parse_args()
    result=accept_review(args.model_dir,args.review,report_path=args.report)
    print(json.dumps({'status':result['status'],'visualReview':True,'originalOcrPreserved':True}))


if __name__=='__main__':main()
