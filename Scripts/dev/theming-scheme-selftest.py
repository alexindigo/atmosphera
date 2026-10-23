#!/usr/bin/env python3
"""Legacy/authored scheme contracts; execute only in the assigned VM."""
from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Scripts/python/src/theming'))
from lib.scheme import normalize_scheme, expand_predefined_scheme
from lib.color import Color
from lib.contrast import contrast_ratio
from lib.renderer import TemplateRenderer

EXPECTED = {
    'Ayu': ('#f694ea', '#5b0359'), 'Catppuccin': ('#f29f1a', '#462a00'),
    'Dracula': ('#f8a91f', '#452b00'), 'Eldritch': ('#e5733f', '#521a00'),
    'Gruvbox': ('#fd87c0', '#62023e'), 'Kanagawa': ('#f39583', '#591c11'),
    'MacOS': ('#f88349', '#571f00'), 'Noctalia-default': ('#f594cf', '#5a0f46'),
    'Nord': ('#d18663', '#542106'), 'Rosepine': ('#afaf67', '#323200'),
    'Tokyo-Night': ('#e5733f', '#521a00'),
}


def bundled(name):
    return json.loads((ROOT / f'Assets/ColorScheme/{name}/{name}.json').read_text())


def legacy(data):
    data = deepcopy(data)
    for mode in ('dark', 'light'):
        data[mode].pop('mStandout', None)
        data[mode].pop('mOnStandout', None)
    return data


class SchemeTests(unittest.TestCase):
    def test_all_bundled_authored_and_legacy_values(self):
        self.assertEqual(len(list((ROOT / 'Assets/ColorScheme').glob('*/*.json'))), 11)
        for name, (fill, ink) in EXPECTED.items():
            with self.subTest(name=name):
                data = bundled(name)
                old = legacy(data)
                before = deepcopy(old)
                normalized = normalize_scheme(old)
                self.assertEqual(old, before)
                for mode in ('dark', 'light'):
                    self.assertEqual((normalized[mode]['mStandout'], normalized[mode]['mOnStandout']), (fill, ink))
                    self.assertEqual((data[mode]['mStandout'], data[mode]['mOnStandout']), (fill, ink))
                    self.assertGreaterEqual(contrast_ratio(Color.from_hex(fill), Color.from_hex(ink)), 4.5)
                    self.assertEqual({k: v for k, v in normalized[mode].items() if 'Standout' not in k}, old[mode])
                self.assertEqual(normalize_scheme(normalized), normalized)

    def test_authored_fields_independently_preserved(self):
        data = legacy(bundled('MacOS'))
        data['dark'].update(mStandout='#757575', mOnStandout='#123456')
        data['light']['mStandout'] = '#757575'
        normalized = normalize_scheme(data)
        self.assertEqual(normalized['dark']['mOnStandout'], '#123456')
        self.assertEqual(normalized['light']['mStandout'], '#757575')
        self.assertEqual(normalized['light']['mOnStandout'], '#ffffff')
        data['dark'].pop('mStandout')
        self.assertEqual(normalize_scheme(data)['dark']['mOnStandout'], '#123456')

    def test_flat_single_variant_aliases_and_no_call_order_state(self):
        dark = legacy(bundled('MacOS'))['dark']
        for data in (dark, {'dark': dark}, {'light': dark},
                     {key[1].lower() + key[2:]: value for key, value in dark.items() if key.startswith('m')}):
            normalized = normalize_scheme(data)
            self.assertEqual(normalized['dark']['mStandout'], '#f88349')
            self.assertEqual(normalized['light']['mStandout'], '#f88349')
        normalize_scheme(bundled('Ayu'))
        self.assertEqual(normalize_scheme(dark)['dark']['mStandout'], '#f88349')

    def test_cli_template_and_atomic_save_reload(self):
        data = legacy(bundled('Catppuccin'))
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            path = folder / 'Custom/Custom.json'
            saved = subprocess.run(['timeout', '10', sys.executable, '-B', str(ROOT / 'Scripts/python/src/theming/normalize-scheme.py'), '--save', str(path)],
                                   input=json.dumps(data), text=True, capture_output=True, check=True, timeout=15)
            normalized = json.loads(saved.stdout)
            self.assertEqual(json.loads(path.read_text()), normalized)
            self.assertEqual(list(path.parent.glob('.scheme-*')), [])
            template = folder / 'roles.json'
            rendered = folder / 'rendered.json'
            template.write_text((ROOT / 'Assets/Templates/noctalia.json').read_text())
            path.write_text(json.dumps(data))
            subprocess.run(['timeout', '15', sys.executable, '-B', str(ROOT / 'Scripts/python/src/theming/template-processor.py'), '--scheme', str(path),
                            '--render', f'{template}:{rendered}'], capture_output=True, text=True, check=True, timeout=20)
            result = json.loads(rendered.read_text())
            self.assertEqual((result['mStandout'], result['mOnStandout']), EXPECTED['Catppuccin'])
            for mode in ('dark', 'light'):
                expanded = expand_predefined_scheme(normalized[mode], mode)
                self.assertEqual((expanded['standout'], expanded['on_standout']), EXPECTED['Catppuccin'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
