"""Fixed Thor GBA checkpoint: ordinary UI actions, renderer events and captures.

Start at the ranked 24-game, four-column GBA grid, first game selected. The
secondary display must be the verified 1240x1080 display. No backend actions,
scraping, ROM launch, readiness sleeps, deadlines or automatic retries are performed.
Double-tap input uses a 100ms inter-tap interval within Flutter's 40..300ms
gesture contract; this does not synchronize loading or classify readiness.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--pid', required=True, type=int)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--capture-helper', required=True, type=Path)
    parser.add_argument('--pack-report', required=True, type=Path)
    parser.add_argument('--start-ordinal', type=int, default=0)
    parser.add_argument('--initial-selection', required=True)
    parser.add_argument('--initial-keycode', type=int, choices=[19, 20, 21, 22])
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    if not 0 <= args.start_ordinal < 24:
        parser.error('start-ordinal must be in 0..23')
    expected = {row['rank']: row['roles'] for row in
                json.loads(args.pack_report.read_text(encoding='utf-8'))}
    if set(expected) != set(range(1, 25)):
        parser.error('The reviewed pack must contain the 24 actual ranked games')
    args.output.mkdir(exist_ok=False)

    def adb(*words):
        return subprocess.check_output(['adb', '-s', args.serial, *map(str, words)],
                                       text=True, encoding='utf-8')

    if adb('shell', 'pidof', 'com.darkaxt.rshop').strip() != str(args.pid):
        raise RuntimeError('Installed app process changed')
    def require_offline():
        if args.offline and adb('shell', 'settings', 'get', 'global', 'wifi_on').strip() != '0':
            raise RuntimeError('Offline inspection lost its disabled-Wi-Fi boundary')
    require_offline()

    def key(code):
        require_foreground()
        adb('shell', 'input', '-d', '0', 'keyevent', code)

    def tap(x, y, lower=False):
        require_foreground()
        adb('shell', 'input', '-d', '4' if lower else '0', 'tap', x, y)

    def require_foreground():
        activities = adb('shell', 'dumpsys', 'activity', 'activities')
        if not re.search(r'Resumed: ActivityRecord\{[^\n]* com\.darkaxt\.rshop/', activities):
            raise RuntimeError('R-Shop is not resumed; no input was dispatched')

    def resource(line, view, identity=None):
        if 'RShopResources ' not in line or f'"view":"{view}"' not in line:
            return None
        match = re.search(r'"identity":("(?:\\.|[^"\\])*")', line)
        if match is None:
            raise RuntimeError('Missing renderer identity')
        current = hashlib.sha256(json.loads(match[1]).encode()).hexdigest()
        if identity is not None and current != identity:
            return None
        if not all(value in line for value in
                   ['"frameRendered":true', '"labelReady":true', '"error":null']):
            raise RuntimeError('Resource renderer did not report a valid frame')
        roles = re.search(r'"roles":(\{[^}]*\})', line)
        return {'selection': current, 'view': view,
                'roles': json.loads(roles[1]) if roles else {},
                'canOpen': '"canOpen":true' in line}

    log = subprocess.Popen(['adb', '-s', args.serial, 'logcat', '--pid', str(args.pid),
                            '-T', '1', '-v', 'raw', '-s', 'flutter:I', 'RShopPreview:I'],
                           stdout=subprocess.PIPE, text=True, encoding='utf-8')
    try:
        def wait_for(predicate):
            for line in log.stdout:
                if 'Physical-media renderer ' in line:
                    raise RuntimeError('Native model renderer failed; inspect its exact logged error')
                result = predicate(line)
                if result:
                    return result
            raise RuntimeError('Native event stream ended before readiness')

        visited = set()
        previous = None
        if args.initial_keycode is not None:
            key(args.initial_keycode)
        with (args.output / 'frames.jsonl').open('x', encoding='utf-8') as report:
            for ordinal in range(args.start_ordinal, 24):
                require_offline()
                if ordinal != args.start_ordinal:
                    row, column = divmod(ordinal, 4)
                    key(20 if column == 0 else (22 if row % 2 == 0 else 21))
                identity = None
                if ordinal == args.start_ordinal:
                    identity = args.initial_selection
                while True:
                    target = wait_for(lambda line: re.search(
                        r'rendered selection=([a-f0-9]{64}).*model=true.*label=true.*resources=true.*video=true.*completed=true', line))
                    if ordinal == args.start_ordinal and target[1] != identity:
                        continue
                    identity = target[1]
                    if identity != previous and identity not in visited:
                        break
                # Cover the actual upper viewport through ordinary scrolling;
                # lower-preview success does not establish shelf rendering.
                if ordinal % 4 == 0 or ordinal == 23:
                    subprocess.run([sys.executable, str(args.capture_helper),
                        '--serial', args.serial, '--screens', 'up',
                        '--up-id', '4630946441858561667', '--output-dir',
                        str(args.output), '--prefix', f'{ordinal+1:02}-shelf'],
                        check=True, stdout=subprocess.DEVNULL)
                if ordinal == 15:
                    subprocess.run([sys.executable, str(args.capture_helper),
                        '--serial', args.serial, '--screens', 'down',
                        '--down-id', '4630946482288158084', '--output-dir',
                        str(args.output), '--prefix', f'{ordinal+1:02}-special-tableau'],
                        check=True, stdout=subprocess.DEVNULL)
                # One primary HUD Select opens Details, never a second Select
                # (which would launch). Wait for its fresh frame, then use the
                # secondary Resources button, away from Play/Download.
                tap(1760, 985)
                wait_for(lambda line: f'rendered selection={identity}' in line and
                         'model=null' in line)
                tap(620, 970, lower=True)
                manual_pages = 0
                for view, point in [('box', None), ('cartridge', (340, 65)),
                                    ('manual', (620, 65))]:
                    if view == 'manual' and not manual_pages:
                        continue
                    if point:
                        tap(*point, lower=True)
                    frame = wait_for(lambda line: resource(line, view, identity))
                    identity = frame['selection']
                    if ordinal == args.start_ordinal and identity != args.initial_selection:
                        raise RuntimeError('Initial focused game does not match the reviewed selection')
                    manual_pages = frame['roles'].get('manual-page', 0)
                    if not all(frame['roles'].get(role) == 1 for role in
                               ['box-2D', 'box-2D-back', 'box-2D-side', 'support-texture']):
                        raise RuntimeError('Selected game lacks required typed faces/label')
                    frame['ordinal'] = ordinal + 1
                    row, column = divmod(ordinal, 4)
                    frame['rank'] = row * 4 + (column if row % 2 == 0 else 3 - column) + 1
                    for role, count in expected[frame['rank']].items():
                        if frame['roles'].get(role, 0) != count:
                            raise RuntimeError('Cached resource count differs from the reviewed pack')
                    report.write(json.dumps(frame) + '\n')
                    report.flush()
                    if view in {'box', 'cartridge'}:
                        subprocess.run([sys.executable, str(args.capture_helper),
                            '--serial', args.serial, '--screens', 'down',
                            '--down-id', '4630946482288158084', '--output-dir',
                            str(args.output), '--prefix', f'{ordinal+1:02}-{view}'],
                            check=True, stdout=subprocess.DEVNULL)
                    if view == 'manual':
                        require_foreground()
                        adb('shell', 'input -d 4 tap 620 550; sleep 0.1; input -d 4 tap 620 550')
                        wait_for(lambda line: 'RShopManual phase=reader page=2' in line)
                        subprocess.run([sys.executable, str(args.capture_helper),
                            '--serial', args.serial, '--screens', 'down',
                            '--down-id', '4630946482288158084', '--output-dir',
                            str(args.output), '--prefix', f'{ordinal+1:02}-reader'],
                            check=True, stdout=subprocess.DEVNULL)
                # Reader and Gallery share compact full-canvas navigation.
                tap(*( (455, 36) if manual_pages else (860, 65) ), lower=True)
                trailer = wait_for(lambda line: re.search(
                    r'RShopGallery (\{.*\})', line) if all(s in line for s in
                    ['"kind":"trailer"', '"videoReady":true', '"playing":true']) else None)
                playback = json.loads(trailer[1])
                if playback['error'] is not None or not 0 < playback['volume'] <= 1:
                    raise RuntimeError('Trailer playback/volume did not pass')
                if playback['items'] < 2:
                    raise RuntimeError('Unified gallery lacks its collected images')
                report.write(json.dumps({'selection': identity, 'gallery': playback}) + '\n')
                report.flush()
                # The first image follows the trailer in the same carousel.
                # This point lies inside the first image with and without
                # overflow arrows on the verified 1240px secondary display.
                tap(580, 1000, lower=True)
                wait_for(lambda line: 'RShopGallery ' in line and '"kind":"image"' in line)
                visited.add(identity)
                previous = identity
                tap(1184, 36, lower=True)
                print(json.dumps({'inspected': len(visited), 'expected': 24-args.start_ordinal}), flush=True)
            print(json.dumps({'completed': True, 'distinct': len(visited),
                              'startOrdinal': args.start_ordinal,
                              'offline': args.offline,
                              'videoAcceptance': True, 'cinematicCompleted': True,
                              'visualInspectionRequired': True}), flush=True)
    finally:
        log.terminate()
        log.wait()


if __name__ == '__main__':
    main()
