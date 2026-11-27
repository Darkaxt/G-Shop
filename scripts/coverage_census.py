"""S26 coverage census (issue #6): per source archive, is its physical-resource set bound?

Read-only. Denominator = the current archive listing of each ROM folder (one
non-recursive listing per folder). Bindings come from the Windows master
catalogue store, which is what tool/publish_catalogue_test.dart publishes (a dry
run with 0 writes proves Drive matches it).

Counted (GBA/NES): the archive's edition has a carton AND a standalone
cartridge label texture (`support-texture`), each with an image body in the
store or already published in the Drive catalogue (a published asset's
`media_key`; the publisher carries those without a local body). A carton is either all six packaging outer-box faces or the
flat front and back (`box-2D`, `box-2D-back`) from packaging or ScreenScraper,
which the app's box renderer folds into the 3D carton (unboxing_preview.dart
boxPanelPath). A missing spine/top/bottom renders as a plain generic face (owner
best-effort box rulings 2026-10-17 and 2026-10-22, restated 2026-11-26), so the
spine (`box-2D-side`) is reported separately and does not block the count. A complete-cartridge picture (`support-2D`)
is not a label. e-Reader cards and Multiboot payloads have no physical-resource
set: counted once the edition has a sourced `facts` record (spec revision 190,
COVERAGE-FACTS-01). Counted (G&W): the installed handheld model and its carton
model both exist.

Release classes (owner objective 2026-11-27: full official coverage first). Every
archive is also classed from its No-Intro name tags and source folder, in this
order: 'fan' (translation/hack folders or [T-..]/[h..] tags), 'prerelease'
(Beta/Proto/Demo/Sample/Kiosk/Debug/Program tags, excluded from short-term
support), 'aftermarket' (Aftermarket/Homebrew tags or the iNES2 Aftermarket and
Private folders), 'unlicensed' (Unl/Pirate) and otherwise 'official' (licensed
retail, official rereleases, e-Reader and Multiboot). Per-class totals are
reported as class:<name>, and officialPercent is the headline figure. labelStandIn
counts covered archives whose label is another printing of the same game
(reconstruction=regionalPackaging) rather than their own.

Usage: python -I coverage_census.py [--store D:/RShopPrivate/CatalogueStore]
       [--database COPY_OF_metadata.sqlite] [--catalogue "H:/My Drive/R-Shop Metadata"]
       [--roms "H:/My Drive/Roms"] [--models D:/RShopPrivate/Models] [--json OUT]
"""
import argparse
import collections
import hashlib
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

FOLDERS = {'gba': 'Nintendo - Game Boy Advance', 'nes': 'Nintendo - Nintendo Entertainment System',
           'gameandwatch': 'Nintendo - Game & Watch'}
CARTON = {f'outer-box-{f}' for f in ('front', 'back', 'top', 'bottom', 'left', 'right')}
FLAT = {'box-2D', 'box-2D-back'}
SPINE = 'box-2D-side'
LABEL = 'support-texture'
FACT_ONLY = {'e-Reader', 'Multiboot'}  # ROM subfolders whose entries are covered by facts


FAN_FOLDERS = {'Translations', 'T-En', 'Hacks', 'Color Hacks'}
AFTERMARKET_FOLDERS = ('Aftermarket', 'Private')
PRERELEASE = re.compile(r'\b(?:Beta|Proto|Demo|Sample|Kiosk|Debug|Program)\b')


def release_class(name):
    """official / unlicensed / aftermarket / prerelease / fan, from tags and folder."""
    base = name.split('/')[-1]
    top = name.split('/')[0] if '/' in name else ''
    words = {w.strip() for tag in re.findall(r'\(([^)]*)\)', base) for w in tag.split(',')}
    if top in FAN_FOLDERS or re.search(r'\[(?:T-|h\d*[^\]]*\])', base):
        return 'fan'
    if any(PRERELEASE.search(w) for w in words):
        return 'prerelease'
    if words & {'Aftermarket', 'Homebrew'} or top.startswith(AFTERMARKET_FOLDERS):
        return 'aftermarket'
    if words & {'Unl', 'Pirate'}:
        return 'unlicensed'
    return 'official'


EXCLUDED = {'saves', 'patches'}  # saves are not archives; derived patch builds are counted separately


def listing(folder, prefix=''):
    """Archives under one ROM folder, bounded to that folder; returns relative paths."""
    names = []
    with os.scandir(folder) as entries:
        for e in entries:
            if e.name.startswith('.') or e.name.lower() == 'desktop.ini':
                continue
            if e.is_dir():
                if e.name.lower() not in EXCLUDED:
                    names += listing(e.path, f'{prefix}{e.name}/')
            elif e.is_file():
                names.append(prefix + e.name)
    return sorted(names)


def media_key(media):
    """metadataMediaKey (metadata_artwork_selection.dart): sha256 of Dart jsonEncode."""
    return hashlib.sha256(json.dumps([media, 'png-1024-v1'], separators=(',', ':'),
                                     ensure_ascii=False).encode()).hexdigest()


def published_keys(catalogue, platforms):
    """media_key of every asset in the published catalogue manifests (one
    metadata.json per game folder; bounded to the platform folders)."""
    keys = set()
    for platform in platforms:
        root = Path(catalogue, platform)
        if not root.is_dir():
            continue
        with os.scandir(root) as entries:
            for e in entries:
                m = Path(e.path, 'metadata.json')
                if e.is_dir() and m.is_file():
                    keys |= {a.get('media_key') for a in json.loads(m.read_text(encoding='utf-8')).get('assets', [])}
    return keys


def store_roles(store, database=None, published=frozenset()):
    """Roles with a local image body. Pass a copy of metadata.sqlite as `database`
    while a store writer runs, so this reader cannot hold its lock."""
    db = sqlite3.connect(f'file:{Path(database or Path(store, "metadata.sqlite")).as_posix()}?mode=ro', uri=True)
    artwork = Path(store, 'artwork')
    local = {k for k, f in db.execute('SELECT media_key, filename FROM metadata_artwork_cache')
             if (artwork / f).is_file()}
    bodies = local | set(published)
    archive_edition = {}
    for edition, artifacts in db.execute('SELECT edition_id, artifacts_json FROM identity_bindings'):
        for artifact in json.loads(artifacts):
            archive_edition[artifact.get('displayPath', '')] = edition
    roles = collections.defaultdict(set)
    facts = {e for (e,) in db.execute("SELECT edition_id FROM records WHERE provider_id = 'facts'")}
    for edition, provider, record in db.execute(
            "SELECT edition_id, provider_id, record_json FROM records WHERE provider_id IN ('packaging','screenscraper','reference')"):
        # A reference reuses another edition's media: the publisher can only
        # ship it from a local body (published copies sit in the retail folder).
        usable = local if provider == 'reference' else bodies
        media = [m for m in json.loads(record).get('media', []) if media_key(m) in usable]
        roles[edition] |= {('packaging:' if provider == 'packaging' else '') + m['type'] for m in media}
        # Another printing's label/box stands in (reconstruction=regionalPackaging).
        roles[edition] |= {'standin:' + m['type'] for m in media
                           if (m.get('importReference') or {}).get('reconstruction') == 'regionalPackaging'}
    db.close()
    return archive_edition, roles, facts


def gamewatch_releases(repo):
    """The app's exact No-Intro archive -> ROM-set binding (console_model.dart)."""
    text = Path(repo, 'lib/models/console_model.dart').read_text(encoding='utf-8')
    block = text[text.index('static const gameWatchReleases'):]
    block = block[:block.index('};')]
    return {k: v for _, k, v in re.findall(r"""(['"])((?:(?!\1).)+)\1:\s*'(gnw_[a-z0-9_]+)'""", block)}


def census(store, roms, models, database=None, catalogue=None):
    published = published_keys(catalogue, ('gba', 'nes')) if catalogue else set()
    archive_edition, roles, facts = store_roles(store, database, published)
    releases = gamewatch_releases(Path(__file__).resolve().parents[1])
    report = {'readOnly': True, 'rule': __doc__.split('\n\n')[2].replace('\n', ' '), 'systems': {}}
    for system, folder in FOLDERS.items():
        names = listing(Path(roms, folder))
        row = {'archives': len(names), 'counted': 0}
        row = collections.defaultdict(int, row)
        gaps = []
        for name in names:
            if system == 'gameandwatch':
                stem = releases.get(name, Path(name).stem)
                handheld = Path(models, 'handhelds/gameandwatch', stem, 'model.json').is_file()
                box = Path(models, 'boxes/gameandwatch', stem, 'model.json').is_file()
                row['handheld'] += handheld; row['box'] += box
                ok = handheld and box
                if not ok: gaps.append({'archive': name, 'romSet': stem, 'handheld': handheld, 'box': box})
            else:
                edition = archive_edition.get(f'{folder}/{name}')
                have = roles.get(edition, set())
                outer = {f'packaging:{r}' for r in CARTON} <= have
                flat = all(r in have or f'packaging:{r}' in have for r in FLAT)
                carton = outer or flat
                row['outerCarton'] += outer; row['flatCartonOnly'] += flat and not outer
                row['flatWithoutSpine'] += flat and not outer and not (SPINE in have or f'packaging:{SPINE}' in have)
                label = LABEL in have or f'packaging:{LABEL}' in have
                row['bound'] += edition is not None
                row['carton'] += carton; row['label'] += label
                fact = edition in facts
                row['facts'] += fact
                ok = fact if name.split('/')[0] in FACT_ONLY else carton and label
                if not ok: gaps.append({'archive': name, 'bound': edition is not None, 'carton': carton, 'label': label, 'facts': fact})
            row['counted'] += ok
            klass = release_class(name)
            if klass != 'prerelease' and (name.split('/')[0] in FACT_ONLY or system == 'gameandwatch'):
                klass = 'official'
            if not ok: gaps[-1]['class'] = klass
            cls = row.setdefault(f'class:{klass}', collections.Counter())
            cls['archives'] += 1; cls['counted'] += ok
            if ok and system != 'gameandwatch' and f'standin:{LABEL}' in have and LABEL not in have:
                cls['labelStandIn'] += 1
            group = name.split('/')[0] if '/' in name else '(root)'
            sub = row.setdefault(f'group:{group}', collections.Counter())
            sub['archives'] += 1; sub['counted'] += ok
        row = {k: (dict(v) if isinstance(v, collections.Counter) else v) for k, v in row.items()}
        row['target80'] = -(-row['archives'] * 8 // 10)
        row['countedPercent'] = round(100 * row['counted'] / row['archives'], 2) if row['archives'] else 0
        official = row.get('class:official', {'archives': 0, 'counted': 0})
        row['officialPercent'] = round(100 * official['counted'] / official['archives'], 2) if official['archives'] else 0
        report['systems'][system] = {**row, 'gaps': gaps}
    return report


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--store', default='D:/RShopPrivate/CatalogueStore')
    p.add_argument('--roms', default='H:/My Drive/Roms')
    p.add_argument('--models', default='D:/RShopPrivate/Models')
    p.add_argument('--database', help='read this copy of metadata.sqlite instead')
    p.add_argument('--catalogue', default='H:/My Drive/R-Shop Metadata')
    p.add_argument('--json', type=Path)
    a = p.parse_args()
    report = census(a.store, a.roms, a.models, a.database, a.catalogue)
    for system, row in report['systems'].items():
        print(system, json.dumps({k: v for k, v in row.items() if k != 'gaps'}))
    if a.json:
        a.json.write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding='utf-8')


if __name__ == '__main__':
    main()
