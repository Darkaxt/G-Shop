"""Bounded regression for the production published-folder lookup, no network."""
import json
from pathlib import Path
import re
import sqlite3
import unittest


class CatalogueClassificationQueryTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parent.parent
        source = (root / 'lib/services/library_store.dart').read_text(encoding='utf-8')
        method = source[source.index('static Future<EditionIdentity> _classifyCatalogueFolders'):]
        self.sql = re.search(r"final files = await db.rawQuery\('''(.*?)'''", method, re.S).group(1)
        schema = (root / 'lib/services/drive/drive_catalogue.dart').read_text(encoding='utf-8')
        self.db = sqlite3.connect(':memory:')
        self.db.row_factory = sqlite3.Row
        for statement in re.findall(r"db.execute\('''(.*?)'''\)", schema, re.S)[:3]:
            self.db.execute(statement)
        self.scope = json.dumps(['source', 'account', 'root'], separators=(',', ':'))
        self.prefix = json.dumps(['source', 'account'], separators=(',', ':'))[:-1] + ','
        self.db.execute('INSERT INTO drive_catalogue_state VALUES (?,1,2,3)', (self.scope,))
        self.entry(self.scope, 1, 'target')

    def tearDown(self):
        self.db.close()

    def entry(self, scope, generation, file_id, folder=0):
        self.db.execute('INSERT INTO drive_catalogue_entries VALUES (?,?,?,?,?,?,?)',
                        (scope, generation, file_id, 'parent', 'fixture', folder, '{}'))

    def lookup(self):
        steps = 0

        def progress():
            nonlocal steps
            steps += 1
            return 0  # Observation only; never cancels or changes the query.

        self.db.set_progress_handler(progress, 1)
        try:
            rows = list(self.db.execute(self.sql, ('target', self.prefix, self.prefix)))
        finally:
            self.db.set_progress_handler(None, 0)
        return rows, steps

    def test_unpublished_collection_size_does_not_drive_per_artifact_work(self):
        before, baseline = self.lookup()
        self.assertEqual(len(before), 1)
        self.db.executemany('INSERT INTO drive_catalogue_entries VALUES (?,2,?,NULL,?,0,?)',
                            ((self.scope, 'pending-' + str(i), 'fixture', '{}')
                             for i in range(20000)))
        after, expanded = self.lookup()
        self.assertEqual([dict(row) for row in after], [dict(row) for row in before])
        self.assertLessEqual(expanded, baseline + 100,
                             f'Published lookup grew from {baseline} to {expanded} VM steps')

    def test_exact_scope_active_generation_folder_and_ambiguity_are_preserved(self):
        foreign = json.dumps(['source', 'account-other', 'root'], separators=(',', ':'))
        pending = json.dumps(['source', 'account', 'pending-root'], separators=(',', ':'))
        for scope, active in ((foreign, 1), (pending, None)):
            self.db.execute('INSERT INTO drive_catalogue_state VALUES (?,?,2,3)', (scope, active))
            self.entry(scope, 2 if active is None else 1, 'target')
        folder_scope = json.dumps(['source', 'account', 'folder-root'], separators=(',', ':'))
        self.db.execute('INSERT INTO drive_catalogue_state VALUES (?,1,NULL,2)', (folder_scope,))
        self.entry(folder_scope, 1, 'target', folder=1)
        self.assertEqual(len(self.lookup()[0]), 1)
        other = json.dumps(['source', 'account', 'other-root'], separators=(',', ':'))
        self.db.execute('INSERT INTO drive_catalogue_state VALUES (?,1,NULL,2)', (other,))
        self.entry(other, 1, 'target')
        self.assertEqual(len(self.lookup()[0]), 2)  # Caller must reject ambiguity.


if __name__ == '__main__':
    unittest.main()
