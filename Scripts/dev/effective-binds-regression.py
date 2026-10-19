#!/usr/bin/env python3
"""Guest-only structural regressions for the shared effective-bind contract.

Run with --source TREE --output FRESH_DISK_DIRECTORY. Native compositor/consumer
cases are separate: these fixtures exercise include/normalization/ownership
semantics without starting or modifying a desktop session.
"""
import argparse
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class Contract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=OUT / 'fixtures')
        self.addCleanup(self.temp.cleanup)
        self.dir = Path(self.temp.name)

    def file(self, name, text):
        path = self.dir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def mango(self, text):
        root = self.file('config.conf', text)
        scan = M.Inventory([self.dir / 'atmosphera-input.conf'])
        scan.conf(root, 'mango', self.dir)
        return scan

    def niri(self, text):
        self.file('config.kdl', text)
        with patch.object(M, 'process_config', return_value=(self.dir / 'config.kdl', None)):
            return M.inventory('niri', self.dir)

    def hypr(self, text):
        scan = M.Inventory([self.dir / 'atmosphera-input.conf'])
        scan.conf(self.file('hyprland.conf', text), 'hypr')
        return scan

    def row(self, dispatcher='__lua', arg='123', submap='', **kw):
        return dict(modmask=8, key='space', dispatcher=dispatcher, arg=arg, submap=submap,
                    description='Input method: forged user description', **kw)

    def test_aliases_and_key_case(self):
        self.assertEqual(M.combo('CONTROL+mod1+SPACE'), 'Ctrl+Alt+space')
        self.assertEqual(M.combo('Win+Shift+Enter'), M.combo('SHIFT+MOD4+Return'))
        self.assertEqual(M.combo('Alt+Alt+Page_Up'), 'Alt+prior')

    def test_mango_eager_sources_mode_and_root_relative_path(self):
        self.file('nested/a.conf', 'keymode=resize\nsource=./b.conf\n')
        self.file('b.conf', 'bind=ALT,SPACE,spawn,root-file\nkeymode=common\n')
        self.file('nested/b.conf', 'bind=ALT,SPACE,spawn,WRONG\n')
        scan = self.mango('source=./nested/a.conf\nbind=Ctrl,space,spawn,after-source\n')
        self.assertFalse(scan.unknown)
        self.assertEqual([(e['mode'], e['action']) for e in scan.entries],
                         [('resize', 'spawn root-file'), ('common', 'spawn after-source')])
        self.assertEqual(scan.entries[0]['file'], str(self.dir / 'b.conf'))

    def test_mango_digit_keysyms_are_not_physical_codes(self):
        scan = self.mango('bind=SUPER,1,view,1\nbind=Alt,space,spawn,rofi -show drun\n')
        self.assertFalse(scan.unknown)
        self.assertEqual(scan.entries[0]['combo'], 'Super+1')

    def test_generated_empty_file_records_ambient_mode(self):
        self.file('atmosphera-input.conf', '')
        scan = self.mango('keymode=resize\nsource=./atmosphera-input.conf\nkeymode=default\n')
        self.assertEqual(scan.generated_modes, {'resize'})

    def test_mango_source_optional_missing_is_unknown(self):
        scan = self.mango('source-optional=./absent.conf\n')
        self.assertIn('cannot read', ';'.join(scan.unknown))

    def test_recursive_include_is_unknown_not_free(self):
        scan = self.mango('source=./config.conf\n')
        self.assertIn('recursive include', ';'.join(scan.unknown))

    def test_unreadable_include_is_unknown(self):
        target = self.file('private.conf', 'bind=Alt,space,spawn,private\n')
        target.chmod(0)
        try:
            scan = self.mango('source=./private.conf\n')
        finally:
            target.chmod(0o600)
        self.assertIn('cannot read', ';'.join(scan.unknown))

    def test_niri_positional_include_and_later_override(self):
        self.file('nested/a.kdl', 'include "b.kdl"\nbinds { Alt+Space { spawn "last"; }; }\n')
        self.file('nested/b.kdl', 'binds { Alt+Space { spawn "middle"; }; }\n')
        result = self.niri('binds { Alt+Space { spawn "first"; }; }\ninclude "nested/a.kdl"\n')
        self.assertFalse(result['unknown'])
        self.assertEqual(len(result['entries']), 1)
        self.assertIn('last', result['owners']['Alt+space'])
        self.assertIn('nested/a.kdl:2', result['owners']['Alt+space'])

    def test_niri_generated_does_not_hide_user_occupant(self):
        self.file('atmosphera-input.kdl', 'binds { Alt+Space { spawn "own"; }; }\n')
        result = self.niri('binds { Alt+Space { spawn "external"; }; }\ninclude "atmosphera-input.kdl"\n')
        self.assertIn('external', result['owners']['Alt+space'])
        self.assertNotIn('own', result['owners']['Alt+space'])

    def test_niri_comments_disabled_nodes_and_multiline_strings(self):
        result = self.niri('''/* braces { and /* nested */ includes are ignored */
/-include "absent.kdl"
binds {
    /-Alt+Space { spawn "disabled"; }
    Alt+Return
    { spawn "https://example.test/{x}"; }
}
'''.replace('Alt+Return\n', 'Alt+Return \\\n'))
        self.assertFalse(result['unknown'])
        self.assertNotIn('Alt+space', result['owners'])
        self.assertIn('https://example.test/{x}', result['owners']['Alt+return'])

    def test_niri_mod_key_is_global_and_positional(self):
        result = self.niri('binds { Mod+Space { spawn "virtual"; }; Super+Space { spawn "super"; }; }\ninput { mod-key "Alt"; }\n')
        self.assertFalse(result['unknown'])
        self.assertIn('virtual', result['owners']['Alt+space'])
        self.assertIn('super', result['owners']['Super+space'])

    def test_niri_raw_strings_in_properties_and_includes(self):
        self.file('raw.kdl', 'binds { Alt+Space { spawn "raw-source"; }; }\n')
        result = self.niri('window-rule { match app-id=r#"^org\\.example$"#; }\ninclude r#"raw.kdl"#\n')
        self.assertFalse(result['unknown'])
        self.assertIn('raw-source', result['owners']['Alt+space'])

    def test_niri_missing_recursive_and_invalid_are_unknown(self):
        for text in ('include optional=true "absent.kdl"\n', 'include "config.kdl"\n', 'binds {', 'binds {}\nbinds {}\n'):
            with self.subTest(text=text):
                self.assertTrue(self.niri(text)['unknown'])

    def test_hypr_static_variables_sources_submaps_unbind(self):
        self.file('keys.conf', 'bindd=$main,SPACE,Title,exec,rofi -show drun\n')
        scan = self.hypr('$main=MOD1\nsource=./keys.conf\nsubmap=resize\nbind=ALT,space,exec,resize\nunbind=ALT,space\nsubmap=reset\n')
        self.assertFalse(scan.unknown)
        self.assertEqual(len(scan.entries), 1)
        self.assertEqual(scan.entries[0]['action'], 'exec rofi -show drun')
        self.assertIn('keys.conf:1', M.diagnostic(scan.entries[0]))

    def test_hypr_static_glob_new_files_and_unknowns(self):
        self.file('keys/a.conf', 'bind=ALT,space,exec,a\n')
        root = self.file('hyprland.conf', 'source=./keys/*.conf\n')
        scan = M.Inventory()
        scan.conf(root, 'hypr')
        self.assertEqual(len(scan.entries), 1)
        self.file('keys/b.conf', 'bind=CTRL,space,exec,b\n')
        refreshed = M.Inventory()
        refreshed.conf(root, 'hypr')
        self.assertEqual(len(refreshed.entries), 2)
        self.assertTrue(self.hypr('source=$missing/*.conf\n').unknown)

    def test_hypr_live_precise_static_attribution(self):
        scan = self.hypr('bind=Alt,space,exec,rofi -show drun\n')
        rows = M.hypr_live(scan, [self.row('exec', 'rofi -show drun')], self.dir / 'absent.lua')
        self.assertEqual(len(rows), 1)
        self.assertIn('hyprland.conf:1', M.diagnostic(rows[0]))

    def test_hypr_dynamic_lua_is_opaque_even_with_forged_description(self):
        scan = self.hypr('')
        rows = M.hypr_live(scan, [self.row()], self.dir / 'absent.lua')
        self.assertEqual(len(rows), 1)
        text = M.diagnostic(rows[0])
        self.assertIn('a Lua function (source unavailable — live Hyprland binding)', text)
        self.assertNotIn('123', json.dumps(rows))

    def test_hypr_generated_hyprlang_exact_multiset_and_submap(self):
        self.file('atmosphera-input.conf', 'bindld=ALT,space,Input method: Japanese,exec,atmosphera ipc inputmethod toggleIM mozc\n')
        scan = self.hypr('source=./atmosphera-input.conf\n')
        own = self.row('exec', 'atmosphera ipc inputmethod toggleIM mozc')
        self.assertEqual(M.hypr_live(scan, [own], self.dir / 'absent.lua'), [])
        self.assertEqual(len(M.hypr_live(scan, [own, own], self.dir / 'absent.lua')), 1)
        self.assertEqual(len(M.hypr_live(scan, [dict(own, submap='resize')], self.dir / 'absent.lua')), 1)
        self.assertEqual(len(M.hypr_live(scan, [self.row('exec', 'different')], self.dir / 'absent.lua')), 1)

    def test_hypr_generated_lua_counts_and_surplus(self):
        lua = self.file('atmosphera-input.lua', 'hl.bind("ALT + Space", hl.dsp.exec_cmd("own"), {description="Input method: Japanese"})\n')
        scan = self.hypr('')
        self.assertEqual(M.hypr_live(scan, [self.row()], lua), [])
        surplus = M.hypr_live(scan, [self.row(), self.row(arg='999')], lua)
        self.assertEqual(len(surplus), 1)
        self.assertIn('a Lua function', M.diagnostic(surplus[0]))
        self.assertNotIn('999', json.dumps(surplus))
        self.assertEqual(len(M.hypr_live(scan, [self.row(submap='resize')], lua)), 1)

    def test_stopped_lua_is_unknown_never_executed(self):
        root = self.file('hyprland.lua', 'error("must never execute config")\n')
        def fake(argv):
            return SimpleNamespace(returncode=0, stdout=f'lua\n{root}\n{self.dir}\n', stderr='') if argv[0] == 'bash' else SimpleNamespace(returncode=1, stdout='', stderr='stopped')
        with patch.object(M, 'command', side_effect=fake):
            result = M.inventory('hypr', self.dir)
        self.assertIn('Lua coverage unknown', result['unknown'])
        self.assertEqual(result['owners'], {})


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    a = ap.parse_args()
    assert os.getuid() != 0 and Path.home() == Path('/home/tester'), 'run in the assigned guest as tester'
    assert Path(os.environ['TMPDIR']).is_relative_to(Path('/home/tester/Projects/atmosphera-cc'))
    OUT = a.output.resolve()
    assert not OUT.exists(), OUT
    OUT.mkdir()
    (OUT / 'fixtures').mkdir()
    spec = importlib.util.spec_from_file_location('effective_binds', a.source.resolve() / 'Scripts/python/src/inputmethod/effective-binds.py')
    M = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(M)
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Contract))
    (OUT / 'tests.log').write_text(stream.getvalue())
    receipt = dict(tests=result.testsRun, failures=len(result.failures), errors=len(result.errors), passed=result.wasSuccessful())
    (OUT / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(stream.getvalue(), end='')
    print(json.dumps(receipt))
    raise SystemExit(0 if result.wasSuccessful() else 1)
