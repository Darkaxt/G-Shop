"""Both artwork services participate; reviewed quality can beat pixel count."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0,str(Path(__file__).parents[1]))
import prepare_packaging_resources as packaging


def image(size=128, blur=0):
    value=Image.new('RGB',(size,size),'white')
    drawing=ImageDraw.Draw(value)
    for x in range(8,size-8,16): drawing.rectangle((x,8,x+4,size-8),fill='black')
    if blur: value=value.filter(ImageFilter.GaussianBlur(blur))
    body=io.BytesIO();value.save(body,format='PNG');return body.getvalue()


class ArtworkQualityTest(unittest.TestCase):
    def test_completed_crawl_bodies_avoid_repeated_authenticated_fetch(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);source=root/'crawl';source.mkdir();cache=root/'cache'
            body=image();sha=hashlib.sha256(body).hexdigest()
            (source/(sha+'.png')).write_bytes(body)
            media={'type':'box-2D','region':'us','providerReference':{
                'providerId':'screenscraper','providerGameId':'7','providerPlatformId':3,
                'mediaType':'box-2D','region':'us','memberIndex':None}}
            (source/'item.artwork.json').write_text(json.dumps([{
                'status':'matched','sha256':sha,'bytes':len(body),'file':sha+'.png','media':media}]))
            self.assertEqual(packaging.seed_crawl_artwork(source,cache)['seeded'],1)
            with patch.object(packaging,'HTTP_CACHE',cache), patch.object(packaging.requests,'Session') as session:
                actual=packaging.fetch(session,'https://api.screenscraper.fr/api2/mediaJeu.php',params={
                    'devid':'private-fixture','systemeid':3,'jeuid':'7','media':'box-2D(us)',
                    'outputformat':'png','maxwidth':1024,'maxheight':1024})
            self.assertEqual(actual,body)
            session.get.assert_not_called()

    def test_reviewed_lower_resolution_can_win_and_changed_hash_cannot(self):
        small, large=image(),image(1024,10)
        candidates=[{'source':'launchbox','body':large},{'source':'screenscraper','body':small}]
        review={'sourceId':'screenscraper','sourceSha256':hashlib.sha256(small).hexdigest(),
                'reason':'Crisp complete text; larger alternate is visibly blurred'}
        selected,audit=packaging.choose_artwork(candidates,review)
        self.assertEqual(selected['source'],'screenscraper')
        self.assertEqual(audit['method'],'reviewed-source-hash')
        self.assertEqual(len(audit['candidates']),2)
        self.assertNotIn('body',audit['candidates'][0])
        with self.assertRaisesRegex(ValueError,'Quality review'):
            packaging.choose_artwork(candidates,{**review,'sourceSha256':'f'*64})

    def test_measured_nomination_is_explicitly_not_visual_acceptance(self):
        selected,audit=packaging.choose_artwork([{'source':'launchbox','body':image()}])
        self.assertIsNotNone(selected)
        self.assertEqual(audit['method'],'measured-nomination-requires-visual-sample')
        self.assertEqual(audit['candidates'][0]['quality']['width'],128)

    def test_bad_provider_body_does_not_hide_the_other_valid_candidate(self):
        body=image()
        selected,audit=packaging.choose_artwork([{'source':'launchbox','body':b'bad response'},
                                                {'source':'screenscraper','body':body}])
        self.assertEqual(selected['source'],'screenscraper')
        self.assertEqual(audit['rejected'][0]['source'],'launchbox')
        selected,_=packaging.choose_artwork([{'source':'screenscraper','body':body}]*2,
            {'sourceId':'screenscraper','sourceSha256':hashlib.sha256(body).hexdigest(),
             'reason':'Byte-identical duplicate alternatives identify the same image'})
        self.assertEqual(selected['body'],body)

    def test_collector_requests_both_even_when_launchbox_has_every_face(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            lb,ss=image(256),image(128)
            ids=['00000001-0000-0000-0000-000000000000.png',
                 '00000002-0000-0000-0000-000000000000.png',
                 '00000003-0000-0000-0000-000000000000.png']
            images={'1':[{'Type':kind,'Region':'North America','FileName':name}
                          for kind,name in zip(packaging.ROLES,ids)]}
            row={'rank':None,'title':'Game','cache_row_id':1,
                'game':{'id':'g','platformId':'nes'},
                'edition':{'id':'e','gameId':'g','regions':['us'],'tags':[]},
                'metadata':{'providerGameId':'7','media':[
                    {'type':role,'region':'us','providerReference':{'providerPlatformId':3}}
                    for role in packaging.ROLES.values()]}}
            review={'g':{'box-2D':{'sourceId':'screenscraper','sourceSha256':hashlib.sha256(ss).hexdigest(),
                'reason':'Reviewed sharper compatible front'}}}
            (root/'review.json').write_text(json.dumps(review))
            (root/'projection.gz').write_bytes(b'fixture')
            args=SimpleNamespace(selection='collection',system='nes',projection=root/'projection.gz',
                launchbox=root/'index.zip',env=root/'credentials',panel_layouts=None,
                quality_review=root/'review.json',output=root/'pack.zip')
            auth={k:'fixture' for k in ['SCREENSCRAPER_DEVID','SCREENSCRAPER_DEVPASSWORD',
                'SCREENSCRAPER_SOFTNAME','SCREENSCRAPER_USERNAME','SCREENSCRAPER_PASSWORD']}
            def fetch(_session,url,**kwargs):
                return lb if 'images.launchbox-app.com' in url else None if 'mediaManuel' in url else ss
            with patch.object(packaging,'collection_selection',return_value=[row]), \
                 patch.object(packaging,'launchbox_index',return_value=({'1':'Game'},images,{'game':{'1'}})), \
                 patch.object(packaging,'website_box',return_value=None), \
                 patch.object(packaging,'read_env',return_value=auth), \
                 patch.object(packaging,'fetch',side_effect=fetch) as called:
                packaging.collect(args)
            calls=[c for c in called.call_args_list if 'mediaManuel' not in c.args[1]]
            self.assertEqual(len(calls),6)
            report=json.loads(args.output.with_suffix('.report.json').read_text())
            for role in packaging.ROLES.values():
                self.assertEqual({x['source'] for x in report[0]['artworkQuality'][role]['candidates']},
                                 {'launchbox','screenscraper'})
            with zipfile.ZipFile(args.output) as archive:
                resources=json.loads(archive.read('packaging.json'))['games'][0]['resources']
            front=next(r for r in resources if r['type']=='box-2D')['importReference']
            self.assertEqual(front['sourceId'],'screenscraper')
            self.assertEqual(front['sourceSha256'],hashlib.sha256(ss).hexdigest())
            # The independent LaunchBox lane still produces candidates when SS
            # reports actual quota exhaustion; no paired-quality claim is made.
            args.output=root/'quota-pack.zip';args.quality_review=None
            def quota_fetch(_session,url,**kwargs):
                if 'images.launchbox-app.com' in url:return lb
                raise packaging.ScreenScraperUnavailable('quotaExceeded')
            with patch.object(packaging,'collection_selection',return_value=[row]), \
                 patch.object(packaging,'launchbox_index',return_value=({'1':'Game'},images,{'game':{'1'}})), \
                 patch.object(packaging,'website_box',return_value=None), \
                 patch.object(packaging,'read_env',return_value=auth), \
                 patch.object(packaging,'fetch',side_effect=quota_fetch):
                packaging.collect(args)
            report=json.loads(args.output.with_suffix('.report.json').read_text())
            for role in packaging.ROLES.values():
                self.assertEqual(report[0]['artworkQuality'][role]['providers']['screenscraper'],'quotaExceeded')
                self.assertEqual(report[0]['artworkQuality'][role]['selectedSourceId'],'launchbox')


if __name__=='__main__': unittest.main()
