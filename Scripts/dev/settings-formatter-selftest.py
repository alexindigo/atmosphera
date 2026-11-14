#!/usr/bin/env python3
"""Refuse formatter drift before formatting reproducible schema resources."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('schema', ROOT / 'Scripts/dev/build-settings-schema.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FormatterVersion(unittest.TestCase):
    def test_wrong_or_unreadable_version_never_formats(self):
        for output, status in [('qmlformat 6.13.0\n', 0), ('qmlformat 6.12.1\n', 0),
                               ('not a version\n', 0), ('', 1)]:
            with self.subTest(output=output, status=status):
                calls = []

                def run(argv, **kwargs):
                    calls.append(argv)
                    return SimpleNamespace(returncode=status, stdout=output, stderr='')

                with patch.object(module.shutil, 'which', return_value='/private/qmlformat'), \
                        patch.object(module.subprocess, 'run', run):
                    with self.assertRaisesRegex(ValueError, 'qmlformat.*6[.]12[.]0'):
                        module.outputs(ROOT)
                self.assertEqual(calls, [['/private/qmlformat', '--version']])

    def test_matching_formatter_preserves_resources(self):
        for name, text in module.outputs(ROOT).items():
            self.assertEqual((ROOT / name).read_bytes(), text.encode(), name)


if __name__ == '__main__':
    unittest.main()
