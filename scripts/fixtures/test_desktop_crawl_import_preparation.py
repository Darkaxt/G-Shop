"""Completed desktop results retain exact owners, hashes and transport bounds."""
import io,json,sys,tempfile,unittest,zipfile
from pathlib import Path
from PIL import Image
sys.path.insert(0,str(Path(__file__).parents[1]))
from prepare_desktop_crawl_import import prepare,digest
from prepare_packaging_resources import owner_key


class DesktopImportPreparationTest(unittest.TestCase):
    def inputs(self,root,count=26):
        crawl=root/'crawl';crawl.mkdir()
        image=io.BytesIO();Image.new('RGBA',(4,4),'red').save(image,format='PNG')
        body=image.getvalue();sha=digest(body);(crawl/(sha+'.png')).write_bytes(body)
        rows=[{'kind':'snapshot','record':{'editionDirty':0,'cacheDirty':0,'readOnly':True}}]
        items=[]
        for i in range(count):
            game={'id':f'g{i}','platformId':'nes','title':'Game','providerIds':{},'evidence':[]}
            aid={'providerId':'drive','sourceId':'s','accountId':'a','providerFileId':str(i)}
            artifact={'id':aid,'displayName':'Game.7z','version':'1','sizeBytes':100,
                      'providerChecksums':{'md5':'a'*32},'canDownload':True}
            edition={'id':f'e{i}','gameId':game['id'],'members':[{'artifactId':aid}],
                     'regions':[],'tags':[],'evidence':[],'providerIds':{}}
            request={'gameId':game['id'],'editionId':edition['id'],'platformId':'nes','romIdentifier':None}
            items.append({'request':request,'archive':{'path':'D:/fixture/Game.7z','artifact':artifact},'allowRawBinding':True})
            rows.extend([{'kind':'game','record':game},{'kind':'edition','record':edition},{'kind':'artifact','record':artifact}])
        rows.append({'kind':'end','rows':len(rows)})
        census=root/'census.ndjson';census.write_text('\n'.join(json.dumps(r) for r in rows),encoding='utf8')
        manifest=root/'manifest.json';manifest.write_text(json.dumps({'version':1,'items':items}),encoding='utf8')
        manifest_hash=digest(manifest.read_bytes());completed={}
        for item in items:
            key=digest(json.dumps(item,ensure_ascii=False,separators=(',',':')).encode())
            raw={'kind':'rawRom','filename':'Game.nes','sizeBytes':200,'md5':'b'*32,'sha1':'c'*40}
            row={'version':2,'key':key,'manifestSha256':manifest_hash,'status':'matched',
                'archiveReadStatus':'validated','request':{**item['request'],'romIdentifier':raw},
                'archiveObservation':{'raw':raw,'container':{'sizeBytes':100,'md5':'a'*32}},
                'artwork':[{'status':'matched','sha256':sha,'bytes':len(body),'file':sha+'.png',
                           'media':{'type':'box-2D','region':'us'}}]}
            (crawl/(key+'.json')).write_text(json.dumps(row),encoding='utf8');completed[key]='matched'
        (crawl/'checkpoint.json').write_text(json.dumps({'version':2,'manifestSha256':manifest_hash,'items':completed}),encoding='utf8')
        return census,manifest,crawl,sha

    def test_complete_scope_is_split_not_truncated_and_never_claims_publication(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);census,manifest,crawl,_=self.inputs(root)
            result=prepare(census,manifest,crawl,root/'out')
            self.assertEqual(result,{'preparedGames':26,'packs':2,'published':False})
            sizes=[]
            for path in sorted((root/'out').glob('*.zip')):
                with zipfile.ZipFile(path) as archive:
                    self.assertTrue(all(x.compress_type==zipfile.ZIP_STORED for x in archive.infolist()))
                    sizes.append(len(json.loads(archive.read('packaging.json'))['games']))
            self.assertEqual(sizes,[25,1])
            with self.assertRaises(FileExistsError):prepare(census,manifest,crawl,root/'out')

    def test_changed_body_and_incomplete_census_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);census,manifest,crawl,sha=self.inputs(root,1)
            (crawl/(sha+'.png')).write_bytes(b'corrupt')
            with self.assertRaisesRegex(ValueError,'body changed'):prepare(census,manifest,crawl,root/'out')
            self.assertFalse((root/'out').exists())
            census.write_text('\n'.join(census.read_text().splitlines()[:-1]))
            with self.assertRaisesRegex(ValueError,'Incomplete'):prepare(census,manifest,crawl,root/'out')

    def test_provider_scoping_retains_malformed_assertions(self):
        game={'id':'g','title':'Rename','providerIds':{'screenscraper':'7','igdb':'9'},'evidence':[]}
        edition={'id':'e','providerIds':{},'evidence':[{'source':'manual','kind':'providerId','value':'["igdb", 9]'}]}
        key=owner_key(game,edition,'screenscraper')
        game['title']='Display-only change';game['providerIds']['igdb']='10'
        self.assertEqual(key,owner_key(game,edition,'screenscraper'))
        edition['evidence']=[]
        self.assertNotEqual(key,owner_key(game,edition,'screenscraper'))


if __name__=='__main__': unittest.main()
