"""Give fan translations their original game's carton with a "translated" sticker.

Owner ruling 2026-11-26: show the original box, with a sticker on the front in
the shape of the Nintendo oval saying it is translated. A translation archive
(`<platform folder>/Translations|T-En/<title> (<region>) [T-En by ...].7z`) takes the
carton of the original archive whose name is identical once the bracketed tags
are removed; nothing is guessed from a translated or retitled name.

Provenance stays honest: each resource keeps the original's source (sourceId,
URL, source digest, any fanCover reconstruction) and the front adds
`overlay: translationSticker`. Bodies come from the local catalogue store only.

Inputs are copies, never live files being written:
  --projection  read-only copy of the catalogue projection (translation editions)
  --store-db    read-only copy of the store's metadata.sqlite (original cartons)
  --artwork     the store's artwork directory (bodies, read-only)

Usage: python -I prepare_translation_pack.py --platform nes --projection P
       --store-db S --artwork A --output DIR/translations-nes.zip
"""
import argparse
import collections
import hashlib
import io
import json
from pathlib import Path
import re
import sqlite3
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from coverage_census import media_key  # noqa: E402
from prepare_packaging_resources import (  # noqa: E402
    normalize_role_image, owner_key, write_packaging_batches)

FOLDERS = {'nes': 'Nintendo - Nintendo Entertainment System',
           'gba': 'Nintendo - Game Boy Advance'}
TRANSLATIONS = {'nes': 'Translations', 'gba': 'T-En'}  # Drive subfolder names
ROLES = ('box-2D', 'box-2D-back', 'box-2D-side')
PROVIDERS = ('packaging', 'screenscraper')  # curated packs win over raw scrapes
LANGUAGES = {'en': 'ENGLISH', 'es': 'SPANISH', 'fr': 'FRENCH', 'de': 'GERMAN',
             'it': 'ITALIAN', 'pt': 'PORTUGUESE', 'ru': 'RUSSIAN', 'pl': 'POLISH',
             'nl': 'DUTCH', 'sv': 'SWEDISH', 'zh': 'CHINESE', 'ko': 'KOREAN',
             'ar': 'ARABIC', 'tr': 'TURKISH', 'el': 'GREEK', 'ja': 'JAPANESE'}
FONT = 'C:/Windows/Fonts/ariblk.ttf'
RED = (228, 0, 18)


def base_name(path):
    name = path.rsplit('/', 1)[-1]
    name = name[:-3] if name.lower().endswith('.7z') else name
    return re.sub(r'\s*\[[^\]]*\]', '', name).strip()


def language(path):
    found = re.search(r'\[T-([A-Za-z]{2})\b', path)
    return LANGUAGES.get(found.group(1).lower()) if found else None


def sticker(front, lang):
    """Composite a Nintendo-style oval seal: white stadium, red ring, red text."""
    image = front.convert('RGBA')
    # Sized from the shorter side so landscape (Japanese GBA) fronts keep it modest.
    w = round(min(image.width, image.height * 0.9) * 0.46)
    h = round(w * 0.42)
    seal = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(seal)
    ring = max(3, round(h * 0.08))
    draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=(255, 255, 255, 255))
    draw.rounded_rectangle((ring // 2, ring // 2, w - 1 - ring // 2, h - 1 - ring // 2),
                           radius=h // 2, outline=RED, width=ring)
    lines = [('TRANSLATED', 0.34)] + ([(lang, 0.17)] if lang else [])
    sizes = []
    for text, share in lines:
        size = round(h * share)
        font = ImageFont.truetype(FONT, size)
        while font.getlength(text) > w * 0.78 and size > 6:
            size -= 1
            font = ImageFont.truetype(FONT, size)
        sizes.append((text, font, font.getbbox(text)))
    total = sum(b[3] - b[1] for _, _, b in sizes) + round(h * 0.05) * (len(sizes) - 1)
    y = (h - total) / 2
    for text, font, box in sizes:
        draw.text(((w - (box[2] - box[0])) / 2 - box[0], y - box[1]), text, font=font, fill=RED)
        y += box[3] - box[1] + round(h * 0.05)
    seal = seal.rotate(8, resample=Image.Resampling.BICUBIC, expand=True)
    shadow = Image.new('RGBA', seal.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), mask=seal.getchannel('A'))
    x = image.width - seal.width - round(image.width * 0.04)
    y = round(image.height * 0.03)
    offset = max(2, round(h * 0.04))
    image.alpha_composite(shadow, (x + offset, y + offset))
    image.alpha_composite(seal, (x, y))
    out = io.BytesIO()
    image.convert('RGB').save(out, format='PNG')
    return out.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=sorted(FOLDERS), required=True)
    for name in ('projection', 'store_db', 'artwork', 'output'):
        parser.add_argument('--' + name.replace('_', '-'), dest=name, type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit(f'{args.output} exists')
    folder = FOLDERS[args.platform] + '/'
    subfolder = folder + TRANSLATIONS[args.platform] + '/'
    projection = sqlite3.connect(f'file:{args.projection.as_posix()}?mode=ro', uri=True)
    store = sqlite3.connect(f'file:{args.store_db.as_posix()}?mode=ro', uri=True)

    paths = {fid: p.replace('\\', '/') for fid, p in projection.execute(
        'SELECT file_id, display_path FROM drive_catalogue_entries WHERE is_folder=0 '
        'AND display_path LIKE ?', (folder + '%',))}
    translations = {fid: p for fid, p in paths.items()
                    if p.startswith(subfolder) and p.lower().endswith('.7z')}
    originals = collections.defaultdict(list)
    for p in paths.values():
        if not p.startswith(subfolder) and p.lower().endswith('.7z'):
            originals[base_name(p)].append(p)

    edition_of_path = {}
    for edition, artifacts in store.execute('SELECT edition_id, artifacts_json FROM identity_bindings'):
        for artifact in json.loads(artifacts):
            edition_of_path[artifact.get('displayPath', '')] = edition
    bodies = {k: args.artwork / f for k, f in store.execute(
        'SELECT media_key, filename FROM metadata_artwork_cache')}
    records = collections.defaultdict(dict)
    for edition, provider, record, edition_json in store.execute(
            "SELECT edition_id, provider_id, record_json, edition_json FROM records "
            "WHERE provider_id IN ('packaging','screenscraper')"):
        records[edition][provider] = (json.loads(record), json.loads(edition_json or '{}'))

    def carton(edition):
        """Best local body per role: curated provider first, edition region first."""
        chosen = {}
        for provider in PROVIDERS:
            if provider not in records.get(edition, {}):
                continue
            record, edition_json = records[edition][provider]
            regions = edition_json.get('regions') or []
            media = sorted(record.get('media', []),
                           key=lambda m: (m.get('region') not in regions, m.get('region') or ''))
            for m in media:
                if m['type'] in ROLES and m['type'] not in chosen:
                    body = bodies.get(media_key(m))
                    if body is not None and body.is_file():
                        chosen[m['type']] = (provider, m, body)
        return chosen if 'box-2D' in chosen else None

    query = {}
    for edition, game, key in projection.execute(
            'SELECT edition_id, game_id, catalogue_key FROM library_query_editions '
            'WHERE platform_id=? AND member=1', (args.platform,)):
        if key:
            query[json.loads(key)[-1]] = (edition, game)

    report = collections.Counter()
    games, payload = [], {}
    for fid, path in sorted(translations.items(), key=lambda item: item[1]):
        target = query.get(fid)
        if target is None:
            report['noTranslationEdition'] += 1
            continue
        if carton(target[0]):
            report['alreadyHasCarton'] += 1
            continue
        donors = [edition_of_path[p] for p in sorted(originals.get(base_name(path), []),
                  key=lambda p: ('/Public' not in p, p)) if p in edition_of_path]
        donor = next(((e, c) for e in donors for c in [carton(e)] if c), None)
        if donor is None:
            report['noOriginalCarton' if donors or originals.get(base_name(path)) else 'noOriginal'] += 1
            continue
        found = projection.execute('''SELECT g.record_json, e.record_json FROM library_editions e
            JOIN library_game_identities g ON g.game_id=e.game_id WHERE e.edition_id=?''',
            (target[0],)).fetchone()
        game, edition = (json.loads(v) for v in found)
        if game.get('platformId') != args.platform or not edition.get('isTranslation'):
            report['notTranslationEdition'] += 1
            continue
        resources = []
        for role in ROLES:
            if role not in donor[1]:
                continue
            provider, media, body_path = donor[1][role]
            raw = body_path.read_bytes()
            if role == 'box-2D':
                with Image.open(io.BytesIO(raw)) as front:
                    raw_out = sticker(front, language(path))
            else:
                raw_out = raw
            data, rotation = normalize_role_image(role, raw_out)
            digest = hashlib.sha256(data).hexdigest()
            payload[digest] = data
            original = media.get('importReference') or {}
            ref = media.get('providerReference') or {}
            reference = {
                'sourceId': original.get('sourceId', 'screenscraper'),
                'assetId': f'translation/{donor[0]}/{role}',
                'sourceUrl': original.get('sourceUrl') or
                    f"https://www.screenscraper.fr/gameinfos.php?gameid={ref.get('providerGameId')}",
                'sourceSha256': original.get('sourceSha256') or hashlib.sha256(raw).hexdigest(),
                'sha256': digest}
            for key in ('panel', 'sourceRegion', 'reconstruction', 'sourceLanguages'):
                if original.get(key) is not None:
                    reference[key] = original[key]
            if media.get('region') and 'sourceRegion' not in reference:
                reference['sourceRegion'] = media['region']
            if rotation:
                reference['rotationDegrees'] = rotation
            if role == 'box-2D':
                reference['overlay'] = 'translationSticker'
            resources.append({'type': role, 'importReference': reference})
        games.append({'editionId': target[0], 'gameId': game['id'],
                      'identityKey': owner_key(game, edition), 'resources': resources})
        report['selected'] += 1
    report['translations'] = len(translations)
    if not games:
        raise SystemExit(json.dumps(report))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    packs = write_packaging_batches(args.output, {'version': 1, 'platform': args.platform,
                                                  'games': games}, payload)
    print(json.dumps({**report, 'packs': packs}))


if __name__ == '__main__':
    main()
