#!/usr/bin/env python3
"""P169 green: pointer, keyboard and AT-SPI activation of Pomodoro toggles. VM only.

The actual Pomodoro page and Main run on the real niri session. A task-built
wlr virtual pointer clicks each switch, the task injector sends Tab and
Space/Return, and AT-SPI toggle actions activate the same controls. Each pass
must give identical field intents, native Apply, persisted values and Main
consumer state. The persisted file is read again independently here.
"""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
BAD = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
BEFORE = dict(autoStartBreaks=False, autoStartWork=False, compactMode=False, playSound=True, opaque=dict(keep=True))
# Three passes flip every value each time; the final pass leaves them flipped.
AFTER = dict(autoStartBreaks=True, autoStartWork=True, compactMode=True, playSound=False, opaque=dict(keep=True))


def build_pointer(source, build):
    build.mkdir()
    protocol = source / 'Scripts/dev/wlr-virtual-pointer-unstable-v1.xml'
    for mode, name in (('client-header', 'virtual-pointer-client.h'), ('private-code', 'virtual-pointer-protocol.c')):
        subprocess.run(['wayland-scanner', mode, str(protocol), str(build / name)], check=True)
    flags = subprocess.run(['pkg-config', '--cflags', '--libs', 'wayland-client'], check=True,
                           capture_output=True, text=True).stdout.split()
    subprocess.run(['cc', '-Wall', '-Werror', '-I', str(build), str(source / 'Scripts/dev/edge-scroll-test-pointer.c'),
                    str(build / 'virtual-pointer-protocol.c'), *flags, '-o', str(build / 'pointer')], check=True)
    return build / 'pointer'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--a11y-python', type=Path, default=Path('/usr/bin/python3'))
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    subprocess.run([str(args.a11y_python), '-c', 'import pyatspi'], check=True)
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    injector = Path(os.environ['PHA_INPUT_INJECTOR']).resolve()
    if not injector.is_relative_to(profile.work_base) or not injector.is_file():
        parser.error('task-owned input injector required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        case, out = args.work_root, args.output
        install = case / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        for part in ('config/settings/plugins', 'cache', 'state'):
            (case / part).mkdir(parents=True)
        shutil.copytree(args.plugins / 'pomodoro', case / 'config/plugins/pomodoro', ignore=shutil.ignore_patterns('*.bak'))
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        shared = case / 'config/settings/plugins/pomodoro.json'
        runner.write_json(shared, BEFORE)
        pointer = build_pointer(args.source, case / 'pointer-build')
        sockets = list(profile.session_runtime.glob('niri.' + profile.wayland_display + '.*.sock'))
        assert len(sockets) == 1, sockets
        outputs = json.loads(subprocess.run(['niri', 'msg', '--json', 'outputs'],
                            env=dict(os.environ, NIRI_SOCKET=str(sockets[0])), check=True,
                            capture_output=True, text=True).stdout)
        active = {key: value['logical'] for key, value in outputs.items() if value['logical'] is not None}
        screen = sorted(active)[0]
        geometry = active[screen]
        assert min(v['x'] for v in active.values()) == 0 and min(v['y'] for v in active.values()) == 0
        layout = dict(x=geometry['x'], y=geometry['y'],
                      width=max(v['x'] + v['width'] for v in active.values()),
                      height=max(v['y'] + v['height'] for v in active.values()))
        runner.write_json(out / 'pointer-layout.json', dict(outputs=outputs, screen=screen, layout=layout))
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-pomodoro-input.qml'
        inputs = {}
        for label, path in (
            ('NToggle.qml', install / 'Widgets/NToggle.qml'),
            ('NPluginSettingsPopup.qml', install / 'Widgets/NPluginSettingsPopup.qml'),
            ('PluginSettingsSession.qml', install / 'Services/Plugins/PluginSettingsSession.qml'),
            ('PluginSettingsPageApi.qml', install / 'Services/Plugins/PluginSettingsPageApi.qml'),
            ('pomodoro/Settings.qml', case / 'config/plugins/pomodoro/Settings.qml'),
            ('pomodoro/Main.qml', case / 'config/plugins/pomodoro/Main.qml'),
            ('pomodoro/manifest.json', case / 'config/plugins/pomodoro/manifest.json'),
            ('inputFixture', fixture),
            ('accessibilityProbe', args.source / 'Scripts/dev/fixtures/plugin-settings-pomodoro-a11y.py'),
            ('pointerSource', args.source / 'Scripts/dev/edge-scroll-test-pointer.c'),
            ('pointerProtocol', args.source / 'Scripts/dev/wlr-virtual-pointer-unstable-v1.xml'),
            ('driver', Path(__file__)),
        ):
            inputs[label] = hashlib.sha256(path.read_bytes()).hexdigest()
        env = dict(QT_LINUX_ACCESSIBILITY_ALWAYS_ON='1', QT_FORCE_STDERR_LOGGING='1', PHA_POINTER=str(pointer),
                   PHA_P169_SCREEN=screen, PHA_P169_LAYOUT=json.dumps(layout), PHA_A11Y_PYTHON=str(args.a11y_python),
                   PHA_A11Y_PROBE=str(args.source / 'Scripts/dev/fixtures/plugin-settings-pomodoro-a11y.py'),
                   PHA_A11Y_RESULT=str(out / 'a11y.json'))
        lint = [case / 'config/plugins/pomodoro/Settings.qml', install / 'Widgets/NToggle.qml']
        error = None
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env, extra_lint=lint, timeout=150)
        except RuntimeError as failure:
            error = str(failure)
            text = (out / 'runtime.log').read_text()
        stored = json.loads(shared.read_text())
        a11y = json.loads((out / 'a11y.json').read_text()) if (out / 'a11y.json').exists() else []
        checks = dict(
            fixture=error is None and 'P169_INPUT: PASS' in text,
            pointerIntents=text.count('P169_POINTER_INTENT: ') == 4,
            keyboardIntents=text.count('P169_KEYBOARD_INTENT: ') == 4,
            accessibilityIntents=text.count('P169_ACCESSIBILITY_INTENT: ') == 4,
            appliedPasses=text.count('P169_PASS_APPLIED: ') == 3,
            accessibleToggleActions=len(a11y) == 1 and len(a11y[0]['controls']) == 4 and
            all(control['invoked'] == 'Toggle' for control in a11y[0]['controls']),
            independentReadback=stored == AFTER,
            runtimeClean=not any(marker in text for marker in BAD))
        result = dict(id='P169', status='PASS' if all(checks.values()) else 'FAIL', checks=checks, fixtureError=error,
                      stored=stored, accessibility=a11y, inputs=inputs,
                      pointer=dict(path=str(pointer), sha256=hashlib.sha256(pointer.read_bytes()).hexdigest()),
                      injector=dict(path=str(injector), sha256=hashlib.sha256(injector.read_bytes()).hexdigest()),
                      witness='real niri pointer/keyboard input and AT-SPI actions on the actual Pomodoro page and Main')
        runner.write_json(out / 'result.json', result)
        print('CASE P169-input: %s %s' % (result['status'], json.dumps(checks)), flush=True)
        if result['status'] != 'PASS':
            raise SystemExit(1)
        runner.remove_completed_installs(case, out)


if __name__ == '__main__':
    main()
