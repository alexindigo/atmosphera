#!/usr/bin/env python3
"""The shell's focused window is niri's, as real windows open, gain focus and close.

Runs on the assigned launcher VM console with the guest-only probe. Every step
compares niri's own focused window with each shell view that consumers read:
CompositorService.focusedWindowId, getFocusedWindow(), the focused title and
each window row's isFocused flag (exactly one row, the native one).
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import traceback

from launcher_workspace import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('keys', Path(__file__).with_name('launcher-key-owner-e2e.py'))
    keys = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(keys)
    flow = keys.flow
    flow.boundary()
    output = ROOT / 'evidence' / args.label
    output.mkdir()
    env = dict(os.environ, GDK_BACKEND='wayland', GTK_IM_MODULE='wayland')
    fixture = Path(__file__).parent / 'fixtures/launcher-paste-target.py'
    processes = {}
    logs = []
    cases = []

    def state(name):
        try:
            return json.loads((output / name / 'state.json').read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    def native():
        return {w['id']: w for w in flow.windows()}

    def by_title(title):
        return next(w for w in native().values() if w['title'] == title)

    def open_window(name):
        folder = output / name
        folder.mkdir()
        log = (folder / 'run.log').open('x')
        logs.append(log)
        processes[name] = subprocess.Popen(['timeout', '--kill-after=5', '180', 'python3', '-u', '-B', str(fixture), str(folder),
                                            'Focus ' + name], env=env, stdout=log, stderr=subprocess.STDOUT)
        flow.wait(lambda: state(name) and state(name)['active'], 10)
        return flow.wait(lambda: next((w for w in native().values() if w['title'] == 'Focus ' + name and w['is_focused']), None), 10)

    def close_window(name):
        window = by_title('Focus ' + name)
        flow.command(['niri', 'msg', 'action', 'close-window', '--id', str(window['id'])])
        processes.pop(name).wait(timeout=10)
        flow.wait(lambda: window['id'] not in native(), 10)

    def focus_window(name):
        window = by_title('Focus ' + name)
        flow.command(['niri', 'msg', 'action', 'focus-window', '--id', str(window['id'])])
        flow.wait(lambda: native()[window['id']]['is_focused'] and state(name)['active'], 10)

    def agreement():
        windows = native()
        focused = [w for w in windows.values() if w['is_focused']]
        assert len(focused) <= 1, focused
        expected = focused[0] if focused else None
        shell = json.loads(keys.ipc('focusIdentity'))
        flagged = [r['id'] for r in shell['rows'] if r['isFocused']]
        checks = dict(
            rows_match_native=sorted(r['id'] for r in shell['rows']) == sorted(windows),
            get_focused_window=(shell['focused'] or {}).get('id') == (expected['id'] if expected else None),
            title=shell['title'] == (expected['title'] if expected else ''),
            one_flagged_row=flagged == ([expected['id']] if expected else []))
        # Absent only on sources predating the id owner; such a run cannot pass.
        if shell['focusedWindowId'] != 'absent':
            checks['focused_window_id'] = shell['focusedWindowId'] == (expected['id'] if expected else None)
        return dict(native_focused=expected and dict(id=expected['id'], title=expected['title']),
                    shell=shell, checks=checks, agrees=all(checks.values()))

    def step(name, action):
        row = dict(name=name)
        try:
            action()
            latest = None
            def agrees():
                nonlocal latest
                latest = agreement()
                return latest['agrees']
            try:
                flow.wait(agrees, 5)
            except AssertionError:
                pass
            row.update(latest, passed=latest['agrees'])
        except Exception as error:
            row.update(passed=False, error=repr(error), traceback=traceback.format_exc())
        cases.append(row)
        (output / 'result.json').write_text(json.dumps(dict(complete=False, cases=cases), indent=2, ensure_ascii=False))
        print(name, 'PASS' if row['passed'] else 'FAIL', json.dumps(row.get('checks', row.get('error'))), flush=True)

    try:
        assert not flow.windows(), 'Preserve unexpected windows; run on an empty console desktop'
        keys.closed()
        step('initial-no-window', lambda: None)
        step('open-a', lambda: open_window('A'))
        step('open-b-while-a-focused', lambda: open_window('B'))
        step('open-c-while-b-focused', lambda: open_window('C'))
        step('focus-a', lambda: focus_window('A'))
        step('focus-already-focused-a', lambda: focus_window('A'))
        step('close-other-b', lambda: close_window('B'))
        step('focus-c', lambda: focus_window('C'))
        step('close-other-a', lambda: close_window('A'))
        step('open-d-while-c-focused', lambda: open_window('D'))
        step('close-focused-d', lambda: close_window('D'))
        step('close-last-c', lambda: close_window('C'))
    finally:
        for name in list(processes):
            (output / name / 'exit-request').write_text('exit')
        for process in processes.values():
            process.wait(timeout=10)
        for log in logs:
            log.close()
    owner = all('focused_window_id' in c.get('checks', {}) for c in cases)
    result = dict(passed=len(cases) == 12 and owner and all(c['passed'] for c in cases), complete=len(cases) == 12,
                  focused_window_id_published=owner, cases=cases)
    (output / 'result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
