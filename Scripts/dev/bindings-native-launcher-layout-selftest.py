#!/usr/bin/env python3
"""Synthetic legacy/current signature controls; assigned project VM only."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
from unittest import mock
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('native_launcher_selftest', HERE / 'bindings-native-launcher-selftest.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def fixture(layout):
    pixels = bytearray(b'\x1e\x1e\x1e' * (500 * 120))

    def put(x, y, color):
        start = (y * 500 + x) * 3
        pixels[start:start + 3] = bytes(color)

    if layout == 'legacy':
        for x in range(20, 430):
            put(x, 11, (100, 100, 100))
        put(20, 78, (140, 20, 200))
    else:
        for y in (11, 46):
            for x in range(20, 431):
                put(x, y, (120, 60, 180))
        for y in (70, 78, 86):
            for x in range(50, 101):
                put(x, y, (20, 130, 250))
        for x in range(200, 211):
            put(x, 78, (60, 60, 60))
        if layout == 'apps':
            put(480, 28, (50, 50, 50))
            put(464, 28, (50, 50, 50))
        else:
            for y in (11, 46):
                for x in range(455, 481):
                    put(x, y, (120, 60, 180))
    return pixels


class LauncherLayoutTests(unittest.TestCase):
    def test_supported_layouts_keep_their_applicable_rejecting_controls(self):
        for layout in ('legacy', 'apps', 'clipboard'):
            with self.subTest(layout=layout):
                output = io.StringIO()
                with mock.patch('sys.argv', ['selftest', '--capture', layout + '.png']), \
                        mock.patch.object(runner.subprocess, 'check_output', return_value=fixture(layout)), \
                        contextlib.redirect_stdout(output):
                    runner.main()
                result = json.loads(output.getvalue())
                self.assertEqual(result['status'], 'PASS')
                self.assertEqual(result['captures'][0]['missingGeometryRejected'], 2 if layout == 'legacy' else 3)
                self.assertTrue(result['malformedAndBlankRejected'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
