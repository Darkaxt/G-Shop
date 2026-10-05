"""Focused contracts for the S7 read-only audit; no device/network requests."""
import io
import unittest
from unittest.mock import Mock, patch

from thor_migration_audit import Device, compare_observation, checked_relative_path


class MigrationAuditTests(unittest.TestCase):
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


if __name__ == '__main__':
    unittest.main()
