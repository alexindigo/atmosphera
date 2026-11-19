#!/usr/bin/env python3
"""Actual helper entry/callback controls; synthetic bus, no suspend or PAM."""
import argparse
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from locker_test_support import require_guest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    spec = importlib.util.spec_from_file_location('inhibitor', source / 'Scripts/python/locker-sleep-inhibitor.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    results = []
    for scenario in ('resume-refusal', 'startup-in-progress', 'startup-progress-ended', 'startup-other-error'):
        output = io.StringIO()
        callbacks = {}
        acquired = []
        calls = []
        quits = []
        reads = []
        in_progress = 'org.freedesktop.login1.OperationInProgress'
        class Manager:
            def Inhibit(self, *args):
                calls.append(args)
                failure = (scenario == 'resume-refusal' and len(calls) == 2) or (
                    scenario.startswith('startup-') and len(calls) == 1)
                if failure:
                    name = 'org.freedesktop.DBus.Error.AccessDenied' if scenario == 'startup-other-error' else in_progress
                    raise helper.dbus.DBusException('controlled Inhibit refusal', name=name)
                fd = os.open(work / ('fd-' + scenario + '-' + str(len(calls))), os.O_RDWR | os.O_CREAT, 0o600)
                acquired.append(fd)
                return SimpleNamespace(take=lambda: fd)
        class Properties:
            def Get(self, iface, prop):
                reads.append(prop)
                return 5_000_000 if prop == 'InhibitDelayMaxUSec' else scenario == 'startup-in-progress'
        manager, properties = Manager(), Properties()
        bus = SimpleNamespace(get_object=lambda *args: object(),
            add_signal_receiver=lambda callback, **kwargs: callbacks.update(prepare=callback))
        class Loop:
            def quit(self):
                quits.append(True)
            def run(self):
                if scenario == 'resume-refusal':
                    callbacks['prepare'](True)
                    window = json.loads(output.getvalue().splitlines()[-1])['window']
                    input_file.write((json.dumps(dict(window=window, secure=True)) + '\n').encode())
                    input_file.flush()
                    input_file.seek(0)
                    callbacks['receive'](input_file, helper.GLib.IO_IN)
                    callbacks['prepare'](False)
                    assert quits, 'failed reacquisition left helper alive without an fd'
                elif scenario == 'startup-in-progress':
                    events = [json.loads(line) for line in output.getvalue().splitlines()]
                    assert any(e['event'] == 'prepare' and e['sleeping'] and e['window'] for e in events), events
                    assert not acquired, 'startup claimed an fd that logind refused'
                    callbacks['prepare'](False)
                    assert len(acquired) == 1, 'resume did not acquire the first real fd'
                elif scenario == 'startup-progress-ended':
                    assert len(acquired) == 1 and len(calls) == 2, (acquired, calls)
        error = None
        with (work / ('input-' + scenario)).open('w+b') as input_file, redirect_stdout(output), \
                patch.object(helper.dbus, 'SystemBus', return_value=bus), \
                patch.object(helper.dbus, 'Interface', side_effect=lambda obj, iface: manager if iface.endswith('.Manager') else properties), \
                patch.object(helper.GLib, 'MainLoop', Loop), \
                patch.object(helper.GLib, 'io_add_watch', side_effect=lambda fd, cond, cb: callbacks.update(receive=cb)), \
                patch.object(helper.GLib, 'timeout_add'), patch.object(helper.sys, 'stdin', input_file):
            try:
                helper.main()
            except Exception as caught:
                error = caught
        events = [json.loads(line) for line in output.getvalue().splitlines()]
        closed = True
        for fd in acquired:
            try:
                os.fstat(fd)
            except OSError:
                pass
            else:
                closed = False
                os.close(fd)
        passed = closed and (isinstance(error, helper.dbus.DBusException) if scenario == 'startup-other-error' else error is None)
        if scenario == 'startup-in-progress':
            passed = passed and 'PreparingForSleep' in reads
        row = dict(scenario=scenario, passed=passed, calls=len(calls), fds=len(acquired), closed=closed,
            quits=len(quits), reads=reads, events=events, error=str(error) if error else None)
        results.append(row)
        print(json.dumps(row), flush=True)
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
