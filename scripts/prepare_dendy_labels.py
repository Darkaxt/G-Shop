"""Give Russian (Dendy-era) NES games with no official counterpart a cartridge label.

Owner rulings 2026-11-27: a Dendy-era game with no licensed release (so no
official box or label to reuse, see prepare_dendy_pack) gets a label made in the
cheap Dendy style: an illustration repainted from the game's own title screen,
the Dendy logo and the thin printed outline real Dendy labels carry. A game
whose label image could not be generated (a refusal) instead reuses its
official predecessor's label, retitled with a pasted-on name the way pirate
labels were. A real label known only from a photo may be redrawn.

These are G-Shop's own images, never presented as scans: a generated or
redrawn label is `sourceId: gshop`, `reconstruction: generatedLabel`; a
retitled official label keeps the donor's provenance with
`reconstruction: composite`. All carry `overlay: dendySticker`.

The labels directory holds manifest.json ({name, kind, archives, file}) and
the finished PNGs; kind is generated, reconstruction or composite. Composite
donors are curated below; nothing is guessed.

Usage: python -I prepare_dendy_labels.py --projection P --store-db S --artwork A
       --labels DIR --output DIR/dendy-labels-nes.zip
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import sys

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_packaging_resources import (  # noqa: E402
    normalize_role_image, owner_key, write_packaging_batches)
from prepare_translation_pack import store_cartons  # noqa: E402

FOLDER = 'Nintendo - Nintendo Entertainment System/'
SPEC_URL = ('https://github.com/Darkaxt/G-Shop/blob/codex/drive-metadata-implementation/'
            'docs/SPECIFICATION.md')
# Retitled pirate sequels: the official label the cartridge maker reused.
COMPOSITE_DONORS = {'ducktales-iii': 'Public (iNES2)/DuckTales 2 (Japan).7z'}
# Cartridge labels are small; real scans are about 600 px wide.
MAX_WIDTH = 1024


def label_bytes(path):
    with Image.open(path) as image:
        image = image.convert('RGB')
        if image.width > MAX_WIDTH:
            image = image.resize((MAX_WIDTH, round(image.height * MAX_WIDTH / image.width)),
                                 Image.Resampling.LANCZOS)
        out = io.BytesIO()
        image.save(out, format='PNG')
    return normalize_role_image('support-texture', out.getvalue())[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('projection', 'store_db', 'artwork', 'labels', 'output'):
        parser.add_argument('--' + name.replace('_', '-'), dest=name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit(f'{args.output} exists')
    projection = sqlite3.connect(f'file:{args.projection.as_posix()}?mode=ro', uri=True)
    store = sqlite3.connect(f'file:{args.store_db.as_posix()}?mode=ro', uri=True)
    edition_of_path, carton = store_cartons(store, args.artwork)
    query = {}
    paths = {}
    for fid, path in projection.execute(
            'SELECT file_id, display_path FROM drive_catalogue_entries WHERE is_folder=0 '
            'AND display_path LIKE ?', (FOLDER + '%',)):
        paths[path.replace(chr(92), '/')] = fid
    for edition, key in projection.execute(
            "SELECT edition_id, catalogue_key FROM library_query_editions "
            "WHERE platform_id='nes' AND member=1"):
        if key:
            query[json.loads(key)[-1]] = edition

    manifest = json.loads((args.labels / 'manifest.json').read_text(encoding='utf-8'))
    games, payload, report = [], {}, {'selected': 0, 'noEdition': []}
    for entry in manifest:
        body = label_bytes(args.labels / Path(entry['file']).name)
        digest = hashlib.sha256(body).hexdigest()
        payload[digest] = body
        if entry['kind'] == 'composite':
            donor = FOLDER + COMPOSITE_DONORS[entry['name']]
            provider, media, source = carton(edition_of_path[donor])['support-texture']
            original = media.get('importReference') or {}
            ref = media.get('providerReference') or {}
            reference = {
                'sourceId': original.get('sourceId', 'screenscraper'),
                'assetId': f"dendy/label/{entry['name']}",
                'sourceUrl': original.get('sourceUrl') or
                    f"https://www.screenscraper.fr/gameinfos.php?gameid={ref.get('providerGameId')}",
                'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                'sha256': digest, 'reconstruction': 'composite', 'overlay': 'dendySticker'}
            if media.get('region'):
                reference['sourceRegion'] = media['region']
        elif entry['kind'] in ('generated', 'reconstruction'):
            reference = {'sourceId': 'gshop', 'assetId': f"dendy/label/{entry['name']}",
                         'sourceUrl': SPEC_URL, 'sha256': digest,
                         'reconstruction': 'generatedLabel', 'overlay': 'dendySticker'}
        else:
            raise SystemExit(f"unknown label kind {entry['kind']}")
        for archive in entry['archives']:
            path = FOLDER + archive
            edition_id = edition_of_path.get(path) or query.get(paths.get(path))
            found = edition_id and projection.execute(
                '''SELECT g.record_json, e.record_json FROM library_editions e
                JOIN library_game_identities g ON g.game_id=e.game_id WHERE e.edition_id=?''',
                (edition_id,)).fetchone()
            if not found:
                report['noEdition'].append(archive)
                continue
            game, edition = (json.loads(v) for v in found)
            if game.get('platformId') != 'nes':
                report['noEdition'].append(archive)
                continue
            games.append({'editionId': edition_id, 'gameId': game['id'],
                          'identityKey': owner_key(game, edition),
                          'resources': [{'type': 'support-texture',
                                         'importReference': dict(reference)}]})
            report['selected'] += 1
    if not games:
        raise SystemExit(json.dumps(report))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    packs = write_packaging_batches(args.output, {'version': 1, 'platform': 'nes',
                                                  'games': games}, payload)
    print(json.dumps({**report, 'packs': packs}, ensure_ascii=False))


if __name__ == '__main__':
    main()
