"""Offline adversarial checks. All archive contents here are hypothetical."""

import hashlib
import importlib.util
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "inspect_zip.py"
SPEC = importlib.util.spec_from_file_location("inspect_zip", SCRIPT)
inspector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inspector)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / "test.zip"

    def write_archive(self, entries, compression=zipfile.ZIP_STORED):
        with zipfile.ZipFile(self.archive, "w", compression=compression) as archive:
            for name, content in entries:
                archive.writestr(name, content)

    def test_hashes_bytes_without_extraction_or_execution(self):
        content = b"raise RuntimeError('must never execute')\n"
        self.write_archive([("raw/", b""), ("raw/collect.py", content)])
        original = self.archive.read_bytes()
        result = inspector.inspect_archive(self.archive)
        self.assertEqual(result["archive_sha256"], hashlib.sha256(original).hexdigest())
        self.assertEqual(result["members"][1]["sha256"], hashlib.sha256(content).hexdigest())
        self.assertEqual(result["scientific_validation"], "not_performed")
        self.assertEqual(self.archive.read_bytes(), original)
        self.assertEqual(list(Path(self.temp.name).iterdir()), [self.archive])

    def test_unsafe_paths(self):
        for name in ("../x", "/x", "a/../x", "C:/x", "a\\x", "a//x", "./x", "a./x", "NUL.txt", "a\nx", "a\x00x"):
            with self.subTest(name=name):
                # ZipInfo truncates NUL on write; patch the serialized name instead.
                if "\x00" in name:
                    self.write_archive([("a_x", b"x")])
                    self.archive.write_bytes(self.archive.read_bytes().replace(b"a_x", b"a\x00x"))
                else:
                    self.write_archive([(name, b"x")])
                with self.assertRaises(inspector.ArchiveRejected):
                    inspector.inspect_archive(self.archive)

    def test_case_collisions(self):
        self.write_archive([("a", b"x"), ("A", b"y")])
        with self.assertRaises(inspector.ArchiveRejected):
            inspector.inspect_archive(self.archive)

    def test_file_parent_collision(self):
        self.write_archive([("a", b"x"), ("a/b", b"y")])
        with self.assertRaises(inspector.ArchiveRejected):
            inspector.inspect_archive(self.archive)

    def test_symlink_rejected(self):
        member = zipfile.ZipInfo("link")
        member.create_system = 3
        member.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.write_archive([(member, b"../elsewhere")])
        with self.assertRaises(inspector.ArchiveRejected):
            inspector.inspect_archive(self.archive)

    def test_budgets(self):
        self.write_archive([("a", b"hello"), ("b", b"world")])
        for key, limit in (("MAX_ARCHIVE_BYTES", 2), ("MAX_MEMBERS", 1), ("MAX_MEMBER_BYTES", 4), ("MAX_TOTAL_BYTES", 9)):
            with self.subTest(key=key), patch.object(inspector, key, limit):
                with self.assertRaises(inspector.ArchiveRejected):
                    inspector.inspect_archive(self.archive)

    def test_compression_bomb_rejected(self):
        self.write_archive([("a", b"0" * 100000)], compression=zipfile.ZIP_DEFLATED)
        with self.assertRaises(inspector.ArchiveRejected):
            inspector.inspect_archive(self.archive)

    def test_corrupt_member_rejected(self):
        self.write_archive([("a", b"unique-content")])
        self.archive.write_bytes(self.archive.read_bytes().replace(b"unique-content", b"broken-content"))
        with self.assertRaises(zipfile.BadZipFile):
            inspector.inspect_archive(self.archive)


if __name__ == "__main__":
    unittest.main()
