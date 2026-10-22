"""Build explicit private ROM-filename to reference-carton candidate bindings.

This does not identify a physical printing from a ROM. All candidates retain
their edition IDs, artwork receipts and region; hacks/virtual releases are not
silently assigned their base game's retail packaging.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import unicodedata


def title(value):
    value=value.split('(')[0].split('[')[0].strip()
    value=unicodedata.normalize('NFKD',value).encode('ascii','ignore').decode().lower()
    for roman,number in [('iv','4'),('iii','3'),('ii','2')]:
        value=re.sub(r'\b'+roman+r'\b',number,value)
    value=re.sub('[^a-z0-9]','',value)
    value=re.sub('^the|the$','',value)
    return value


def regions(edition):
    leaf=edition['editionFolder'].split('\\')[-1]
    codes=set(re.findall(r'(?:-|\b)(USA|CAN|GBR|UKV|FRA|NOE|FRG|SCN|ESP|ITA|HOL|AUS|EEC|EUR|JPN|KOR|HKG|ASI)(?:\b|\))',leaf))
    mapping={'USA':'USA','CAN':'Canada','GBR':'Europe','UKV':'Europe','FRA':'France',
        'NOE':'Germany','FRG':'Germany','SCN':'Europe','ESP':'Spain','ITA':'Italy',
        'HOL':'Europe','AUS':'Australia','EEC':'Europe','EUR':'Europe',
        'JPN':'Japan','KOR':'Korea','HKG':'Hong Kong','ASI':'Asia'}
    found={mapping[c] for c in codes}
    if '(HVC-' in leaf or '_FC-' in leaf or 'Famicom' in leaf:
        found={'Japan'}
    if not found:
        if '(HVC-' in leaf or '_FC-' in leaf or 'Famicom' in leaf: found={'Japan'}
        elif '_AME' in leaf: found={'USA','Canada'}
        elif '_EUR' in leaf: found={'Europe'}
        elif '_ASI' in leaf: found={'Asia'}
    return sorted(found)


def archive_regions(filename):
    known={'USA','Europe','Japan','World','Australia','Canada','Asia','Hong Kong',
        'Korea','China','Taiwan','Brazil','Russia','France','Germany','Spain',
        'Italy','Netherlands','Sweden','Denmark','Finland','Norway','United Kingdom'}
    for tag in re.findall(r'\(([^()]*)\)',filename):
        parts={p.strip() for p in tag.split(',')}
        if parts and parts<=known: return parts
    return set()


def is_retail_reference(filename):
    return '[' not in filename and not re.search(
        r'\((?:Aftermarket|Pirate|Proto[^)]*|Beta[^)]*|Demo[^)]*|[^)]*(?:Virtual Console|Switch|Collection|Archives|Retro-Bit|FamicomBox|Classic Mini|Classics Mini Mix|Disney Classic Games|QUByte Classics)[^)]*)\)',filename,re.I)


def apply_prepared_references(catalogue, prepared, imports, filenames):
    """Join reviewed derivatives by exact archive; never infer regional ownership.

    Preparation uses the existing catalogue schema and separately verified model
    receipts. Validate the complete selection before mutating its live catalogue.
    Original editions remain available; only explicit selected bindings change.
    """
    if (prepared.get('schemaVersion') != 1 or prepared.get('system') != 'nes' or
            not isinstance(prepared.get('editions'), list) or
            not isinstance(prepared.get('bindings'), dict)):
        raise ValueError('Invalid prepared NES references')
    editions = {e['id']: e for e in catalogue['editions']}
    additions = []
    seen = set()
    for entry in prepared['editions']:
        id = entry.get('id')
        digest = entry.get('manifestSha256')
        label = entry.get('label')
        if (not isinstance(id, str) or not re.fullmatch(r'nes-[a-f0-9]{12}', id) or
                id in seen or not isinstance(digest, str) or
                not re.fullmatch(r'[a-f0-9]{64}', digest) or
                not isinstance(label, str) or not 1 <= len(label) <= 180):
            raise ValueError('Invalid prepared carton edition')
        seen.add(id)
        file = imports/id/'model.json'
        raw = file.read_bytes()
        model = json.loads(raw)
        if (hashlib.sha256(raw).hexdigest() != digest or
                model.get('retailEditionId') != id or model.get('system') != 'nes' or
                model.get('resourceKind') != 'box' or model.get('canOpen') is not True):
            raise ValueError('Prepared carton differs from its receipt')
        if id in editions and editions[id]['manifestSha256'] != digest:
            raise ValueError('Prepared reference would replace a source edition')
        if id not in editions:
            editions[id] = entry
            additions.append(entry)
    bindings = {}
    for filename, ids in prepared['bindings'].items():
        if (filename not in filenames or not is_retail_reference(filename) or
                '/' in filename or '\\' in filename or not isinstance(ids, list) or
                not 1 <= len(ids) <= 32 or any(not isinstance(id, str) for id in ids) or
                len(ids) != len(set(ids)) or any(id not in seen for id in ids)):
            raise ValueError('Unreviewed or invalid prepared archive binding')
        selected = list(dict.fromkeys(ids + catalogue['bindings'].get(filename, [])))
        if len(selected) > 32:
            raise ValueError('Too many prepared carton choices')
        bindings[filename] = selected
    catalogue['editions'].extend(additions)
    catalogue['bindings'].update(bindings)


def main():
    p=argparse.ArgumentParser(); p.add_argument('--source-catalogue',type=Path,required=True)
    p.add_argument('--rom-census',type=Path,required=True); p.add_argument('--imports',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    p.add_argument('--prepared-references',type=Path,
        help='Reviewed exact bindings to supplied or prepared composite/reconstructed models')
    a=p.parse_args()
    source=json.loads(a.source_catalogue.read_text(encoding='utf-8'))
    editions=[e for e in source['editions'] if e['platform']=='NES - Famicom']
    assert len(editions)==623
    by_title=collections.defaultdict(list); output=[]
    for e in editions:
        manifest=a.imports/e['id']/'model.json'
        data=json.loads(manifest.read_text(encoding='utf-8'))
        assert data['retailEditionId']==e['id'] and data['canOpen']
        r=regions(e)
        entry={'id':e['id'],'label':e['editionFolder'].split('\\')[-1][-176:],
               'game':e['game'],'regions':r,'sourceEditionFolder':e['editionFolder'],
               'manifestSha256':hashlib.sha256(manifest.read_bytes()).hexdigest()}
        output.append(entry); by_title[title(e['game'])].append(entry)
    europe={'Europe','France','Germany','Spain','Italy','Netherlands','Sweden'}
    # Explicit observed title spelling aliases, never similarity/fuzzy matching.
    aliases={'legendofzelda2theadventureoflink':'zeldaiitheadventureoflink',
             'thelegendofzelda2adventureoflink':'zeldaiitheadventureoflink'}
    for key,target in aliases.items():
        if key in by_title: by_title[target].extend(by_title[key])
    bindings={}; excluded=[]; unmatched=[]; ambiguous=[]
    roms=json.loads(a.rom_census.read_text(encoding='utf-8'))['entries']
    for rom in roms:
        filename=rom['filename']
        if not is_retail_reference(filename):
            excluded.append(filename); continue
        region=archive_regions(filename)
        candidates=[]
        for e in by_title[title(filename)]:
            er=set(e['regions'])
            if not(region&er or region&europe and er&europe): continue
            if e['id'] not in candidates: candidates.append(e['id'])
        if candidates:
            assert len(candidates)<=32
            bindings[filename]=candidates
            if len(candidates)>1: ambiguous.append(filename)
        else: unmatched.append(filename)
    catalogue={'schemaVersion':1,'system':'nes','bindingMeaning':'regional reference artwork; exact physical printing unproven',
               'editions':output,'bindings':bindings}
    if a.prepared_references:
        apply_prepared_references(catalogue,
            json.loads(a.prepared_references.read_text(encoding='utf-8')),
            a.imports,{r['filename'] for r in roms})
        unmatched=[f for f in unmatched if f not in bindings]
    (a.imports/'catalogue.json').write_text(json.dumps(catalogue,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    report={'archives':len(roms),'cartonEditions':len(output),'referenceBoundArchives':len(bindings),
            'multipleReferenceChoices':len(ambiguous),'excludedNonRetailArchives':len(excluded),
            'unmatchedRetailArchives':unmatched,'ambiguousArchives':ambiguous,
            'exactOwnedPhysicalPrintingsEstablished':0,
            'limits':'Reference artwork candidates are not claims of an exact owned physical SKU.'}
    a.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if not isinstance(v,list)}))


if __name__=='__main__': main()
