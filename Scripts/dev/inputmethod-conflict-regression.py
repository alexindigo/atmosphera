#!/usr/bin/env python3
"""Guest effective-bind runtime regressions; QEMU keys use a disk handshake.

Source and evidence labels must be fresh. All test-generated configs are restored
in finally. Keys are injected only after the guest proves generation and focus.
The coordinator drives ready-*.json / sent-*.json like the existing IM profiles.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

R = Path('/home/tester/Projects/atmosphera-cc')
MACS = {'niri': '52:54:00:cf:3d:44', 'mango': '52:54:00:51:d6:fd', 'hyprland': '52:54:00:5f:98:a7'}
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--source', type=Path, required=True)
ap.add_argument('--label', required=True)
ap.add_argument('--compositor', choices=MACS, required=True)
ap.add_argument('--capture', action='store_true', help='mango: full screenshot of actual settings panel to runtime capture.png')
a = ap.parse_args()
assert a.label.startswith('c5r1-') and all(c.isalnum() or c == '-' for c in a.label)
assert MACS[a.compositor] in [p.read_text().strip() for p in Path('/sys/class/net').glob('*/address')]
assert os.environ['TMPDIR'] == str(R / 'tmp')
out, work = R / 'evidence' / a.label, R / 'runtime' / a.label
assert not out.exists() and not work.exists()
source = a.source.resolve()

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod

reg = module('imreg', source / 'Scripts/dev/inputmethod-regression.py')
hypr = module('hyprreg', source / 'Scripts/dev/hypr-config-regression.py')
reg.COMP = a.compositor
os.environ.update(XDG_RUNTIME_DIR='/run/user/1000', DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus')
assert reg.sh(['pgrep', '-x', 'qs']).returncode != 0
assert reg.sh(['pgrep', '-x', 'fcitx5']).returncode != 0
out.mkdir()
work.mkdir()
(out / 'keys').mkdir()
config = Path('/home/tester/.config') / {'mango': 'mango', 'niri': 'niri', 'hyprland': 'hypr'}[a.compositor]
shutil.copytree(config, out / 'config-before', symlinks=True)

def digest(directory):
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(directory.rglob('*')) if p.is_file()}

before = digest(config)
fcitx = Path('/home/tester/.config/fcitx5/profile')
fcitx_before = fcitx.read_bytes() if fcitx.exists() else None
manager = dict(s.split('=', 1) for s in reg.sh(['systemctl', '--user', 'show-environment']).stdout.splitlines() if '=' in s)
reg.sh(['systemctl', '--user', 'set-environment', f'TMPDIR={R}/tmp'])
selector = R / 'runtime/c2-session-config-path'
selector_before = selector.read_bytes() if a.compositor == 'hyprland' else None
result = {'source': str(source), 'compositor': a.compositor, 'cases': [], 'before': before, 'passed': False}
contexts = []
ctx = None

def check(case, title, fn):
    rec = dict(case=case, title=title, passed=False)
    result['cases'].append(rec)
    rec['observed'] = fn()
    rec['passed'] = True
    print(f'{case} PASS {title}', flush=True)

def require(pred, message, seconds=15):
    ok, elapsed = reg.wait_for(pred, seconds, 0.2)
    assert ok, message
    return elapsed

def start(tag, root=None):
    global ctx
    if root is not None:
        live = hypr.session(root)
        assert not live['configerrors'], live
        reg.COMP_INSTANCE = live['instance']['instance']
        os.environ.update(HYPRLAND_CONFIG=str(root), HYPRLAND_INSTANCE_SIGNATURE=reg.COMP_INSTANCE,
                          WAYLAND_DISPLAY=live['instance']['wl_socket'])
    elif a.compositor == 'niri':
        reg.COMP_INSTANCE = str(next(Path('/run/user/1000').glob('niri.*.sock')))
    else:
        reg.COMP_INSTANCE = str(next(Path('/run/user/1000').glob('mango-*.sock')))
    os.environ.update(reg.base_env(), **reg.compositor_env())
    child_out = out / tag
    child_out.mkdir()
    ctx = reg.Ctx(source, work / tag, child_out, 'B', a.label + '-' + tag, keys=True)
    contexts.append(ctx)
    reg.setup_work(ctx)
    # Read-only diagnostic endpoint in this disposable test copy. Observe the
    # public conflictFor consumer, without changing product inventory/generation.
    handler = ctx.work / 'shell/Services/Control/IPCService.qml'
    text = handler.read_text()
    anchor = '    function toggleIM(name: string, group: string): string {\n'
    assert text.count(anchor) == 1
    handler.write_text(text.replace(anchor, '    function c5Conflict(combo: string): string { return InputMethodBinds.conflictFor(combo); }\n' + anchor))
    reg.keys_setup(ctx)
    settings_path = ctx.profile_dir / 'config/settings.json'
    settings = json.loads(settings_path.read_text())
    settings['inputMethod'].update(switches=[reg.SWITCH_JA], nextKeys=[], launchFcitx5=False)
    settings_path.write_text(json.dumps(settings))
    reg.start_fcitx5(ctx, reg.PROFILE_B)
    reg.start_focus(ctx)
    reg.start_shell(ctx)
    require(lambda: reg.shell_state(ctx).get('available') if reg.shell_state(ctx) else False, 'IM service unavailable')
    ready, proof = reg.cli_route(ctx)
    (child_out / 'cli-route.json').write_text(json.dumps(dict(passed=ready, **proof), indent=2) + '\n')
    assert ready, f'production atmosphera ipc does not reach this shell: {proof}'
    return ctx

def stop():
    global ctx
    if ctx is None:
        return
    (ctx.output / 'shell-journal.txt').write_text(reg.journal(ctx))
    cleaned = reg.stop_everything(ctx)
    link = reg.keys_teardown(ctx)
    assert not cleaned['qs_running_after_stop'] and not cleaned['fcitx5_running_after_stop'] and link['link_removed']
    (ctx.output / 'cleanup.json').write_text(json.dumps(dict(cleanup=cleaned, link=link), indent=2))
    ctx = None

def conflict(chord='Alt+Space'):
    rc, text = reg.ipc(ctx, 'c5Conflict', chord)
    assert rc == 0
    return text

def generated():
    if a.compositor == 'niri':
        path = config / 'atmosphera-input.kdl'
    elif a.compositor == 'mango':
        path = config / 'atmosphera-input.conf'
    else:
        root = Path(os.environ['HYPRLAND_CONFIG'])
        path = root.parent / ('atmosphera-input.lua' if root.suffix == '.lua' else 'atmosphera-input.conf')
    return path.read_text() if path.exists() else ''

def has_switch():
    return ('"toggleIM" "mozc"' if a.compositor == 'niri' else 'toggleIM mozc') in generated()

def refused(needle, chord='Alt+Space'):
    require(lambda: needle in conflict(chord) and not has_switch(), 'conflict not refused: ' + needle)
    require(lambda: needle in reg.journal(ctx), 'generator did not log diagnostic')
    return dict(diagnostic=conflict(chord), generated=generated())

def press(case, chord):
    # The settings change and native reload must reach the actual fcitx consumer.
    reg.gdbus(ctx, 'SwitchInputMethodGroup', reg.GROUP_RU)
    reg.gdbus(ctx, 'SetCurrentIM', 'keyboard-us')
    require(lambda: reg.truth_is(ctx, reg.GROUP_RU, 'keyboard-us'), 'could not establish consumer baseline')
    require(lambda: conflict(chord) == '' and has_switch(), 'free chord not generated')
    if a.compositor == 'hyprland':
        require(lambda: any(b['key'].lower() == 'space' and b['modmask'] == (8 if chord == 'Alt+Space' else 12)
                            for b in json.loads(reg.sh(['hyprctl', 'binds', '-j']).stdout)), 'generated bind not loaded')
    request = dict(step=case, combo=chord, hold_ms=80)
    (out / 'keys' / ('ready-' + case + '.json')).write_text(json.dumps(request))
    require(lambda: (out / 'keys' / ('sent-' + case + '.json')).exists(), 'key driver did not acknowledge', 100)
    require(lambda: reg.truth_is(ctx, reg.GROUP_JP, 'mozc'), 'real key did not change consumer IM', 15)
    require(lambda: reg.shell_matches(ctx, reg.GROUP_JP, 'mozc'), 'shell did not observe consumer IM')
    return dict(key=request, truth=reg.truth(ctx), generated=generated(), diagnostic=conflict(chord))

try:
    if a.compositor == 'mango':
        base = config / 'config.conf'
        original = base.read_text()
        assert base.read_bytes() == Path('/etc/mango/config.conf').read_bytes()
        start('mango')
        check('1', 'untouched default rofi conflict, public diagnostic and generator refusal', lambda: refused('rofi -show drun'))
        assert base.read_text() == original
        if a.capture:
            # Full real settings window. Capture stays outside evidence/ so a
            # plan evidence pull never puts screenshots inside the plans folder.
            r = reg.sh(['qs', '-p', str(ctx.shell_qml), 'ipc', 'call', 'settings', 'openTab', 'general/2'])
            assert r.returncode == 0, r
            time.sleep(3)
            # Navigate once content is instantiated as well (the existing
            # first-open panel route can settle to its default subtab).
            reg.sh(['qs', '-p', str(ctx.shell_qml), 'ipc', 'call', 'settings', 'openTab', 'general/2'])
            time.sleep(1)
            reg.sh(['grim', str(work / 'capture.png')])
            result['capture'] = str(work / 'capture.png')
            reg.sh(['qs', '-p', str(ctx.shell_qml), 'ipc', 'call', 'settings', 'toggle'])
            time.sleep(1)
        # Wire only the generated file, retaining the default rofi occupant.
        wired = original + '\n# C5 owned fixture\nsource=./atmosphera-input.conf\n'
        base.write_text(wired)
        reg.sh(['mmsg', 'dispatch', 'reload_config'])
        refused('rofi -show drun')
        settings_before = digest(ctx.profile_dir / 'config')
        def freed():
            base.write_text(wired.replace('bind=Alt,space,spawn,rofi -show drun', '#bind=Alt,space,spawn,rofi -show drun'))
            # No settings write, reload, IPC regenerate or shell restart here.
            observation = press('2', 'Alt+Space')
            observation['settings_unchanged'] = digest(ctx.profile_dir / 'config') == settings_before
            assert observation['settings_unchanged']
            return observation
        check('2', 'external-file-only removal regenerates and real Alt+Space switches IM', freed)
        sourced = config / 'c5r1-external.conf'
        sourced.write_text('bind=MOD1,SPACE,spawn,c5-sourced-action\n')
        base.write_text(base.read_text() + 'source=./c5r1-external.conf\n')
        check('3', 'sourced occupant has exact provenance', lambda: refused('c5r1-external.conf:1'))
        reg.write_im_section(ctx, [dict(reg.SWITCH_JA, keys=['Ctrl+Alt+Space'])])
        check('7-mango', 'free chord generated and dispatches to fcitx5', lambda: press('7-mango', 'Ctrl+Alt+Space'))
    elif a.compositor == 'niri':
        base = config / 'config.kdl'
        original = base.read_text()
        assert original.count('binds {\n') == 1
        base.write_text(original.replace('binds {\n', 'binds {\n    Alt+Space { spawn "c5-external-action"; }\n', 1))
        validation = reg.niri_validate(base)
        (out / 'fixture-validate.json').write_text(json.dumps(validation))
        assert validation[0] == 0, validation
        start('niri')
        check('4', 'niri user base conflict preserved', lambda: refused('c5-external-action'))
        reg.write_im_section(ctx, [dict(reg.SWITCH_JA, keys=['Ctrl+Alt+Space'])])
        check('7-niri', 'free chord generated and dispatches to fcitx5', lambda: press('7-niri', 'Ctrl+Alt+Space'))
    else:
        fixture = out / 'hypr'
        fixture.mkdir()
        for language in ('conf', 'lua'):
            root = fixture / ('hyprland.' + language)
            own_file = fixture / ('atmosphera-input.' + language)
            own_file.write_text('')
            own_source = (f'source={own_file}\n' if language == 'conf' else f'local f = loadfile({json.dumps(str(own_file))}); if f then f() end\n')
            occupant = ('bind=ALT,space,exec,rofi -show drun\n' if language == 'conf' else
                        'local chord = table.concat({"ALT", "space"}, " + ")\nhl.bind(chord, function() hl.exec_cmd("true") end, {description="Input method: forged external"})\n')
            root.write_text(own_source + occupant)
            start(language, root)
            number = '5a' if language == 'conf' else '5b'
            check(number, 'live user occupancy refused', lambda: refused('hyprland.conf:2' if language == 'conf' else 'a Lua function (source unavailable — live Hyprland binding)'))
            root.write_text(own_source)
            reg.sh(['hyprctl', 'reload'])
            require(lambda: conflict() == '' and 'toggleIM mozc' in generated(), 'own-only chord did not generate')
            time.sleep(4)  # observe multiple live-list refreshes after generated reload
            check('5c-' + language, 'only generated records are owned, without self-conflict',
                  lambda: dict(diagnostic=conflict(), generated=generated()) if conflict() == '' and 'toggleIM mozc' in generated() else (_ for _ in ()).throw(AssertionError('self-conflict')))
            if language == 'lua':
                root.write_text(own_source + occupant)
                reg.sh(['hyprctl', 'reload'])
                check('5d', 'surplus Lua record remains external despite forged description', lambda: refused('a Lua function'))
                root.write_text(own_source)
                reg.sh(['hyprctl', 'reload'])
            reg.write_im_section(ctx, [dict(reg.SWITCH_JA, keys=['Ctrl+Alt+Space'])])
            check('7-hypr-' + language, 'free chord reaches the real fcitx5 consumer', lambda: press('7-hypr-' + language, 'Ctrl+Alt+Space'))
            stop()
        reg.sh(['sudo', '-n', 'systemctl', 'stop', 'getty@tty1.service'])
        assert reg.sh(['pgrep', '-x', 'Hyprland']).returncode != 0
        p = reg.sh(['python3', '-B', source / 'Scripts/python/src/inputmethod/effective-binds.py', '--dialect', 'hypr', '--directory', fixture])
        stopped = json.loads(p.stdout)
        check('6', 'stopped Lua coverage is unknown, never free', lambda: stopped if 'Lua coverage unknown' in stopped['unknown'] else (_ for _ in ()).throw(AssertionError(stopped)))
    result['passed'] = True
except Exception as error:
    result['error'] = f'{type(error).__name__}: {error}'
    print(result['error'], flush=True)
finally:
    try:
        stop()
        for p in config.iterdir():
            if p.is_dir() and not p.is_symlink():
                shutil.rmtree(p)
            else:
                p.unlink()
        shutil.copytree(out / 'config-before', config, dirs_exist_ok=True, symlinks=True)
        if fcitx_before is None:
            fcitx.unlink(missing_ok=True)
        else:
            fcitx.write_bytes(fcitx_before)
        if selector_before is not None:
            result['restored_session'] = hypr.session(Path(selector_before.decode().strip()))
            selector.write_bytes(selector_before)
            assert not result['restored_session']['configerrors']
        elif a.compositor == 'mango':
            reg.sh(['mmsg', 'dispatch', 'reload_config'])
        for key in ('TMPDIR',):
            reg.sh(['systemctl', '--user', 'set-environment', f'{key}={manager[key]}'] if key in manager else ['systemctl', '--user', 'unset-environment', key])
        result.update(after=digest(config), restored=digest(config) == before)
    except Exception as error:
        result.update(restoration_error=f'{type(error).__name__}: {error}', restored=False)
    (out / 'keys/finished').write_text('done\n')
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2), flush=True)
raise SystemExit(0 if result['passed'] and result.get('restored') else 1)
