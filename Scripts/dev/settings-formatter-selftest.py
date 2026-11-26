#!/usr/bin/env python3
"""Refuse formatter drift before formatting reproducible schema resources."""
import importlib.util
import re
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
        major, minor, revision = map(int, module.REQUIRED_QMLFORMAT_VERSION.split('.'))
        wrong_minor = f'qmlformat {major}.{minor + 1}.0\n'
        wrong_patch = f'qmlformat {major}.{minor}.{revision + 1}\n'
        required = re.escape(f'qmlformat {module.REQUIRED_QMLFORMAT_VERSION} required')
        for output, status in [(wrong_minor, 0), (wrong_patch, 0),
                               ('not a version\n', 0), ('', 1)]:
            with self.subTest(output=output, status=status):
                calls = []

                def run(argv, **kwargs):
                    calls.append(argv)
                    return SimpleNamespace(returncode=status, stdout=output, stderr='')

                with patch.object(module.shutil, 'which', return_value='/private/qmlformat'), \
                        patch.object(module.subprocess, 'run', run):
                    with self.assertRaisesRegex(ValueError, required):
                        module.outputs(ROOT)
                self.assertEqual(calls, [['/private/qmlformat', '--version']])

    def test_matching_formatter_preserves_resources(self):
        for name, text in module.outputs(ROOT).items():
            self.assertEqual((ROOT / name).read_bytes(), text.encode(), name)


if __name__ == '__main__':
    unittest.main()
