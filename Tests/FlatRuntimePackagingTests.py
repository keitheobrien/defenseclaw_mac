"""Exercise trust and archive boundaries without signing or executing fixture binaries."""
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('flat', Path(__file__).resolve().parents[1] / 'scripts/prepare_flat_runtime.py')
flat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flat)

class FlatRuntimePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_checksums_reject_duplicates_paths_and_bad_hashes(self):
        path = self.root / 'checksums'
        row = 'a' * 64 + '  safe.whl\n'
        path.write_text(row)
        self.assertEqual(flat.checksum_entries(path), {'safe.whl': 'a' * 64})
        for value in [row + row, 'a' * 64 + '  ../escape\n', 'bad  file\n']:
            path.write_text(value)
            with self.assertRaises(ValueError): flat.checksum_entries(path)

    def test_lock_requires_exact_pins_hashes_and_trusted_urls(self):
        path = self.root / 'lock'
        good = 'example==1.0 ; python_version >= "3.10" \\\n    --hash=sha256:' + 'a' * 64 + '\n'
        path.write_text(good)
        flat.validate_requirements(path)
        for value in ['', 'example==1.0', good.replace('==1.0', '>=1.0'), '--extra-index-url https://example.test\n' + good, good.replace('example==1.0', 'example @ https://example.test/file.whl')]:
            path.write_text(value)
            with self.assertRaises(ValueError): flat.validate_requirements(path)

    def archive(self, entries):
        path = self.root / 'runtime.tar.gz'
        with tarfile.open(path, 'w:gz') as archive:
            for name, link in entries:
                info = tarfile.TarInfo(name)
                info.size = 3
                if link:
                    info.type = tarfile.SYMTYPE
                    info.linkname = '../outside'
                archive.addfile(info, io.BytesIO(b'abc'))
        return path

    def test_extracts_only_complete_regular_binary_pair(self):
        path = self.archive([('defenseclaw-gateway', False), ('defenseclaw-acp', False), ('../escape', False)])
        output = self.root / 'output'
        output.mkdir()
        flat.extract_binaries(path, output)
        self.assertEqual(sorted(p.name for p in output.iterdir()), ['defenseclaw-acp', 'defenseclaw-gateway'])
        self.assertFalse((self.root / 'escape').exists())

    def test_rejects_missing_symlink_and_duplicate_executables(self):
        for index, entries in enumerate([[('defenseclaw-gateway', False)], [('defenseclaw-gateway', True), ('defenseclaw-acp', False)], [('defenseclaw-gateway', False)] * 2]):
            output = self.root / str(index)
            output.mkdir()
            with self.assertRaises(ValueError): flat.extract_binaries(self.archive(entries), output)

if __name__ == '__main__': unittest.main()
