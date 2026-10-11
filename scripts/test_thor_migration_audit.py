"""Focused contracts for the S7 read-only audit; no device/network requests."""
import io
import json
from contextlib import closing
from pathlib import Path
import shlex
import re
import sqlite3
import tempfile
import unittest
from unittest.mock import Mock, patch
import thor_migration_audit as audit

from thor_migration_audit import Device, GATES, compare_observation, checked_relative_path, main


class MigrationAuditTests(unittest.TestCase):
    @staticmethod
    def cache_page(artifacts=(), row_ids=(), after=0, total=None, states=()):
        return {'schema': 'rshop.s7.cache.v2', 'platform': 'psp',
                'after': after, 'rowIds': list(row_ids),
                'next': row_ids[-1] if row_ids else after,
                'totalArtifacts': len(artifacts) if total is None else total,
                'artifacts': list(artifacts), 'states': list(states)}

    def test_cloud_pages_cross_old_limit_without_retaining_unrelated_names(self):
        device = Mock()
        device.private.return_value = b'{"sources":[]}'
        rows = [dict(self.cloud, displayName=f'Other-{i}.zip') for i in range(2048)]
        rows[-1] = self.cloud
        pages = [self.cache_page(rows[start:start + 128],
                                list(range(start + 1, start + 129)),
                                after=start, total=2048)
                 for start in range(0, 2048, 128)]
        pages.append(self.cache_page(after=2048, total=2048))
        device.cache_snapshot.side_effect = [json.dumps(page).encode() for page in pages]
        artifacts, scopes = audit.cloud_snapshot(device, 'psp', {self.cloud['displayName']})
        self.assertEqual(artifacts, [self.cloud])
        self.assertEqual(scopes, [])
        self.assertEqual(device.cache_snapshot.call_args_list,
                         [unittest.mock.call('psp', after) for after in range(0, 2049, 128)])

    @staticmethod
    def retention_sql():
        root = Path(__file__).resolve().parent.parent
        dart = (root / 'lib/services/library_query.dart').read_text(encoding='utf-8')
        ranks = re.search(r"static String _rankedScope\(String scope\) => '''(.*?)''';",
                          dart, re.S).group(1).replace('$scope', 'AND platform_id = ?')
        method = dart[dart.index('static Future<LibraryRetentionPage> _retentionPage'):
                      dart.index('static void _validate')]
        page = re.search(r"final response = await txn.rawQuery\(\s*'''(.*?)'''", method, re.S).group(1)
        native = (root / 'scripts/RShopRetentionSnapshot.java').read_text(encoding='utf-8')
        shipped = re.search(r'String SQL = """\s*(.*?)\s*""";', native, re.S).group(1)
        # Native review is the normal paged query, not the optional exact-row
        # review. Instantiate that explicit null branch, preserving SQL tokens.
        row_filter = "${cacheRowId == null ? '' : 'WHERE s.cache_row_id = ?'}"
        if page.count(row_filter) != 1:
            raise AssertionError('Unrecognized retention row-filter expression')
        expected = page.replace('$cte', ranks).replace(row_filter, '').strip()
        if shipped.split() != expected.split():
            raise AssertionError('Native retention observation must use the actual Dart query')
        return shipped

    def test_retention_native_sql_matches_dart_and_keeps_all_canonical_members(self):
        db = sqlite3.connect(':memory:')
        db.row_factory = sqlite3.Row
        try:
            db.executescript('''CREATE TABLE library_query_editions(
                edition_id TEXT,game_id TEXT,group_key TEXT,platform_id TEXT,
                cache_row_id INTEGER,member INTEGER,score REAL,source_order INTEGER,
                rating_eligible INTEGER);
                CREATE TABLE games(id INTEGER,systemSlug TEXT,is_folder INTEGER);''')
            rows = [
                ('e1','g1','first','psx',1,1,80,0,1),
                ('e2','g1','first','psx',2,1,None,None,0),
                # Prefer the accepted first source, not a higher second source.
                ('e3','g1','first','psx',3,1,99,1,1),
                ('e4','g2','second','psx',4,1,90,0,1),
                ('e5','g3','unresolved','psx',5,1,None,None,0),
                ('e6','g4','other-console','snes',6,1,100,0,1),
            ]
            db.executemany('INSERT INTO library_query_editions VALUES (?,?,?,?,?,?,?,?,?)', rows)
            db.executemany('INSERT INTO games VALUES (?,?,0)',
                           [(i, 'psx' if i != 6 else 'snes') for i in range(1,8)])
            result = [dict(row) for row in db.execute(self.retention_sql(), ('psx','psx',128,0))]
            self.assertEqual(len(result), 5)
            self.assertEqual(result[0]['collection_games'], 3)
            self.assertEqual(result[0]['ranked_games'], 2)
            self.assertEqual(result[0]['total_members'], 5)
            self.assertEqual(result[0]['unbound_artifacts'], 1)
            self.assertEqual({row['canonical_rank'] for row in result if row['group_key']=='first'}, {2})
            self.assertEqual(next(row['canonical_rank'] for row in result if row['edition_id']=='e2'), 2)
            self.assertIsNone(next(row['canonical_rank'] for row in result if row['edition_id']=='e5'))
            empty = dict(db.execute(self.retention_sql(), ('psx','psx',128,5)).fetchone())
            self.assertIsNone(empty['edition_id'])
            self.assertEqual(empty['total_members'], 5)
        finally:
            db.close()

    def test_cloud_projection_does_not_copy_a_live_database(self):
        device = Mock()
        config = json.dumps({'sources': [{'id': 'source', 'drive': {
            'account_id': 'account', 'root_folder_id': 'root'}}]}).encode()
        device.private.return_value = config
        payload = self.cache_page([self.cloud], [7], states=[
            {'scope': ['source', 'account', 'root'], 'active': 3, 'pending': 4}])
        device.cache_snapshot.return_value = json.dumps(payload).encode()
        artifacts, scopes = audit.cloud_snapshot(device, 'psp')
        self.assertEqual(artifacts, [self.cloud])
        self.assertEqual(scopes, [{'sourceId': 'source', 'accountId': 'account',
                                  'rootFolderId': 'root', 'activeGeneration': 3,
                                  'pendingGeneration': 4}])
        device.cache_snapshot.assert_called_once_with('psp', 0)
        self.assertEqual(device.private.call_args_list,
                         [unittest.mock.call('app_flutter/config.json', 1048576)] * 2)

    def test_cloud_projection_rejects_incomplete_foreign_or_oversized_snapshots(self):
        device = Mock()
        device.private.return_value = b'{"sources":[]}'
        good = self.cache_page()
        for index, change in enumerate(({'schema': 'other'}, {'platform': 'ps2'}, {'error': 'bound'},
                       {'artifacts': {}}, {'artifacts': [{}] * 129},
                       {'after': 1}, {'next': 1}, {'totalArtifacts': True},
                       {'totalArtifacts': 100001}, {'rowIds': [1]},
                       {'states': [{'scope': 'same', 'active': 1, 'pending': None}] * 2},
                       {'states': [{'scope': 's', 'active': -1, 'pending': None}]},
                       {'states': [{'scope': ['source', 'account', 'root'], 'pending': None}]},
                       {'states': [
                           {'scope': ['s', 'a', 'r'], 'active': 1, 'pending': None},
                           {'scope': ['s', 'a', 'r'], 'active': 1, 'pending': None}]},
                       {'states': [{}] * 257})):
            device.cache_snapshot.return_value = json.dumps(dict(good, **change)).encode()
            with self.subTest(case=index):
                with self.assertRaises(ValueError):
                    audit.cloud_snapshot(device, 'psp')
        device.cache_snapshot.return_value = b'{' + b' ' * 1048576 + b'}'
        with self.assertRaises(ValueError):
            audit.cloud_snapshot(device, 'psp')

    def test_cloud_projection_rejects_changed_configuration(self):
        device = Mock()
        device.private.side_effect = [b'{"sources":[]}', b'{"sources":[],"changed":true}']
        device.cache_snapshot.return_value = json.dumps(self.cache_page()).encode()
        with self.assertRaisesRegex(ValueError, 'Configuration changed'):
            audit.cloud_snapshot(device, 'psp')

    def test_native_projection_invocation_is_fixed_and_bounded(self):
        device = Device('adb', 'serial', 'com.darkaxt.rshop.debug',
                        '/data/local/tmp/rshop-s7-cache-snapshot.jar')
        with patch.object(device, '_read', return_value=b'{}') as read:
            self.assertEqual(device.cache_snapshot('psp'), b'{}')
            command, limit = read.call_args.args
            self.assertEqual(limit, 1048576)
            self.assertEqual(command[:6], ['adb', '-s', 'serial', 'exec-out', 'run-as',
                                         'com.darkaxt.rshop.debug'])
            self.assertEqual(command[6:8], ['sh', '-c'])
            self.assertEqual(command[8], 'CLASSPATH=/data/local/tmp/rshop-s7-cache-snapshot.jar '
                                        'app_process -Xmx128m /system/bin RShopMigrationCacheSnapshot psp 0')
        for platform in ('psp; id', '../psp', ''):
            with self.assertRaises(ValueError):
                device.cache_snapshot(platform)
        with self.assertRaises(ValueError):
            Device('adb', 'serial', 'package', '/data/local/tmp/../private.jar')
        with self.assertRaises(ValueError):
            Device('adb', 'serial', 'package').cache_snapshot('psp')
        for after in (-1, True, 1 << 63, '1;id'):
            with self.assertRaises(ValueError):
                device.cache_snapshot('psp', after)

    def test_cloud_pages_reject_drift_repeats_missing_rows_and_memory_excess(self):
        first = self.cache_page([self.cloud] * 128, list(range(1, 129)), total=129)
        good = self.cache_page([self.cloud], [129], after=128, total=129)
        for second in (dict(good, totalArtifacts=130), dict(good, after=127),
                       dict(good, rowIds=[128], next=128),
                       dict(good, next=130), self.cache_page(after=128, total=129),
                       dict(good, states=[{'scope':['s','a','r'], 'active':1,'pending':None}])):
            device = Mock()
            device.private.return_value = b'{"sources":[]}'
            device.cache_snapshot.side_effect = [json.dumps(first).encode(), json.dumps(second).encode()]
            with self.subTest(second=second), self.assertRaises(ValueError):
                audit.cloud_snapshot(device, 'psp')
        device = Mock()
        device.private.return_value = b'{"sources":[]}'
        device.cache_snapshot.return_value = json.dumps(self.cache_page([self.cloud], [1])).encode()
        with patch.object(audit, 'MAX_RETAINED_ARTIFACT_BYTES', 1), self.assertRaisesRegex(ValueError, 'retained'):
            audit.cloud_snapshot(device, 'psp')

    def test_native_sql_exports_exact_platform_and_generations_with_bounds(self):
        source = (Path(__file__).parent / 'RShopMigrationCacheSnapshot.java').read_text()
        query = re.search(r'String SQL = """\n(.*?)\n\s*""";', source, re.S).group(1)
        with closing(sqlite3.connect(':memory:')) as db:
            db.execute('CREATE TABLE games(id INTEGER PRIMARY KEY,systemSlug TEXT, remote_artifact TEXT)')
            db.execute('PRAGMA reverse_unordered_selects=ON')
            db.execute('CREATE TABLE drive_catalogue_state(scope TEXT,active INTEGER,pending INTEGER)')
            db.execute('INSERT INTO games VALUES (1,?,?)', ('psp', json.dumps(self.cloud)))
            db.execute('INSERT INTO games VALUES (2,?,?)', ('ps2', 'foreign invalid json'))
            db.execute('INSERT INTO drive_catalogue_state VALUES (?,?,?)',
                       ('["s","a","r"]', 1, 2))
            read = lambda after=0: json.loads(db.execute(query, ('psp', after, 'psp', 'psp', after, after)).fetchone()[0])
            result = read()
            self.assertEqual(result['artifacts'], [self.cloud])
            self.assertEqual(result['states'], [{'scope': ['s', 'a', 'r'],
                                                 'active': 1, 'pending': 2}])
            db.executemany('INSERT INTO games(systemSlug,remote_artifact) VALUES (?,?)', [('psp', '{}')] * 2000)
            all_ids = []
            after = 0
            while True:
                page = read(after)
                self.assertLessEqual(len(page['artifacts']), 128)
                self.assertEqual(page['rowIds'], sorted(page['rowIds']))
                self.assertEqual(page['totalArtifacts'], 2001)
                all_ids.extend(page['rowIds'])
                after = page['next']
                if len(page['artifacts']) < 128:
                    break
            self.assertEqual(len(all_ids), 2001)
            self.assertEqual(len(set(all_ids)), 2001)
            self.assertNotIn(2, all_ids)
            db.execute('DELETE FROM games')
            # Bound is checked before attempting to parse/serialize huge JSON.
            db.execute('INSERT INTO games(systemSlug,remote_artifact) VALUES (?,?)', ('psp', 'x' * 900001))
            self.assertEqual(read()['error'], 'projection_bound')
            db.execute('DELETE FROM games')
            db.executemany('INSERT INTO drive_catalogue_state VALUES (?,?,?)',
                           [('s', 1, None)] * 256)
            self.assertEqual(read()['error'], 'projection_bound')
            db.execute('DELETE FROM drive_catalogue_state')
            db.execute('INSERT INTO drive_catalogue_state VALUES (?,?,?)',
                       ('x' * 65537, 1, None))
            self.assertEqual(read()['error'], 'projection_bound')

    @staticmethod
    def bulk_regular(path, before='1 2 3 4 5', after='1 2 3 4 5', resolved=None):
        return '\0'.join([path, 'regular', resolved or path, before, after, '']).encode()

    def test_bulk_inventory_reads_stats_once_without_rom_hash_commands(self):
        observe = getattr(audit, 'inventory_observations', None)
        self.assertTrue(callable(observe), 'A bounded device-side stat inventory is required')
        root = '/storage/card/Roms'
        path = root + "/psp/It's a game\n日本.chd"
        device = Mock()
        device.shell.side_effect = [(path + '\0').encode(), self.bulk_regular(path)]
        rows = list(observe(device, root))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['path'], path)
        self.assertTrue(rows[0]['stable'])
        self.assertIsNone(rows[0]['md5'])
        self.assertEqual(rows[0]['beforeStat'], [1, 2, 3, 4, 5])
        self.assertEqual(device.shell.call_count, 2)
        command = device.shell.call_args.args[0]
        self.assertIn('stat', command)
        self.assertNotIn('md5sum', command)
        self.assertNotIn('cat ', command)

    def test_bulk_inventory_protects_links_and_changed_file_identity(self):
        root = '/storage/card/Roms'
        device = Mock()
        device.shell.side_effect = [
            (root + '/outside\0' + root + '/changed.zip\0').encode(),
            (root + '/outside\0link\0').encode() +
            self.bulk_regular(root + '/changed.zip', after='1 9 3 4 5')]
        rows = list(audit.inventory_observations(device, root))
        self.assertEqual(rows[0]['issue'], 'symbolic_link_preserved')
        self.assertFalse(rows[0]['stable'])
        self.assertNotIn('resolvedPath', rows[0])
        self.assertFalse(rows[1]['stable'])

    def test_bulk_inventory_rejects_partial_duplicate_escaping_or_invalid_records(self):
        root = '/storage/card/Roms'
        path = root + '/game.zip'
        good = self.bulk_regular(path)
        for data in (good[:-1], (path + '\0regular\0').encode(), good + good,
                     self.bulk_regular(path, resolved='/storage/elsewhere/game.zip'),
                     self.bulk_regular('/storage/card/Roms-other/game.zip'),
                     self.bulk_regular(path, before='1 2 -1 4 5'),
                     self.bulk_regular(path, after='1 2 3'),
                     (path + '\0unknown\0').encode()):
            with self.subTest(data=data):
                device = Mock()
                device.shell.side_effect = [(path + '\0').encode(), data]
                with self.assertRaises(ValueError):
                    list(audit.inventory_observations(device, root))

    def test_bulk_inventory_limits_path_count_and_command_bytes(self):
        root = '/storage/card/Roms'
        paths = [root + f'/game-{i}.zip' for i in range(130)]
        device = Mock()
        device.shell.side_effect = [( '\0'.join(paths) + '\0').encode()] + [
            b''.join(self.bulk_regular(path) for path in paths[start:start + 64])
            for start in range(0, 130, 64)]
        rows = list(audit.inventory_observations(device, root))
        self.assertEqual([r['path'] for r in rows], paths)
        self.assertEqual(device.shell.call_count, 4)
        self.assertIn('-print0', device.shell.call_args_list[0].args[0])
        for call in device.shell.call_args_list[1:]:
            self.assertLessEqual(len(call.args[0].encode('utf-8')), 16384)

    def test_bulk_inventory_requires_every_requested_path_in_response(self):
        root = '/storage/card/Roms'
        paths = [root + '/one.zip', root + '/two.zip']
        for response in (b'', self.bulk_regular(paths[0]),
                         self.bulk_regular(paths[1]) + self.bulk_regular(paths[0])):
            device = Mock()
            device.shell.side_effect = [('\0'.join(paths) + '\0').encode(), response]
            with self.assertRaises(ValueError):
                list(audit.inventory_observations(device, root))

    def test_bulk_inventory_splits_long_quoted_paths_before_the_byte_limit(self):
        root = '/storage/card/Roms'
        paths = [root + '/x' * 500 + f"/It's 日本-{i}.zip" for i in range(40)]
        device = Mock()
        def shell(command):
            if command.startswith('find '):
                return ('\0'.join(paths) + '\0').encode()
            args = shlex.split(command)
            self.assertLessEqual(len(command.encode()), 16384)
            self.assertLess(len(args[4:]), 64)  # Bytes, not count, bound this cohort.
            return b''.join(self.bulk_regular(path) for path in args[4:])
        device.shell.side_effect = shell
        self.assertEqual([r['path'] for r in audit.inventory_observations(device, root)], paths)
        self.assertGreater(device.shell.call_count, 2)

    def setUp(self):
        self.local = {"name": "Game (USA).zip", "sizeBytes": 3,
                      "md5": "900150983cd24fb0d6963f7d28e17f72", "stable": True}
        self.cloud = {"displayName": self.local["name"], "sizeBytes": 3,
                      "version": "7", "canDownload": True,
                      "providerChecksums": {"md5": self.local["md5"]},
                      "id": {"providerId": "drive", "sourceId": "fixture-source",
                             "accountId": "fixture-account", "providerFileId": "fixture-file"}}

    def test_matching_cached_digest_never_authorizes_removal(self):
        result = compare_observation(self.local, [self.cloud])
        self.assertEqual(result["comparison"], "cached_digest_match")
        self.assertEqual(result["disposition"], "preserve")
        self.assertEqual(result["removalAuthorized"], False)
        self.assertIn("live_cloud_revalidation", result["remainingGates"])
        self.assertIn("defensible_retention", result["remainingGates"])
        self.assertIn("tested_restore", result["remainingGates"])

    def test_retention_review_counts_a_canonical_game_not_each_member(self):
        key = json.dumps(['drive', 'fixture-source', 'fixture-account', 'fixture-file'],
                         separators=(',', ':'))
        snapshot = self.retention_fixture([
            {'artifact_key': key, 'edition_id': 'disc1', 'game_id': 'game',
             'group_key': 'canonical', 'canonical_rank': 1},
            {'artifact_key': key, 'edition_id': 'disc2', 'game_id': 'game',
             'group_key': 'canonical', 'canonical_rank': 1},
        ])
        result = audit.review_retention(self.local, [self.cloud], snapshot)
        self.assertEqual(result['disposition'], 'keep')
        self.assertEqual(result['retention']['groupKey'], 'canonical')
        self.assertEqual(result['retention']['editionIds'], ['disc1', 'disc2'])
        self.assertFalse(result['removalAuthorized'])
        self.assertEqual(result['remainingGates'], GATES)

    @staticmethod
    def retention_fixture(members, **changes):
        return dict({'platform': 'n64', 'collection_games': 30, 'ranked_games': 30,
                     'total_members': len(members), 'unbound_artifacts': 0,
                     'dirty_editions': 0, 'dirty_artifacts': 0, 'members': members}, **changes)

    def test_retention_review_never_turns_bottom_rank_into_removal_authority(self):
        key = json.dumps(['drive', 'fixture-source', 'fixture-account', 'fixture-file'],
                         separators=(',', ':'))
        member = {'artifact_key': key, 'edition_id': 'edition', 'game_id': 'game',
                  'group_key': 'canonical', 'canonical_rank': 26}
        result = audit.review_retention(self.local, [self.cloud],
                                        self.retention_fixture([member]))
        self.assertEqual(result['disposition'], 'preserve')
        self.assertEqual(result['retention']['disposition'], 'outside_sample')
        self.assertFalse(result['removalAuthorized'])
        self.assertIn('live_cloud_revalidation', result['remainingGates'])
        self.assertIn('tested_restore', result['remainingGates'])

    def test_retention_review_preserves_missing_conflicting_dirty_or_changed_bindings(self):
        key = json.dumps(['drive', 'fixture-source', 'fixture-account', 'fixture-file'],
                         separators=(',', ':'))
        member = {'artifact_key': key, 'edition_id': 'edition', 'game_id': 'game',
                  'group_key': 'canonical', 'canonical_rank': 1}
        for snapshot in (self.retention_fixture([]),
                         self.retention_fixture([member], dirty_editions=1),
                         self.retention_fixture([member], dirty_artifacts=1),
                         self.retention_fixture([member, dict(member, group_key='another')]),
                         self.retention_fixture([dict(member, artifact_key='other')])):
            with self.subTest(snapshot=snapshot):
                result = audit.review_retention(self.local, [self.cloud], snapshot)
                self.assertEqual(result['disposition'], 'preserve')
                self.assertFalse(result['removalAuthorized'])
        changed = dict(self.local, md5='0' * 32)
        result = audit.review_retention(changed, [self.cloud], self.retention_fixture([member]))
        self.assertEqual(result['disposition'], 'preserve')
        self.assertEqual(result['comparison'], 'digest_mismatch')

    def test_incomplete_ranking_allows_cloud_only_planning_without_removal_authority(self):
        key = json.dumps(['drive', 'fixture-source', 'fixture-account', 'fixture-file'],
                         separators=(',', ':'))
        for rank in (None, 26):
            result = audit.review_retention(self.local, [self.cloud], self.retention_fixture([
                {'artifact_key': key, 'edition_id': 'edition', 'game_id': 'game',
                 'group_key': 'canonical', 'canonical_rank': rank}], ranked_games=26))
            self.assertEqual(result['retention']['disposition'], 'outside_sample')
            self.assertTrue(result['retention']['provisional'])
            self.assertEqual(result['disposition'], 'preserve')
            self.assertFalse(result['removalAuthorized'])
            self.assertEqual(result['remainingGates'], GATES)

    def test_unrelated_unbound_artifact_does_not_veto_exact_member_planning(self):
        key = json.dumps(['drive', 'fixture-source', 'fixture-account', 'fixture-file'],
                         separators=(',', ':'))
        for rank, expected in ((1, 'keep'), (26, 'outside_sample'),
                               (None, 'outside_sample')):
            member = {'artifact_key': key, 'edition_id': 'edition', 'game_id': 'game',
                      'group_key': 'canonical', 'canonical_rank': rank}
            with self.subTest(rank=rank):
                result = audit.review_retention(self.local, [self.cloud],
                    self.retention_fixture([member], unbound_artifacts=1))
                self.assertEqual(result['retention']['disposition'], expected)
                self.assertTrue(result['retention']['provisional'])
                self.assertFalse(result['removalAuthorized'])
                self.assertEqual(result['remainingGates'], GATES)

    def test_retention_pages_are_bounded_and_reject_mixed_or_partial_observations(self):
        key = json.dumps(['drive', 'fixture-source', 'fixture-account', 'fixture-file'],
                         separators=(',', ':'))
        member = {'artifact_key': key, 'edition_id': 'edition', 'game_id': 'game',
                  'group_key': 'canonical', 'canonical_rank': 1}
        page = dict(self.retention_fixture([member], collection_games=1, ranked_games=1),
                    schema='rshop.s7.retention.v2', readOnly=True, removalAuthorized=False, offset=0)
        device = Mock()
        device.retention_page.return_value = json.dumps(page).encode()
        self.assertEqual(audit.retention_snapshot(device, 'n64')['members'], [member])
        device.retention_page.assert_called_once_with('n64', 0)
        for change in ({'schema': 'rshop.s7.retention.v1'}, {'platform': 'psx'},
                       {'offset': 1}, {'readOnly': False}, {'removalAuthorized': True},
                       {'total_members': 100001}, {'members': []},
                       {'members': [dict(member, canonical_rank=True)]},
                       {'members': [dict(member, edition_id='x' * 4097)]},
                       {'members': [dict(member, artifact_key=4)]}):
            with self.subTest(change=change):
                device.retention_page.return_value = json.dumps(dict(page, **change)).encode()
                with self.assertRaises(ValueError):
                    audit.retention_snapshot(device, 'n64')
        first = dict(page, total_members=2)
        for second in (dict(first, offset=1),
                       dict(first, offset=1, members=[]),
                       dict(first, offset=1, dirty_artifacts=1,
                            members=[dict(member, edition_id='another')])):
            device.retention_page.side_effect = [json.dumps(first).encode(), json.dumps(second).encode()]
            with self.assertRaises(ValueError):
                audit.retention_snapshot(device, 'n64')

    def test_retention_pages_cross_old_2000_member_limit(self):
        def pages():
            for offset in range(0, 2049, 128):
                members = [{'artifact_key': f'key-{n}', 'edition_id': f'edition-{n}',
                            'game_id': f'game-{n}', 'group_key': f'group-{n}',
                            'canonical_rank': n + 1}
                           for n in range(offset, min(offset + 128, 2049))]
                yield json.dumps(dict(self.retention_fixture(members,
                    collection_games=2049, ranked_games=2049, total_members=2049),
                    schema='rshop.s7.retention.v2', readOnly=True,
                    removalAuthorized=False, offset=offset)).encode()
        device = Mock()
        device.retention_page.side_effect = pages()
        snapshot = audit.retention_snapshot(device, 'n64')
        self.assertEqual(len(snapshot['members']), 2049)
        self.assertEqual(snapshot['members'][-1]['canonical_rank'], 2049)
        self.assertEqual(device.retention_page.call_args.args, ('n64', 2048))

    def test_retention_keeps_only_inspected_artifacts_but_observes_entire_scope(self):
        total = 16384
        wanted = {'key-0', 'key-9000', 'key-16383'}
        def pages():
            for offset in range(0, total, 128):
                members = [{'artifact_key': f'key-{n}', 'edition_id': f'edition-{n}',
                            'game_id': f'game-{n}', 'group_key': f'group-{n}',
                            'canonical_rank': n + 1}
                           for n in range(offset, offset + 128)]
                yield json.dumps(dict(self.retention_fixture(members,
                    platform='nes', collection_games=total, ranked_games=total, total_members=total),
                    schema='rshop.s7.retention.v2', readOnly=True,
                    removalAuthorized=False, offset=offset)).encode()
        device = Mock()
        device.retention_page.side_effect = pages()
        result = audit.retention_snapshot(device, 'nes', wanted)
        self.assertEqual(result['total_members'], total)
        self.assertEqual(result['ranked_games'], total)
        self.assertEqual({m['artifact_key'] for m in result['members']}, wanted)
        self.assertEqual(len(result['members']), 3)
        self.assertEqual(device.retention_page.call_count, total // 128)

    def test_retention_subset_preserves_duplicate_drift_and_memory_guards(self):
        member = {'artifact_key': 'unrelated', 'edition_id': 'edition',
                  'game_id': 'game', 'group_key': 'group', 'canonical_rank': 1}
        first = dict(self.retention_fixture([member], collection_games=2,
            ranked_games=2, total_members=2), schema='rshop.s7.retention.v2',
            readOnly=True, removalAuthorized=False, offset=0)
        device = Mock()
        # Even an unrelated duplicate or changing summary invalidates the audit.
        for second in (dict(first, offset=1), dict(first, offset=1,
                members=[dict(member, edition_id='other')], dirty_editions=1)):
            device.retention_page.side_effect = [json.dumps(first).encode(), json.dumps(second).encode()]
            with self.assertRaises(ValueError):
                audit.retention_snapshot(device, 'n64', {'wanted'})
        device.retention_page.side_effect = None
        device.retention_page.return_value = json.dumps(first).encode()
        with patch.object(audit, 'MAX_RETENTION_IDENTITY_BYTES', 1):
            with self.assertRaisesRegex(ValueError, 'observed identity bound'):
                audit.retention_snapshot(device, 'n64', {'wanted'})
        with patch.object(audit, 'MAX_RETAINED_RETENTION_BYTES', 1):
            with self.assertRaisesRegex(ValueError, 'retained member bound'):
                audit.retention_snapshot(device, 'n64')
        with self.assertRaisesRegex(ValueError, 'requested identity bound'):
            audit.retention_snapshot(device, 'n64', {'x' * 4097})
        device.retention_page.return_value = b' ' * 1048577
        with self.assertRaisesRegex(ValueError, 'page exceeds'):
            audit.retention_snapshot(device, 'n64', set())

    def test_retention_native_invocation_can_read_large_scope_with_bounded_heap(self):
        device = Device('adb', 'serial', 'package',
                        retention_helper='/data/local/tmp/retention.jar')
        with patch.object(device, '_read', return_value=b'{}') as read:
            device.retention_page('nes', 16384)
            command, limit = read.call_args.args
            self.assertEqual(limit, 1048576)
            self.assertEqual(command[-1], 'CLASSPATH=/data/local/tmp/retention.jar '
                'app_process -Xmx128m /system/bin RShopRetentionSnapshot nes 16384')
        for offset in (-1, True, 100001, '0;id'):
            with self.assertRaises(ValueError):
                device.retention_page('nes', offset)

    def test_native_retention_projection_joins_primary_key_not_filename(self):
        source = (Path(__file__).parent / 'RShopRetentionSnapshot.java').read_text()
        wrapper = source[source.index('String query ='):source.index('try (SQLiteDatabase')]
        prefix, suffix = wrapper.split('+ SQL +')
        decode = lambda value: ''.join(json.loads(q) for q in re.findall(r'"(?:\\.|[^"\\])*"', value))
        query = decode(prefix) + self.retention_sql() + decode(suffix)
        with closing(sqlite3.connect(':memory:')) as db:
            db.row_factory = sqlite3.Row
            db.executescript('''CREATE TABLE library_query_editions(
                edition_id TEXT,game_id TEXT,group_key TEXT,platform_id TEXT,
                cache_row_id INTEGER,member INTEGER,score REAL,source_order INTEGER,
                rating_eligible INTEGER);
                CREATE TABLE games(id INTEGER,systemSlug TEXT,is_folder INTEGER,artifact_key TEXT);
                CREATE TABLE library_query_dirty(edition_id TEXT);
                CREATE TABLE library_query_cache_dirty(cache_row_id INTEGER);''')
            db.execute('INSERT INTO library_query_editions VALUES (?,?,?,?,?,?,?,?,?)',
                       ('edition','game','group','n64',7,1,90,0,1))
            db.executemany('INSERT INTO games VALUES (?, ?,0,?)',
                           [(7,'n64','exact-object'), (8,'n64','another-object')])
            rows = [dict(r) for r in db.execute(query, ('n64','n64',128,0))]
            self.assertEqual(rows[0]['artifact_key'], 'exact-object')
            self.assertEqual(rows[0]['unbound_artifacts'], 1)
            self.assertEqual(rows[0]['dirty_editions'], 0)
        self.assertIn('rshop.s7.retention.v2', source)

    def test_review_manifest_is_exclusive_private_and_preserves_all_removal_gates(self):
        root = '/storage/card/Roms/n64'
        path = root + '/' + self.local['name']
        local = dict(self.local, path=path, relativePath=self.local['name'])
        key = json.dumps(['drive', 'fixture-source', 'fixture-account', 'fixture-file'],
                         separators=(',', ':'))
        snapshot = self.retention_fixture([
            {'artifact_key': key, 'edition_id': 'edition', 'game_id': 'game',
             'group_key': 'canonical', 'canonical_rank': 1}])
        device = Mock()
        device.shell.side_effect = [root.encode(), (path + '\0').encode()]
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'private-review.jsonl'
            argv = ['audit', '--adb', 'adb', '--serial', 'fixture',
                    '--platform', 'n64', '--root', root, '--extension', '.zip',
                    '--cache-helper', '/data/local/tmp/cache.jar',
                    '--retention-helper', '/data/local/tmp/ranks.jar', '--output', str(output)]
            with patch('sys.argv', argv), patch('thor_migration_audit.Device', return_value=device), \
                 patch('thor_migration_audit.cloud_snapshot', return_value=([self.cloud], [])), \
                 patch('thor_migration_audit.retention_snapshot', return_value=snapshot), \
                 patch('thor_migration_audit.local_observation', return_value=local), \
                 patch('sys.stdout', new_callable=io.StringIO):
                main()
            rows = [json.loads(line) for line in output.read_text().splitlines()]
            self.assertEqual(rows[0]['retentionCoherence'], 'per_page_observation_not_execution_authority')
            self.assertEqual(rows[1]['remainingGates'], GATES)
            self.assertEqual(rows[-1]['filesByDisposition'], {'keep': 1})
            self.assertEqual(rows[-1]['boundCanonicalGamesByDisposition'], {'keep': 1})
            self.assertEqual(rows[-1]['bytesByDisposition'], {'keep': 3})
            self.assertTrue(all(row['removalAuthorized'] is False for row in rows))
            device.shell.side_effect = [root.encode(), (path + '\0').encode()]
            with patch('sys.argv', argv), patch('thor_migration_audit.Device', return_value=device), \
                 patch('thor_migration_audit.cloud_snapshot', return_value=([self.cloud], [])), \
                 patch('thor_migration_audit.retention_snapshot', return_value=snapshot):
                with self.assertRaises(FileExistsError):
                    main()

    def test_same_name_different_bytes_is_protected(self):
        self.cloud["providerChecksums"]["md5"] = "0" * 32
        self.assertEqual(compare_observation(self.local, [self.cloud])["comparison"],
                         "digest_mismatch")

    def test_changed_local_file_is_protected(self):
        self.local["stable"] = False
        self.assertEqual(compare_observation(self.local, [self.cloud])["comparison"],
                         "local_changed")

    def test_duplicate_cloud_identity_is_not_guessed(self):
        other = dict(self.cloud, id=dict(self.cloud['id'], providerFileId="other-file"))
        self.assertEqual(compare_observation(self.local, [self.cloud, other])["comparison"],
                         "ambiguous_cloud_candidates")

    def test_missing_invalid_digest_or_version_cannot_prove_recovery(self):
        for change in ({"providerChecksums": {}}, {"version": None},
                       {"providerChecksums": {"md5": "garbage"}}, {"canDownload": False},
                       {"id": {}}, {"id": dict(self.cloud['id'], accountId=None)},
                       {"sizeBytes": None}, {"sizeBytes": -1}):
            result = compare_observation(self.local, [dict(self.cloud, **change)])
            self.assertEqual(result["comparison"], "cloud_evidence_incomplete")

    def test_size_difference_is_not_a_digest_match(self):
        self.cloud['sizeBytes'] = 4
        self.assertEqual(compare_observation(self.local, [self.cloud])['comparison'],
                         'size_mismatch')

    def test_exec_out_passes_shell_program_without_an_extra_quoting_layer(self):
        command = "realpath '/storage/card/Roms/Game Gear'"
        with patch.object(Device, '_read', return_value=b'fixture') as run:
            self.assertEqual(Device('adb', 'serial', 'package').shell(command), b'fixture')
            self.assertEqual(run.call_args.args[0], ['adb', '-s', 'serial',
                                                    'exec-out', 'sh', '-c', command])
            self.assertEqual(run.call_args.args[1], 8 * 1048576)

    def test_reader_limit_stops_only_its_own_client_and_closes_the_pipe(self):
        process = Mock(stdout=io.BytesIO(b'123456'))
        process.poll.return_value = None
        process.wait.return_value = 0
        with patch('thor_migration_audit.subprocess.Popen', return_value=process):
            with self.assertRaisesRegex(ValueError, 'buffer limit'):
                Device('adb', 'serial', 'package')._read(['fixture-reader'], 4)
        process.terminate.assert_called_once_with()
        process.wait.assert_called_once_with()
        self.assertTrue(process.stdout.closed)

    def test_unmapped_file_stays_protected(self):
        self.assertEqual(compare_observation(self.local, [])["comparison"],
                         "no_cloud_candidate")

    def test_exact_descendants_only(self):
        self.assertEqual(checked_relative_path('/storage/card/Roms/gg/a.zip',
                                              '/storage/card/Roms/gg'), 'a.zip')
        for path in ('/storage/card/Roms/gg-other/a.zip',
                     '/storage/card/Roms/gg/../a.zip', '/storage/card/Roms/gg'):
            with self.assertRaises(ValueError):
                checked_relative_path(path, '/storage/card/Roms/gg')

    def test_inventory_only_does_not_read_catalogue_or_hash_roms(self):
        root = '/storage/card/Roms/gg'
        device = Mock()
        device.shell.side_effect = [root.encode(), (root + '/Game.zip\0').encode(),
                                   self.bulk_regular(root + '/Game.zip')]
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'private.jsonl'
            argv = ['audit', '--adb', 'adb', '--serial', 'fixture',
                    '--platform', 'gamegear', '--root', root, '--extension', '.zip',
                    '--inventory-only', '--output', str(output)]
            with patch('sys.argv', argv), patch('thor_migration_audit.Device', return_value=device), \
                 patch('thor_migration_audit.cloud_snapshot') as cloud, \
                 patch('thor_migration_audit.local_observation') as observe, \
                 patch('sys.stdout', new_callable=io.StringIO):
                main()
            records = [json.loads(line) for line in output.read_text().splitlines()]
        cloud.assert_not_called()
        observe.assert_not_called()
        device.private.assert_not_called()
        self.assertEqual(device.shell.call_count, 3)
        self.assertEqual(records[0]['cloudEvidence'], 'inventory_only_no_cloud_evidence')
        self.assertEqual(records[1]['comparison'], 'cloud_not_observed')
        self.assertFalse(records[1]['removalAuthorized'])
        self.assertEqual(records[1]['remainingGates'], GATES)
        self.assertIn('defensible_retention', records[1]['remainingGates'])
        self.assertEqual(records[-1]['kind'], 'completed')
        self.assertFalse(records[-1]['removalAuthorized'])

    def test_inventory_only_preserves_unstable_files_and_non_roms(self):
        root = '/storage/card/Roms/gg'
        device = Mock()
        device.shell.side_effect = [root.encode(),
            (root + '/Game.zip\0' + root + '/settings.txt\0').encode(),
            self.bulk_regular(root + '/Game.zip', after='1 2 4 4 5') +
            self.bulk_regular(root + '/settings.txt')]
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'private.jsonl'
            argv = ['audit', '--adb', 'adb', '--serial', 'fixture',
                    '--platform', 'gamegear', '--root', root, '--extension', '.zip',
                    '--inventory-only', '--output', str(output)]
            with patch('sys.argv', argv), patch('thor_migration_audit.Device', return_value=device), \
                 patch('thor_migration_audit.cloud_snapshot') as cloud, \
                 patch('thor_migration_audit.local_observation') as observe, \
                 patch('sys.stdout', new_callable=io.StringIO):
                main()
            records = [json.loads(line) for line in output.read_text().splitlines()]
        cloud.assert_not_called()
        observe.assert_not_called()
        self.assertEqual(records[1]['comparison'], 'local_changed')
        self.assertEqual(records[2]['comparison'], 'non_rom_preserved')
        self.assertTrue(all(record['removalAuthorized'] is False for record in records))


if __name__ == '__main__':
    unittest.main()
