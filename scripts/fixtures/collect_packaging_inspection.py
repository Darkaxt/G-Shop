"""Bounded per-console evidence from the isolated, live S25 explorer."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from packaging_vm_probe import InspectionSession


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--capture-helper', type=Path, required=True)
    parser.add_argument('--apk-sha256', required=True)
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--systems', nargs='+', help='Focused console IDs; omitted means the full inventory')
    parser.add_argument('--inspect-back', action='store_true')
    parser.add_argument('--source-revision', default='s25-explorer-r4')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    def action(command, *options):
        return connection.action(command, **{options[i].removeprefix('--'): options[i+1]
                                              for i in range(0,len(options),2)})

    def capture(prefix):
        raw = subprocess.check_output([sys.executable, str(args.capture_helper),
            '--serial', args.serial, '--screens', 'up', '--output-dir',
            str(args.output), '--prefix', prefix], text=True)
        result = json.loads(raw)
        if not result['ok']:
            raise RuntimeError('Host capture failed')
        return result['outputs']['up']

    seen = set()
    journal_path = args.output / 'models.jsonl'
    if args.resume:
        for line in journal_path.read_text('utf-8').splitlines():
            row = json.loads(line)
            if row.get('summary') or row['apkSha256'] != args.apk_sha256 or row['device'] != args.serial:
                raise RuntimeError('Cannot resume a completed or different artifact/device journal')
            if row['system'] in seen:
                raise RuntimeError('Duplicate console in journal')
            seen.add(row['system'])
    with InspectionSession(args.serial) as connection, journal_path.open(
            'a' if args.resume else 'x', encoding='utf-8') as journal:
        for index in range(66):
            state = action('ready')
            if state.get('sourceRevision') != args.source_revision:
                raise RuntimeError('Inspection APK does not contain the expected source revision')
            system = state['system']
            if args.systems and system not in args.systems:
                if index < 65:
                    action('next')
                continue
            if system in seen:
                if not args.resume:
                    raise RuntimeError('Console repeated before completing the inventory')
                if index < 65:
                    action('next')
                continue
            seen.add(system)
            row = {'system': system, 'apkSha256': args.apk_sha256,
                   'device': args.serial, 'views': {}, 'cinematicVerified': False}
            for mode in ['box', 'cover', 'manual', 'cartridge']:
                if mode not in state['gallery']['availableViews']:
                    continue
                current = action('view', '--view', mode)
                gallery = current['gallery']
                model = gallery.get('model')
                if model and (model['error'] is not None or not model['frameRendered']):
                    raise RuntimeError(f'{system}/{mode}: renderer did not succeed')
                evidence = {'initial': gallery}
                if model:
                    zoomed = action('button', '--tooltip', 'Zoom in')['gallery']
                    if zoomed['model']['paintedPose']['scale'] <= model['paintedPose']['scale']:
                        raise RuntimeError(f'{system}/{mode}: zoom was not painted')
                    evidence['zoomed'] = zoomed
                    action('button', '--tooltip', 'Reset view')
                    subprocess.check_call(['adb', '-s', args.serial, 'shell',
                                           'input', 'keyevent', 'KEYCODE_DPAD_RIGHT'],
                                          stdout=subprocess.DEVNULL)
                    rotated = action('ready')['gallery']
                    if rotated['model']['paintedPose']['ry'] == model['paintedPose']['ry']:
                        raise RuntimeError(f'{system}/{mode}: controller rotation was not painted')
                    evidence['rotated'] = rotated
                    action('button', '--tooltip', 'Reset view')
                    if args.inspect_back and (mode == 'cartridge' or system == 'nes'):
                        subprocess.check_call(['adb', '-s', args.serial, 'shell', 'input', 'keyevent',
                            *(['KEYCODE_DPAD_RIGHT'] * 26)], stdout=subprocess.DEVNULL)
                        back = action('ready')['gallery']
                        if back['model']['paintedPose']['ry'] - model['paintedPose']['ry'] < 3:
                            raise RuntimeError('Back-face rotation did not paint')
                        evidence['back'] = back
                        evidence['backCapture'] = capture(f'{index:02d}-{system}-{mode}-back')
                        action('button', '--tooltip', 'Reset view')
                    if gallery['canOpen']:
                        opened = action('button', '--tooltip', 'Open')['gallery']
                        if opened['model']['paintedPose']['opening'] != 1:
                            raise RuntimeError(f'{system}/{mode}: open pose was not painted')
                        evidence['opened'] = opened
                        if system == 'nes':
                            evidence['openCapture'] = capture(f'{index:02d}-{system}-{mode}-open')
                        action('button', '--tooltip', 'Close case')
                else:
                    evidence['limitation'] = 'Existing flat fallback; no console-specific 3D model'
                    if mode == 'cartridge':
                        zoomed = action('button', '--tooltip', 'Zoom in')['gallery']
                        subprocess.check_call(['adb', '-s', args.serial, 'shell', 'input',
                                               'keyevent', 'KEYCODE_DPAD_RIGHT'], stdout=subprocess.DEVNULL)
                        rotated = action('ready')['gallery']
                        if zoomed['zoom'] <= gallery['zoom'] or rotated['yaw'] == gallery['yaw']:
                            raise RuntimeError('Flat preview controls did not update')
                        evidence['flatZoomed'] = zoomed
                        evidence['flatRotated'] = rotated
                        action('button', '--tooltip', 'Reset view')
                if mode == 'cartridge':
                    evidence['capture'] = capture(f'{index:02d}-{system}-medium')
                elif system == 'nes':
                    evidence['capture'] = capture(f'{index:02d}-{system}-{mode}')
                if mode == 'manual':
                    reading = action('button', '--tooltip', 'Read manual')['gallery']
                    if not reading['reading'] or reading['manualPages'] != 1:
                        raise RuntimeError('Prepared manual page did not enter read mode')
                    enlarged = action('button', '--tooltip', 'Zoom in')['gallery']
                    if enlarged['readerScale'] <= reading['readerScale']:
                        raise RuntimeError('Manual reader zoom did not change')
                    evidence['reader'] = enlarged
                row['views'][mode] = evidence
            if system in ['snes', 'gbc', 'megadrive']:
                action('button', '--tooltip', 'Region')
                alternate = action('view', '--view', 'cartridge')['gallery']
                if not alternate['model']['frameRendered'] or alternate['model']['error']:
                    raise RuntimeError('Alternate physical model failed')
                zoomed = action('button', '--tooltip', 'Zoom in')['gallery']
                subprocess.check_call(['adb', '-s', args.serial, 'shell', 'input',
                                       'keyevent', 'KEYCODE_DPAD_RIGHT'], stdout=subprocess.DEVNULL)
                rotated = action('ready')['gallery']
                if (zoomed['model']['paintedPose']['scale'] <= alternate['model']['paintedPose']['scale'] or
                    rotated['model']['paintedPose']['ry'] == alternate['model']['paintedPose']['ry']):
                    raise RuntimeError('Alternate model controls did not paint')
                row['alternate'] = {'initial':alternate, 'rotated':rotated,
                                    'capture':capture(f'{index:02d}-{system}-alternate')}
                action('button', '--tooltip', 'Region')
            journal.write(json.dumps(row) + '\n')
            journal.flush()
            print(json.dumps({'completed': index + 1, 'system': system}), flush=True)
            if args.systems and seen == set(args.systems):
                break
            if index < 65:
                action('next')
        if args.systems and seen != set(args.systems):
            raise RuntimeError('A requested console ID was not found')
        journal.write(json.dumps({'summary': 'completed', 'consoles': len(seen),
                                  'cinematicVerified': False}) + '\n')


if __name__ == '__main__':
    main()
