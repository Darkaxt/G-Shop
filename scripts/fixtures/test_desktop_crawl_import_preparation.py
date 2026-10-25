"""Completed desktop results retain exact owners, hashes and transport bounds."""
import io,json,sys,tempfile,unittest,zipfile
from pathlib import Path
from PIL import Image
sys.path.insert(0,str(Path(__file__).parents[1]))
from prepare_desktop_crawl_import import prepare,digest
from prepare_packaging_resources import owner_key


class DesktopImportPreparationTest(unittest.TestCase):
    def test_explicit_delta_keeps_full_checkpoint_and_selected_owner_only(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);census,manifest,crawl,_=self.inputs(root,2)
            before=(crawl/'checkpoint.json').read_bytes()
            first=next(iter(json.loads(before)['items']))
            (crawl/(first+'.json')).unlink()
            prepare(census,manifest,crawl,root/'out',edition_ids=['e1'])
            receipt=json.loads((root/'out/preparation.json').read_text())
            self.assertEqual(receipt['selectionScope'],'selected-editions')
            self.assertEqual(receipt['editionFilter'],['e1'])
            self.assertEqual(receipt['manifestItems'],2)
            self.assertEqual(receipt['selectedManifestItems'],1)
            self.assertEqual(len(receipt['capturedCheckpoint']['items']),2)
            self.assertEqual((crawl/'checkpoint.json').read_bytes(),before)
            with zipfile.ZipFile(root/'out/desktop-resources-0001.zip') as archive:
                entries=json.loads(archive.read('packaging.json'))['games']
                self.assertEqual([r['editionId'] for r in entries],['e1'])

    def test_delta_rejects_missing_or_duplicate_current_edition_before_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);census,manifest,crawl,_=self.inputs(root,2)
            for selected in [['missing'],['e0','e0'],[]]:
                with self.assertRaisesRegex(ValueError,'edition selection'):
                    prepare(census,manifest,crawl,root/'out',edition_ids=selected)
                self.assertFalse((root/'out').exists())

    def test_delta_preserves_selected_provider_conflict_without_reimporting_old_hold(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);census,manifest,crawl,_=self.inputs(root,3)
            keys=list(json.loads((crawl/'checkpoint.json').read_text())['items'])
            holds=root/'holds.json'
            holds.write_text(json.dumps({'version':1,'holds':[
                {'key':key,'sourceSha256':digest((crawl/(key+'.json')).read_bytes()),
                 'reason':'Conflicting sequel identity'} for key in keys[:2]]}))
            prepare(census,manifest,crawl,root/'out',edition_ids=['e1','e2'],review_holds=holds)
            receipt=json.loads((root/'out/preparation.json').read_text())
            self.assertEqual(receipt['preparedGames'],1)
            self.assertEqual([r['key'] for r in receipt['qualityHolds']],[keys[1]])

    def test_reviewed_provider_identity_conflict_is_held_by_source_hash(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);census,manifest,crawl,_=self.inputs(root,2)
            checkpoint=json.loads((crawl/'checkpoint.json').read_text())
            key=next(iter(checkpoint['items']));source=crawl/(key+'.json')
            holds=root/'reviews.json'
            holds.write_text(json.dumps({'version':1,'holds':[{
                'key':key,'sourceSha256':digest(source.read_bytes()),
                'reason':'Provider identifies Vol.1 for the requested Vol.3.'}]}))
            prepare(census,manifest,crawl,root/'out',review_holds=holds)
            receipt=json.loads((root/'out/preparation.json').read_text())
            self.assertEqual(receipt['preparedGames'],1)
            self.assertEqual(receipt['qualityHolds'][0]['key'],key)
            self.assertEqual(receipt['qualityHolds'][0]['kind'],'providerIdentityReview')
            source.write_text(source.read_text()+' ')
            with self.assertRaisesRegex(ValueError,'Reviewed source changed'):
                prepare(census,manifest,crawl,root/'changed',review_holds=holds)

    def inputs(self,root,count=26):
        crawl=root/'crawl';crawl.mkdir()
        image=io.BytesIO();pixels=Image.new('RGBA',(4,4),'red');pixels.putpixel((0,0),(0,0,255,255));pixels.save(image,format='PNG')
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

    def test_explicit_response_reuse_retains_match_proof_without_ratings(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);census,manifest,crawl,_=self.inputs(root,1)
            checkpoint=json.loads((crawl/'checkpoint.json').read_text())
            key=next(iter(checkpoint['items']));source=crawl/(key+'.json')
            row=json.loads(source.read_text())
            row['record']={'gameId':'g0','editionId':'e0','platformId':'nes',
                'providerId':'screenscraper','providerGameId':'42',
                'matchMethod':'rawRomHashAndSize','ratings':[{'mustNotImport':True}]}
            row['officialRomEvidence']={'source':'screenscraper','kind':'exactRomOfficialRelease','value':'proof'}
            source.write_text(json.dumps(row))
            prepare(census,manifest,crawl,root/'out',reuse_lookup=True)
            with zipfile.ZipFile(root/'out/desktop-resources-0001.zip') as archive:
                m=json.loads(archive.read('packaging.json'))
                self.assertTrue(m['reuseProviderResponse'])
                lookup=m['games'][0]['lookup']
                self.assertEqual(lookup['record']['ratings'],[])
                self.assertEqual(lookup['request'],row['request'])
                self.assertEqual(lookup['officialRomEvidence'],row['officialRomEvidence'])

    def test_provider_placeholder_keeps_quality_hold_instead_of_publishing_body(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);census,manifest,crawl,_=self.inputs(root,1)
            key=next(iter(json.loads((crawl/'checkpoint.json').read_text())['items']))
            source=crawl/(key+'.json');row=json.loads(source.read_text())
            body=io.BytesIO();Image.new('RGB',(8,8),'green').save(body,format='PNG')
            body=body.getvalue();sha=digest(body);(crawl/(sha+'.png')).write_bytes(body)
            row['artwork'][0].update(sha256=sha,bytes=len(body),file=sha+'.png')
            row['record']={'gameId':'g0','editionId':'e0','platformId':'nes',
                'providerId':'screenscraper','providerGameId':'42',
                'matchMethod':'rawRomHashAndSize','ratings':[]}
            source.write_text(json.dumps(row))
            prepare(census,manifest,crawl,root/'out',reuse_lookup=True)
            with zipfile.ZipFile(root/'out/desktop-resources-0001.zip') as archive:
                entry=json.loads(archive.read('packaging.json'))['games'][0]
                self.assertEqual(entry['artwork'],[])
                outcome=entry['lookup']['artworkOutcomes'][0]
                self.assertEqual(outcome['status'],'needsReview')
                self.assertEqual(outcome['providerStatus'],'matched')
                self.assertEqual(outcome['sha256'],sha)
                self.assertEqual(outcome['reason'],'blank-or-transparent-placeholder')
                self.assertNotIn('images/'+sha+'.png',archive.namelist())


if __name__=='__main__': unittest.main()
