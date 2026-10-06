"""Bounded regression for production Drive traversal scheduling; no network."""
from pathlib import Path
import re
import sqlite3
import unittest


class DriveCatalogueWorkQueryTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parent.parent
        source = (root / 'lib/services/drive/drive_catalogue.dart').read_text(encoding='utf-8')
        self.sql = re.search(r"final work = await db.rawQuery\(\s*'''(.*?)'''", source, re.S).group(1)
        self.db = sqlite3.connect(':memory:')
        self.db.row_factory = sqlite3.Row
        for statement in re.findall(r"db.execute\('''(.*?)'''\)", source, re.S):
            self.db.execute(statement)

    def tearDown(self):
        self.db.close()

    def folder(self, file_id, *, scope='scope', generation=1, done=0, cursor=None):
        self.db.execute('INSERT INTO drive_catalogue_entries VALUES (?,?,?,?,?,?,?)',
                        (scope, generation, file_id, None, 'fixture/' + file_id, 1, '{}'))
        self.db.execute('INSERT INTO drive_catalogue_work VALUES (?,?,?,?,?)',
                        (scope, generation, file_id, cursor, done))

    def next_folder(self, scope='scope', generation=1):
        steps = 0

        def observe():
            nonlocal steps
            steps += 1
            return 0  # Observation only: never interrupts query execution.

        self.db.set_progress_handler(observe, 1)
        try:
            rows = list(self.db.execute(self.sql, (scope, generation)))
        finally:
            self.db.set_progress_handler(None, 0)
        return rows, steps

    def test_completed_folders_do_not_increase_next_folder_lookup_work(self):
        self.folder('pending', cursor='next-page')
        before, baseline = self.next_folder()
        self.db.execute('DELETE FROM drive_catalogue_work')
        self.db.execute('DELETE FROM drive_catalogue_entries')
        self.db.executemany('INSERT INTO drive_catalogue_entries VALUES (?,1,?,NULL,?,1,?)',
                            (('scope', 'done-' + str(i), 'fixture', '{}') for i in range(20000)))
        self.db.executemany('INSERT INTO drive_catalogue_work VALUES (?,1,?,NULL,1)',
                            (('scope', 'done-' + str(i)) for i in range(20000)))
        self.folder('pending', cursor='next-page')
        after, expanded = self.next_folder()
        self.assertEqual([dict(row) for row in after], [dict(row) for row in before])
        self.assertLessEqual(expanded, baseline + 100,
                             f'Next-folder lookup grew from {baseline} to {expanded} VM steps')

    def test_insertion_order_scope_generation_and_page_cursor_are_preserved(self):
        self.folder('foreign', scope='other')
        self.folder('old-generation', generation=2)
        self.folder('completed', done=1)
        self.folder('z-first', cursor='page-2')
        self.folder('a-second')
        row = self.next_folder()[0][0]
        self.assertEqual(row['file_id'], 'z-first')
        self.assertEqual(row['page_token'], 'page-2')
        self.db.execute("UPDATE drive_catalogue_work SET done=1 WHERE file_id='z-first'")
        self.assertEqual(self.next_folder()[0][0]['file_id'], 'a-second')
        self.db.execute("UPDATE drive_catalogue_work SET done=1 WHERE file_id='a-second'")
        self.assertEqual(self.next_folder()[0], [])


if __name__ == '__main__':
    unittest.main()
