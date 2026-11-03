"""Boundary tests for immutable build inputs and untrusted runtime seed archives."""
from pathlib import Path
from types import SimpleNamespace
import copy
import hashlib
import importlib.util
import io
import json
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


prepare = module('prepare_test', 'prepare-runtime.py')
builder = module('builder_test', 'build-extension.py')


class SeedBoundary(unittest.TestCase):
    def archive(self, directory, names, symlink=False):
        seed = directory / 'seed.tar.gz'
        with tarfile.open(seed, 'w:gz') as archive:
            for name in names:
                item = tarfile.TarInfo(name)
                if symlink:
                    item.type = tarfile.SYMTYPE
                    item.linkname = '../escape'
                    archive.addfile(item)
                else:
                    item.size = 4
                    archive.addfile(item, io.BytesIO(b'data'))
        lock = copy.deepcopy(prepare.LOCK)
        lock['seed'].update(sha256=hashlib.sha256(seed.read_bytes()).hexdigest(), size=seed.stat().st_size,
                            members={name: hashlib.sha256(b'data').hexdigest() for name in names})
        return seed, lock

    def test_traversal_rejected_even_if_archive_and_member_hashes_match(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            seed, lock = self.archive(directory, ['../escape'])
            with patch.object(prepare, 'LOCAL', directory / 'local'), patch.object(prepare, 'LOCK', lock):
                with self.assertRaisesRegex(ValueError, 'Unsafe archive path'):
                    prepare.prepare(seed)
            self.assertFalse((directory / 'escape').exists())

    def test_duplicate_member_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            seed, lock = self.archive(directory, ['public/file', 'public/file'])
            with patch.object(prepare, 'LOCAL', directory / 'local'), patch.object(prepare, 'LOCK', lock):
                with self.assertRaisesRegex(ValueError, 'Unexpected seed member'):
                    prepare.prepare(seed)

    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            seed, lock = self.archive(directory, ['public/file'], symlink=True)
            with patch.object(prepare, 'LOCAL', directory / 'local'), patch.object(prepare, 'LOCK', lock):
                with self.assertRaisesRegex(ValueError, 'Unexpected seed member'):
                    prepare.prepare(seed)

    def test_archive_hash_failure_precedes_extraction(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            seed, lock = self.archive(directory, ['public/file'])
            lock['seed']['sha256'] = '0' * 64
            with patch.object(prepare, 'LOCAL', directory / 'local'), patch.object(prepare, 'LOCK', lock):
                with self.assertRaisesRegex(ValueError, 'checksum/size mismatch'):
                    prepare.prepare(seed)
            self.assertFalse((directory / 'local/runtime-seed.extracting').exists())


class DescriptorBoundary(unittest.TestCase):
    def test_invalid_descriptor_has_failure_record_and_no_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            descriptor = directory / 'descriptor.json'
            descriptor.write_text(json.dumps({'schemaVersion': 99, 'packageName': 'invalid'}))
            output = directory / 'output'
            args = SimpleNamespace(output=output, descriptor=descriptor, upstream=ROOT / 'vendor/extensions-source')
            self.assertEqual(builder.build(args), 1)
            result = json.loads((output / 'build-result.json').read_text())
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['stage'], 'upstream')
            self.assertEqual(result['artifacts'], [])
            self.assertFalse((output / 'manifest.json').exists())

    def test_existing_manifest_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = directory / 'manifest.json'
            manifest.write_text('original')
            with self.assertRaisesRegex(ValueError, 'immutable manifest'):
                builder.build(SimpleNamespace(output=directory))
            self.assertEqual(manifest.read_text(), 'original')


if __name__ == '__main__':
    unittest.main()
