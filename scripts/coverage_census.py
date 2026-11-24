"""S26 coverage census (issue #6): per source archive, is its physical-resource set bound?

Read-only. Denominator = the current archive listing of each ROM folder (one
non-recursive listing per folder). Bindings come from the Windows master
catalogue store, which is what tool/publish_catalogue_test.dart publishes (a dry
run with 0 writes proves Drive matches it).

Counted (GBA/NES): the archive's edition has a packaging record with all six
outer-box faces AND a standalone cartridge label texture (`support-texture`).
A complete-cartridge picture (`support-2D`) is not a label. Counted (G&W): the
installed handheld model and its carton model both exist.

Usage: python -I coverage_census.py [--store D:/RShopPrivate/CatalogueStore]
       [--roms "H:/My Drive/Roms"] [--models D:/RShopPrivate/Models] [--json OUT]
"""
import argparse
import collections
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

FOLDERS = {'gba': 'Nintendo - Game Boy Advance', 'nes': 'Nintendo - Nintendo Entertainment System',
           'gameandwatch': 'Nintendo - Game & Watch'}
CARTON = {f'outer-box-{f}' for f in ('front', 'back', 'top', 'bottom', 'left', 'right')}
LABEL = 'support-texture'


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


def store_roles(store):
    db = sqlite3.connect(f'file:{Path(store, "metadata.sqlite").as_posix()}?mode=ro', uri=True)
    archive_edition = {}
    for edition, artifacts in db.execute('SELECT edition_id, artifacts_json FROM identity_bindings'):
        for artifact in json.loads(artifacts):
            archive_edition[artifact.get('displayPath', '')] = edition
    roles = collections.defaultdict(set)
    for edition, provider, record in db.execute(
            "SELECT edition_id, provider_id, record_json FROM records WHERE provider_id IN ('packaging','screenscraper')"):
        types = {m['type'] for m in json.loads(record).get('media', [])}
        roles[edition] |= {('packaging:' if provider == 'packaging' else '') + t for t in types}
    db.close()
    return archive_edition, roles


def gamewatch_releases(repo):
    """The app's exact No-Intro archive -> ROM-set binding (console_model.dart)."""
    text = Path(repo, 'lib/models/console_model.dart').read_text(encoding='utf-8')
    block = text[text.index('static const gameWatchReleases'):]
    block = block[:block.index('};')]
    return {k: v for _, k, v in re.findall(r"""(['"])((?:(?!\1).)+)\1:\s*'(gnw_[a-z0-9_]+)'""", block)}


def census(store, roms, models):
    archive_edition, roles = store_roles(store)
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
                carton = {f'packaging:{r}' for r in CARTON} <= have
                label = LABEL in have or f'packaging:{LABEL}' in have
                row['bound'] += edition is not None
                row['carton'] += carton; row['label'] += label
                ok = carton and label
                if not ok: gaps.append({'archive': name, 'bound': edition is not None, 'carton': carton, 'label': label})
            row['counted'] += ok
            group = name.split('/')[0] if '/' in name else '(root)'
            sub = row.setdefault(f'group:{group}', collections.Counter())
            sub['archives'] += 1; sub['counted'] += ok
        row = {k: (dict(v) if isinstance(v, collections.Counter) else v) for k, v in row.items()}
        row['target80'] = -(-row['archives'] * 8 // 10)
        row['countedPercent'] = round(100 * row['counted'] / row['archives'], 2) if row['archives'] else 0
        report['systems'][system] = {**row, 'gaps': gaps}
    return report


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--store', default='D:/RShopPrivate/CatalogueStore')
    p.add_argument('--roms', default='H:/My Drive/Roms')
    p.add_argument('--models', default='D:/RShopPrivate/Models')
    p.add_argument('--json', type=Path)
    a = p.parse_args()
    report = census(a.store, a.roms, a.models)
    for system, row in report['systems'].items():
        print(system, json.dumps({k: v for k, v in row.items() if k != 'gaps'}))
    if a.json:
        a.json.write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding='utf-8')


if __name__ == '__main__':
    main()
