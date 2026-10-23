"""Bind an explicit cohort to read-only mounted ROMs and exact Drive artifacts."""
import argparse
import json
import re
import subprocess
from pathlib import Path


def prepare(cohort, artifacts, roots):
    by_id = {json.dumps(a['id'], sort_keys=True): a for a in artifacts}
    items, gaps = [], []
    for platform, root in roots.items():
        rows = cohort.get(platform, [])
        if not isinstance(rows, list):
            continue
        # Enumerate names only; Drive may hydrate bodies only for selected reads.
        found = subprocess.run(['rg', '--files', '--hidden', '--no-ignore', str(root)],
                               check=True, capture_output=True, encoding='utf-8').stdout.splitlines()
        names = {}
        for name in found:
            path = Path(name)
            names.setdefault(path.name, []).append(path)
        for row in rows:
            paths = names.get(row['archive'], [])
            members = row['edition'].get('members', [])
            request = (row.get('lookup') or {}).get('request')
            artifact = by_id.get(json.dumps(members[0]['artifactId'], sort_keys=True)) if len(members) == 1 else None
            if len(paths) != 1 or not artifact or not request:
                gaps.append({'editionId': row['editionId'], 'archive': row['archive'],
                             'pathCandidates': len(paths), 'artifactPresent': bool(artifact),
                             'requestPresent': bool(request)})
                continue
            request = dict(request, romIdentifier=None)
            # Filename markers constrain automatic binding, never establish a new
            # classification. Retain exact raw evidence for human edition review.
            restricted = re.search(r'\((?:Proto\b|Beta\b|Demo\b|Aftermarket\b|Unl\b|Pirate\b|T-|Hack\b)',
                                   row['archive'], re.I) is not None
            tags = set(request['contentTags'])
            evidence = row['edition'].get('evidence', [])
            conflicting_evidence = any(
                (e.get('kind') == 'rawRomIdentifier' and e.get('source') not in
                 {'driveHeader', 'driveLocalArchive'}) or
                (e.get('source') == 'manual' and e.get('kind') == 'contentClassification'
                 and 'unknown' in tags) for e in evidence)
            allow = (not restricted and tags <= {'unknown', 'official'} and
                     not conflicting_evidence and
                     not request.get('baseProviderGameId') and not row['edition'].get('patchId') and
                     not row['edition'].get('isTranslation') and not row['edition'].get('translatedLanguages'))
            items.append({'request': request, 'archive': {'path': str(paths[0].absolute()),
                          'artifact': artifact}, 'allowRawBinding': allow})
    return {'version': 1, 'items': items}, gaps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cohort', type=Path, required=True)
    parser.add_argument('--artifacts', type=Path, required=True,
                        help='Read-only NDJSON artifact snapshot with a final end record')
    parser.add_argument('--root', action='append', required=True, help='platform=mounted directory')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    records = [json.loads(line) for line in args.artifacts.read_text(encoding='utf-8').splitlines()]
    if not records or records[-1].get('kind') != 'end' or not records[-1].get('readOnly'):
        raise ValueError('Incomplete artifact snapshot')
    artifacts = [json.loads(r['record']['record_json']) for r in records if r['kind'] == 'artifact']
    manifest, gaps = prepare(json.loads(args.cohort.read_text(encoding='utf-8')), artifacts,
                             dict(x.split('=', 1) for x in args.root))
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(manifest, stream, indent=2)
    args.output.with_suffix('.gaps.json').write_text(json.dumps(gaps, indent=2), encoding='utf-8')
    print(json.dumps({'selected': len(manifest['items']), 'unresolved': len(gaps)}))


if __name__ == '__main__':
    main()
