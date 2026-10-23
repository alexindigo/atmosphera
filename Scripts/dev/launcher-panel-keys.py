#!/usr/bin/env python3
"""Console regressions: an open dialog owns keys, a hidden one cannot steal them.

Run once per source version through the launcher's pinned tools/guest route.
Only observations and opening a test dialog use IPC; all tested keys are uinput.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import time

ROOT = Path('/home/tester/Projects/atmosphera-launcher')
spec = importlib.util.spec_from_file_location('flow', ROOT / 'tools/launcher-flow-e2e.py')
flow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flow)


def main():
    flow.boundary()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    out = ROOT / 'evidence' / args.label
    assert not out.exists()
    out.mkdir()
    assert not flow.snapshot()['open']
    cases = []

    def check(name, action):
        try:
            actual = action()
            cases.append(dict(name=name, passed=True, observed=actual))
        except (AssertionError, TimeoutError) as error:
            cases.append(dict(name=name, passed=False, error=str(error)))
        (out / 'cases.json').write_text(json.dumps(cases, indent=2))

    def dialog(key, name, expected):
        reply = out / (name + '.reply')
        flow.command(['qs', '-c', 'atmosphera', 'ipc', 'call', 'dialog', 'confirm', 'Launcher keyboard regression', reply])
        time.sleep(.2)
        flow.press(key)
        flow.wait(reply.exists)
        actual = reply.read_text()
        assert actual == expected, actual
        return actual

    def hidden_return():
        flow.keys(*flow.SHORTCUT)
        flow.wait(lambda: flow.snapshot()['open'])
        flow.command(['ydotool', 'type', '--key-delay', '2', '--', '>'])
        flow.wait(lambda: flow.snapshot()['query'] == '>')
        before = flow.snapshot()
        expected = before['results'][0]['name'] + ' '
        flow.press(28)
        flow.wait(lambda: flow.snapshot()['query'] == expected)
        return flow.snapshot()

    def hidden_escape():
        flow.press(1)
        flow.wait(lambda: not flow.snapshot()['open'])
        return flow.snapshot()

    try:
        check('open-dialog-return', lambda: dialog(28, 'return', 'true'))
        check('open-dialog-escape', lambda: dialog(1, 'escape', ''))
        check('hidden-dialog-return-reaches-launcher', hidden_return)
        check('hidden-dialog-escape-reaches-launcher', hidden_escape)
    finally:
        if flow.snapshot()['open']:
            if flow.snapshot()['query'].startswith('>'):
                flow.keys(*flow.SHORTCUT)
                flow.wait(lambda: flow.snapshot()['query'] == '')
            flow.keys(*flow.SHORTCUT)
            flow.wait(lambda: not flow.snapshot()['open'])
        result = dict(passed=all(c['passed'] for c in cases), cases=cases, cleanup=flow.snapshot())
        (out / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
