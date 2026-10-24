"""A visual review resolves uncertain OCR without discarding its evidence."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).parents[1]))
from review_carton_orientation import reviewed_report


class CartonOrientationReviewTest(unittest.TestCase):
    def fixture(self):
        report={'status':'review-required','modelManifestSha256':'a'*64,
            'geometrySha256':'b'*64,'textureFiles':{'front.png':'c'*64},
            'animation':{'canOpen':True,'sourceClips':['Open','Close'],'verifiedMaxError':0},
            'panels':{'front':{'status':'uncertain','surfaceIndex':0,
                'assembledImageSha256':'d'*64,'candidates':[{'clockwiseDegrees':0,'score':5}]},
                'back':{'status':'upright','surfaceIndex':1,'assembledImageSha256':'e'*64}}}
        review={'version':1,'originalReportSha256':'f'*64,
            'modelManifestSha256':'a'*64,'geometrySha256':'b'*64,
            'reviewer':'Agent visual inspection','panels':{'front':{
                'assembledImageSha256':'d'*64,'clockwiseCorrectionDegrees':0,
                'reason':'The mapped title and publisher lettering are visibly upright.'}}}
        return report,review

    def test_visual_review_preserves_original_uncertain_ocr(self):
        report,review=self.fixture();original=copy.deepcopy(report)
        result=reviewed_report(report,review,original_report_sha256='f'*64)
        self.assertEqual(report,original)
        self.assertEqual(result['status'],'verified')
        self.assertEqual(result['panels']['front']['ocrStatus'],'uncertain')
        self.assertEqual(result['panels']['front']['candidates'],report['panels']['front']['candidates'])
        self.assertEqual(result['panels']['front']['status'],'upright')

    def test_changed_evidence_and_missing_review_do_not_pass(self):
        report,review=self.fixture()
        for key in ['originalReportSha256','modelManifestSha256','geometrySha256']:
            changed=copy.deepcopy(review);changed[key]='0'*64
            with self.assertRaises(ValueError):reviewed_report(report,changed,original_report_sha256='f'*64)
        for change in [{'assembledImageSha256':'0'*64},{'clockwiseCorrectionDegrees':90},{'reason':''}]:
            changed=copy.deepcopy(review);changed['panels']['front'].update(change)
            with self.assertRaises(ValueError):reviewed_report(report,changed,original_report_sha256='f'*64)
        review['panels']={}
        with self.assertRaises(ValueError):reviewed_report(report,review,original_report_sha256='f'*64)

    def test_review_cannot_waive_known_rotation_or_missing_opening(self):
        for mutation in ['rotation','animation']:
            report,review=self.fixture()
            if mutation=='rotation':report['panels']['front']['status']='rotated'
            else:report['animation']['canOpen']=False
            with self.assertRaises(ValueError):reviewed_report(report,review,original_report_sha256='f'*64)


if __name__=='__main__':unittest.main()
