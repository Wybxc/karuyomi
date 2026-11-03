"""Regressions for exact upstream patch application and source drift rejection."""
from pathlib import Path
import tempfile
import unittest

from upstream_sources import ROOT, PATCHES, apply_patch, prepare_sources


class UpstreamSourcesTest(unittest.TestCase):
    def test_replacement_insertion_and_deletion(self):
        patch = '--- a/file\n+++ b/file\n@@ -1,3 +1,3 @@\n first\n-old\n+new\n last\n'
        self.assertEqual(apply_patch('first\nold\nlast\n', patch), 'first\nnew\nlast\n')
        insert = '--- a/file\n+++ b/file\n@@ -0,0 +1 @@\n+new\n'
        self.assertEqual(apply_patch('', insert), 'new\n')
        delete = '--- a/file\n+++ b/file\n@@ -1 +0,0 @@\n-old\n'
        self.assertEqual(apply_patch('old\n', delete), '')

    def test_context_drift_and_malformed_ranges_fail(self):
        patch = '--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new\n'
        with self.assertRaisesRegex(ValueError, 'context'):
            apply_patch('changed\n', patch)
        with self.assertRaisesRegex(ValueError, 'length'):
            apply_patch('old\n', patch.replace('@@ -1 +1 @@', '@@ -1,2 +1 @@'))
        with self.assertRaises(ValueError):
            apply_patch('old\n', patch + patch)

    @unittest.skipUnless((ROOT / 'vendor/teavm/classlib').exists(), 'TeaVM submodule is not initialized')
    def test_all_pinned_sources_materialize(self):
        with tempfile.TemporaryDirectory() as temporary:
            outputs = prepare_sources(temporary)
            self.assertEqual(len(outputs), len(PATCHES))
            self.assertTrue(all(path.is_relative_to(Path(temporary)) for path in outputs))

    def test_missing_upstream_fails_with_bootstrap_instruction(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, 'git submodule update'):
                prepare_sources(Path(temporary) / 'out', root=temporary)


if __name__ == '__main__':
    unittest.main()
