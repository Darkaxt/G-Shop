"""Focused read-only protected-file baseline contracts; no live ADB in tests."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import thor_protected_baseline as audit


class ProtectedBaselineTests(unittest.TestCase):
    def test_digest_is_bound_to_same_canonical_path_and_stable_stats(self):
        path = '/storage/emulated/0/RetroArch/saves/test.srm'
        sha = hashlib.sha256(b'save').hexdigest()
        valid = f'{path}\n1 2 4 5 6\n{sha}  -\n1 2 4 5 6\n'.encode()
        result = audit.parse_hash_observation(valid, path, '/storage/emulated/0/RetroArch/saves')
        self.assertTrue(result['stable'])
        self.assertEqual(result['sha256'], sha)
        changed = valid.replace(b'1 2 4 5 6\n', b'1 2 4 5 7\n', 1)
        self.assertFalse(audit.parse_hash_observation(changed, path, '/storage/emulated/0/RetroArch/saves')['stable'])
        for invalid in (valid.replace(sha.encode(), b'bad'), valid.replace(path.encode(), b'/outside/file'), valid[:-3]):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                audit.parse_hash_observation(invalid, path, '/storage/emulated/0/RetroArch/saves')

    def test_comparison_requires_terminal_complete_baseline_and_current_same_hashes(self):
        file = {'type': 'file', 'scope': 'saves', 'path': '/save', 'sizeBytes': 4,
                'sha256': 'a' * 64, 'stable': True, 'removalAuthorized': False}
        directory = {'type': 'scope', 'scope': 'saves', 'path': '/saves',
                     'state': 'observed', 'stableMembership': True}
        with tempfile.TemporaryDirectory(dir=Path(r'D:\Temp')) as temporary:
            path = Path(temporary) / 'private.jsonl'
            records = [{'type': 'header', 'serial': 'thor'}, file, directory,
                       {'type': 'summary', 'files': 1, 'bytes': 4, 'complete': True}]
            path.write_text(''.join(json.dumps(row) + '\n' for row in records), encoding='utf-8')
            baseline = audit.load_baseline(path, 'thor')
            self.assertTrue(audit.compare_baseline(baseline, {file['path']: file}, {'saves': directory})['equal'])
            changed = dict(file, sha256='b' * 64)
            self.assertFalse(audit.compare_baseline(baseline, {'/save': changed}, {'saves': directory})['equal'])
            self.assertFalse(audit.compare_baseline(baseline, {}, {'saves': directory})['equal'])
            unknown = dict(directory, state='absent_or_unreadable')
            self.assertFalse(audit.compare_baseline(baseline, {'/save': file}, {'saves': unknown})['equal'])
            records.pop()
            path.write_text(''.join(json.dumps(row) + '\n' for row in records), encoding='utf-8')
            with self.assertRaises(ValueError):
                audit.load_baseline(path, 'thor')

    def test_uncertain_files_or_membership_cannot_pass(self):
        baseline = {'files': {'/save': {'path': '/save', 'sha256': 'a' * 64, 'sizeBytes': 4, 'stable': True}},
                    'scopes': {'saves': {'path': '/saves', 'state': 'observed', 'stableMembership': True}}}
        for change in ('file', 'scope'):
            files = {key: dict(value) for key, value in baseline['files'].items()}
            scopes = {key: dict(value) for key, value in baseline['scopes'].items()}
            if change == 'file':
                files['/save']['stable'] = False
            else:
                scopes['saves']['stableMembership'] = False
            self.assertFalse(audit.compare_baseline(baseline, files, scopes)['equal'])

    def test_scope_redirect_cannot_verify_empty_baseline(self):
        original = {'path': '/saves', 'state': 'observed', 'stableMembership': True}
        baseline = {'files': {}, 'scopes': {'saves': original}}
        self.assertFalse(audit.compare_baseline(
            baseline, {}, {'saves': dict(original, path='/other')})['equal'])

    def test_capture_emits_streamed_hash_and_rejects_changed_membership(self):
        root = '/storage/emulated/0/RetroArch/saves'
        path = root + '/test.srm'
        sha = hashlib.sha256(b'save').hexdigest()
        observation = {'path': path, 'stable': True, 'beforeStat': [1, 2, 4, 5, 6],
                       'afterStat': [1, 2, 4, 5, 6]}

        class Device:
            def shell(self, command):
                if command.startswith('if test'):
                    return (root + '\n').encode()
                self_command = (f'test ! -L {path} && test -f {path} && realpath {path}'
                                f' && stat -c "%d %i %s %Y %Z" {path}'
                                f' && sha256sum < {path} && stat -c "%d %i %s %Y %Z" {path}')
                if command != self_command:
                    raise AssertionError('Unexpected device command')
                return f'{path}\n1 2 4 5 6\n{sha}  -\n1 2 4 5 6\n'.encode()

        for after in ({path: observation}, {}):
            emitted = []
            with patch.object(audit, '_inventory', side_effect=[{path: observation}, after]):
                files, scope = audit.capture_scope(Device(), 'saves', root, 'directory', emitted.append)
            self.assertEqual(files[0]['sha256'], sha)
            self.assertFalse(files[0]['removalAuthorized'])
            self.assertEqual(scope['stableMembership'], bool(after))
            self.assertEqual([row['type'] for row in emitted], ['file', 'scope'])


if __name__ == '__main__':
    unittest.main()
