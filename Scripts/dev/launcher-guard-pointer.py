#!/usr/bin/env python3
"""Real pointer/wheel events against inactive guarded native controls."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from launcher_workspace import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('flow', Path(__file__).with_name('launcher-flow-e2e.py'))
    flow = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(flow)
    flow.boundary()
    output, runtime = ROOT / 'evidence' / args.label, ROOT / 'runtime' / args.label
    output.mkdir()
    tree = runtime / 'tree'
    shutil.copytree(args.source, tree, symlinks=True)
    (tree / 'shell.qml').write_text((args.source / 'Scripts/dev/fixtures/launcher-guard-pointer.qml').read_text())
    shell = tree / 'shell.qml'
    env = dict(os.environ)
    profile = runtime / 'profile'
    for name in ('home', 'config/atmosphera', 'cache/atmosphera', 'state/atmosphera', 'data'):
        (profile / name).mkdir(parents=True, exist_ok=True)
    settings = json.loads((args.source / 'Configs/defaults.json').read_text())
    settings['settingsVersion'] = 62
    settings['general']['animationDisabled'] = True
    (profile / 'config/atmosphera/settings.json').write_text(json.dumps(settings))
    env.update(HOME=str(profile / 'home'), XDG_CONFIG_HOME=str(profile / 'config'),
               XDG_CACHE_HOME=str(profile / 'cache'), XDG_STATE_HOME=str(profile / 'state'),
               XDG_DATA_HOME=str(profile / 'data'), ATMOSPHERA_CONFIG_DIR=str(profile / 'config/atmosphera'),
               ATMOSPHERA_CACHE_DIR=str(profile / 'cache/atmosphera'),
               ATMOSPHERA_STATE_DIR=str(profile / 'state/atmosphera'),
               ATMOSPHERA_SETTINGS_FILE=str(profile / 'config/atmosphera/settings.json'))
    env.pop('QT_IM_MODULE', None)
    env.pop('GTK_IM_MODULE', None)
    cases = []
    def ipc(member, *values, check=True):
        return flow.command(['qs', '-p', shell, 'ipc', 'call', 'guardPointer', member, *values], check=check)
    def state():
        return json.loads(ipc('state').stdout)
    def check(name, passed, observed):
        cases.append(dict(name=name, passed=bool(passed), observed=observed))
        (output / 'result.json').write_text(json.dumps(dict(complete=False, cases=cases), indent=2))
    def move(point):
        flow.command(['ydotool', 'mousemove', '--absolute', '-x', str(round(point['x'])), '-y', str(round(point['y']))])
    def click(point):
        move(point)
        flow.command(['ydotool', 'click', '0xC0'])
    with (output / 'run.log').open('x') as log:
        process = subprocess.Popen(['timeout', '--kill-after=5', '120', 'qs', '-p', str(shell), '--no-color'],
                                   cwd=tree, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            flow.wait(lambda: ipc('state', check=False).stdout.strip(), 20)
            flow.wait(lambda: state()['active'])
            baseline = state()
            ipc('deactivate', 'true')
            flow.wait(lambda: not state()['active'])
            inactive = state()
            check('inactive-preserves-public-enabled', all(inactive[k] for k in
                  ('surfaceEnabled', 'comboEnabled', 'spinEditorEnabled', 'gridEnabled', 'buttonEnabled')), inactive)
            check('inactive-preserves-opacity', inactive['comboOpacity'] == baseline['comboOpacity'] == 1, inactive)
            move(inactive['grid'])
            flow.command(['ydotool', 'mousemove', '--wheel', '--', '0', '-3'])
            time.sleep(.5)
            scrolled = state()
            check('inactive-real-wheel', scrolled['contentY'] > baseline['contentY'] and not scrolled['active'], scrolled)
            click(scrolled['button'])
            time.sleep(.1)
            pressed = state()
            check('inactive-first-real-click', pressed['clicks'] == 1, pressed)
            click(pressed['spinPlus'])
            time.sleep(.1)
            spun = state()
            check('inactive-spin-pointer', spun['spin'] == 6, spun)
            click(spun['combo'])
            try:
                flow.wait(lambda: state()['popupVisible'] and state()['second'], 2)
                click(state()['second'])
                flow.wait(lambda: state()['selection'] == 'b', 2)
            except AssertionError:
                pass
            selected = state()
            check('inactive-combo-pointer', selected['selection'] == 'b', selected)
            ipc('caller', 'false')
            check('caller-binding-disabled-inactive', not state()['callerEnabled'], state())
            ipc('deactivate', 'false')
            flow.wait(lambda: state()['active'])
            check('caller-disabled-after-reactivation', not state()['callerEnabled'], state())
            ipc('caller', 'true')
            check('caller-binding-recovered', state()['callerEnabled'], state())
        finally:
            ipc('exitControl', check=False)
            process.wait(timeout=10)
    result = dict(passed=all(r['passed'] for r in cases), complete=True, exit=process.returncode, cases=cases)
    (output / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(dict(passed=result['passed'], checks=len(cases), failures=[r['name'] for r in cases if not r['passed']]), indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
