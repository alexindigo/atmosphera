#!/usr/bin/env python3
"""Guest-only controls for fixture publication, observation and cleanup contracts."""
import argparse
import ast
import errno
import json
from pathlib import Path
import runpy
import sys
from types import SimpleNamespace
from unittest.mock import patch

import locker_sleep_support as sleep
import locker_test_support as support


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = support.require_guest(args.work, Path(__file__).resolve().parents[2])
    rows = []

    def check(name, function):
        try:
            function()
            row = dict(name=name, passed=True)
        except Exception as error:
            row = dict(name=name, passed=False, error=repr(error))
        rows.append(row)
        print(json.dumps(row), flush=True)

    def atomic_fixture(name, expected):
        case = work / name
        case.mkdir()
        (case / 'release').touch()
        (case / 'release-sleep-service').touch()
        writes = []
        original = Path.write_text
        def write(path, text, *args, **kwargs):
            writes.append(path.name)
            return original(path, text, *args, **kwargs)
        script = source / 'Scripts/dev/fixtures' / name
        argv = [str(script), '--work', str(case)]
        if 'memory' in name:
            argv += ['--mib', '1']
        with patch.object(sys, 'argv', argv), patch.object(Path, 'write_text', write):
            runpy.run_path(str(script), run_name='__main__')
        for filename in expected:
            assert json.loads((case / filename).read_text())
            assert filename not in writes, 'final readiness path written before complete publication'

    check('atomic-resident-report', lambda: atomic_fixture('locker-memory-pressure.py', ['resident.json']))
    check('atomic-sleep-reports', lambda: atomic_fixture('locker-sleep-service.py', ['sleep-service-entered.json', 'sleep-service-finished.json']))

    def partial_events():
        case = work / 'events'
        case.mkdir()
        harness = sleep.SleepHarness.__new__(sleep.SleepHarness)
        harness.work = case
        (case / 'inhibitor-events.jsonl').write_text('{"value":{"event":"acquired"}}\n{"value":')
        assert harness.events() == [{'value': {'event': 'acquired'}}]
    check('partial-event-tail', partial_events)

    def delayed_release():
        case = work / 'released'
        case.mkdir()
        harness = sleep.SleepHarness.__new__(sleep.SleepHarness)
        harness.work, harness.pid = case, 123
        (case / 'sleep-service-entered.json').write_text('{"monotonic":3}')
        event = {'pid': 123, 'value': {'event': 'released', 'secure': True, 'monotonic': 2}}
        calls = []
        harness.events = lambda: calls.append(1) or ([] if len(calls) == 1 else [event])
        harness.inhibitors = lambda pid: []
        harness.entered(1)
        assert len(calls) >= 2 and (case / 'inhibitor-ordering.json').exists()
    check('delayed-release-receipt', delayed_release)

    def cleanup(foreign=False):
        case = work / ('foreign-override' if foreign else 'owned-override')
        case.mkdir()
        harness = sleep.SleepHarness.__new__(sleep.SleepHarness)
        harness.work, harness.installed = case, True
        harness.override = case / 'override.conf'
        harness.content, harness.original = 'owned', 'original'
        harness.override.write_text('foreign' if foreign else harness.content)
        commands = []
        def run(command):
            commands.append(command)
            if command[:4] == ['sudo', '-n', 'rm', '--']:
                Path(command[-1]).unlink()
            return SimpleNamespace(stdout='original')
        with patch.object(sleep, 'run', run), patch.object(sleep, 'wait_for', side_effect=TimeoutError('delayed service')):
            try:
                harness.close()
            except TimeoutError:
                pass
            except AssertionError as error:
                assert foreign and str(error) == 'sleep fixture changed ownership'
        assert harness.override.exists() == foreign
        if not foreign:
            assert ['sudo', '-n', 'systemctl', 'daemon-reload'] in commands
    check('cleanup-after-wait-failure', cleanup)
    check('foreign-override-preserved', lambda: cleanup(True))

    def removed_cgroup(code):
        fake = SimpleNamespace(read_text=lambda: (_ for _ in ()).throw(OSError(code, 'removed')))
        with patch.object(Path, 'rglob', return_value=[fake]):
            try:
                result = support.cgroup_pids(work)
            except OSError as error:
                assert code == errno.EACCES and error.errno == code
            else:
                assert code != errno.EACCES and result == []
    for code in (errno.ENOENT, errno.ENODEV, errno.EACCES):
        check('cgroup-errno-' + str(code), lambda code=code: removed_cgroup(code))

    def delays(case, explicit=None):
        path = source / 'Scripts/dev/locker-lifecycle-regression.py'
        node = next(n for n in ast.parse(path.read_text()).body if isinstance(n, ast.FunctionDef) and n.name == 'main')
        statements = []
        for statement in node.body:
            if isinstance(statement, ast.If) and isinstance(statement.test, ast.Attribute) and statement.test.attr == 'real_suspend':
                break
            statements.append(statement)
        env = dict(argparse=argparse, Path=Path, __file__=str(path))
        argv = [str(path), '--case', case, '--work', str(work / 'unused')]
        if explicit:
            argv += ['--delays', explicit]
        with patch.object(sys, 'argv', argv):
            exec(compile(ast.Module(body=statements, type_ignores=[]), str(path), 'exec'), env)
        return env['args'].delays
    def defaults():
        assert delays('suspend') == '0,5,40'
        assert delays('boundary') == '2.9,3.0,3.1,29.9,30.0,30.1'
        assert delays('suspend', '5') == '5'
    check('case-specific-delay-defaults', defaults)
    (work / 'result.json').write_text(json.dumps(rows, indent=2))
    return 0 if all(row['passed'] for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
