#!/usr/bin/env python3
"""A key-owner consumer leaves no probe state behind, passing or failing.

Each case runs a consumer inside probe_session() that arms the activation
spy, attaches the focus challenger with competing shortcuts, hides the core,
registers the fixture provider and records keys. One consumer exits normally,
one by an injected failure. After each, outside any consumer scope, the probe
must report its baseline, the launcher settings must be restored, and a real
Enter in the launcher must start the application (not the spy).
Needs the launcher-flow fixtures (launcher-flow-e2e.py --prepare).
"""
import argparse
import importlib.util
import json
from pathlib import Path
import traceback

from launcher_workspace import ROOT


class InjectedFailure(RuntimeError):
    pass


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
    settings_before = json.loads(keys._call('getLauncherSettings'))
    cases = []

    def consumer(fail):
        with keys.probe_session():
            keys.opened('panel', 'apps-list')
            keys.ipc('observe', 'true')
            keys.ipc('armActivation')
            keys.type_text('Launcher Flow Alpha')
            keys.expect(lambda s: s['query'] == 'Launcher Flow Alpha')
            keys.ipc('hide', 'true')
            armed = json.loads(keys._call('probeState'))
            assert armed['activationArmed'] and armed['challenger'] and armed['hidden'] and armed['fixtureProvider'], armed
            if fail:
                raise InjectedFailure('injected consumer failure')
            keys.ipc('hide', 'false')
            return armed

    def real_activation():
        """Enter on the filtered app outside any consumer scope opens its window."""
        assert not flow.snapshot()['open']
        before = {w['id'] for w in flow.windows()}
        flow.keys(*flow.SHORTCUT)
        flow.wait(lambda: flow.snapshot()['open'] and flow.snapshot()['results'])
        flow.command(['ydotool', 'type', '--key-delay', '2', '--', 'Launcher Flow Alpha'])
        flow.wait(lambda: flow.snapshot()['query'] == 'Launcher Flow Alpha')
        assert flow.snapshot()['results'][0]['id'] == flow.APP, flow.snapshot()
        flow.press(28)
        window = flow.wait(lambda: next((w for w in flow.windows() if w['app_id'] == flow.APP and w['id'] not in before), None))
        flow.wait(lambda: not flow.snapshot()['open'])
        flow.command(['niri', 'msg', 'action', 'close-window', '--id', str(window['id'])])
        flow.wait(lambda: all(w['id'] != window['id'] for w in flow.windows()))
        return window

    for name, fail in (('passing-consumer-leaves-baseline', False), ('failing-consumer-leaves-baseline', True)):
        row = dict(name=name)
        try:
            try:
                row['armed_inside'] = consumer(fail)
                assert not fail, 'the injected failure did not propagate'
            except InjectedFailure:
                assert fail
                row['injected'] = True
            row['probe_after'] = json.loads(keys._call('probeState'))
            assert row['probe_after'] == keys.PROBE_BASELINE, row['probe_after']
            row['settings_after'] = json.loads(keys._call('getLauncherSettings'))
            assert row['settings_after'] == settings_before, row['settings_after']
            row['window'] = real_activation()
            row['passed'] = True
        except Exception as error:
            row.update(passed=False, error=repr(error), traceback=traceback.format_exc())
        cases.append(row)
        print(name, 'PASS' if row['passed'] else 'FAIL', row.get('error', ''), flush=True)
        (output / 'result.json').write_text(json.dumps(dict(complete=False, cases=cases), indent=2))
    result = dict(passed=all(c['passed'] for c in cases), complete=len(cases) == 2, cases=cases)
    (output / 'result.json').write_text(json.dumps(result, indent=2))
    return 0 if result['passed'] and result['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
