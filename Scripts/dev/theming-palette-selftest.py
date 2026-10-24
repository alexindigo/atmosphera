#!/usr/bin/env python3
"""Actual positional-palette rendering, compared to the pinned PR base in VM."""
from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASE = Path(os.environ['THEMING_PALETTE_BASELINE'])


class PaletteTests(unittest.TestCase):
    """Observe rendered files and diagnostics, not normalization implementation."""

    def render(self, source, data, template='{{colors.brand.default.hex}}', scheme=False):
        """Run the real CLI once and return its rendered file and JSON palette."""
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            palette, input_template, output, colors = [directory / name for name in ('palette.json', 'input.txt', 'output.txt', 'colors.json')]
            palette.write_text(json.dumps(data))
            input_template.write_text(template)
            command = ['timeout', '15', sys.executable, '-B', str(source / 'Scripts/python/src/theming/template-processor.py')]
            command += ['--scheme', str(palette)] if scheme else [str(palette)]
            command += ['--both', '--render', f'{input_template}:{output}', '--output', str(colors)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=20)
            return result, output.read_bytes() if output.exists() else None, json.loads(colors.read_text()) if colors.exists() else None

    def test_generic_palettes_match_pr_base(self):
        for data in ({'brand': '#112233'}, {'colors': {'brand': '#112233'}},
                     {'colors': {'brand': {'default': {'hex': '#112233'}}}},
                     {'brand': '#112233', 'metadata': 'not-a-colour'}):
            with self.subTest(data=data):
                old, before, old_colors = self.render(BASE, data)
                result, after, colors = self.render(ROOT, data)
                self.assertEqual(old.returncode, 0, old.stderr)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(before, b'#112233')
                self.assertEqual(after, before)
                self.assertEqual(colors, old_colors)

    def test_authored_pair_is_kept(self):
        data = {'brand': '#112233', 'standout': '#abcdef', 'on_standout': '#123456'}
        result, rendered, colors = self.render(ROOT, data, '{{colors.standout.dark.hex}} {{colors.on_standout.light.hex}}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(rendered, b'#abcdef #123456')
        self.assertEqual(colors, {'dark': data, 'light': data})

    def test_authored_fill_can_derive_only_its_foreground(self):
        result, rendered, colors = self.render(ROOT, {'standout': '#757575'}, '{{colors.standout.default.hex}}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(rendered, b'#757575')
        self.assertEqual(colors['light']['on_standout'], '#ffffff')
        self.assertNotEqual(colors['dark']['on_standout'], colors['light']['on_standout'])

    def test_authored_foreground_does_not_require_a_fill(self):
        data = {'on_standout': '#123456'}
        result, rendered, colors = self.render(ROOT, data, '{{colors.on_standout.default.hex}}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(rendered, b'#123456')
        self.assertEqual(colors, {'dark': data, 'light': data})

    def test_legacy_palette_uses_shared_dark_reference(self):
        data = json.loads((ROOT / 'Assets/ColorScheme/MacOS/MacOS.json').read_text())['dark']
        data.pop('mStandout'); data.pop('mOnStandout')
        before = deepcopy(data)
        result, rendered, colors = self.render(ROOT, data, '{{colors.standout.dark.hex}} {{colors.standout.light.hex}}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(rendered, b'#f88349 #f88349')
        for mode in ('dark', 'light'):
            self.assertEqual(colors[mode]['on_standout'], '#571f00')
            for key, value in before.items():
                self.assertEqual(colors[mode][key], value if isinstance(value, str) else str(value))

    def test_unavailable_standout_is_diagnosed_not_fabricated(self):
        result, rendered, colors = self.render(ROOT, {'brand': '#112233'}, '{{colors.standout.default.hex}}')
        self.assertIn("Unknown color 'standout'", result.stdout + result.stderr)
        self.assertNotIn('standout', colors['dark'])

    def test_malformed_full_scheme_still_rejected(self):
        result, rendered, colors = self.render(ROOT, {'brand': '#112233'}, scheme=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(rendered)
        result, rendered, colors = self.render(ROOT, {'primary': 'not-a-colour', 'tertiary': '#112233', 'surface': '#ffffff'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(rendered)


if __name__ == '__main__':
    unittest.main(verbosity=2)
