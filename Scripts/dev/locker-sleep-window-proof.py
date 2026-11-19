#!/usr/bin/env python3
"""Guest-only controls of actual inhibitor closures, not native sleep evidence."""
import argparse
import ast
import json
import os
from pathlib import Path
import secrets
from types import SimpleNamespace

from locker_test_support import require_guest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    path = source / 'Scripts/python/locker-sleep-inhibitor.py'
    main_node = next(node for node in ast.parse(path.read_text()).body
                     if isinstance(node, ast.FunctionDef) and node.name == 'main')
    nodes = [node for node in main_node.body if isinstance(node, ast.FunctionDef)
             and node.name in ('release', 'acquire', 'prepare', 'check_window', 'receive')]
    state_node = next(node for node in main_node.body if isinstance(node, ast.Assign)
                      and any(isinstance(target, ast.Name) and target.id == 'state' for target in node.targets))
    code = compile(ast.Module(body=[state_node, *nodes], type_ignores=[]), str(path), 'exec')
    events, descriptors = [], []
    reader, writer = os.pipe()
    clock = [100.0]
    def inhibit(*unused):
        fd = os.open('/dev/null', os.O_RDONLY)
        descriptors.append(fd)
        return SimpleNamespace(take=lambda: fd)
    env = dict(os=os, json=json, secrets=secrets,
        time=SimpleNamespace(monotonic=lambda: clock[0]), max_delay=5,
        sys=SimpleNamespace(stdin=SimpleNamespace(fileno=lambda: reader)),
        GLib=SimpleNamespace(IO_IN=1), loop=SimpleNamespace(quit=lambda: None),
        manager=SimpleNamespace(Inhibit=inhibit),
        emit=lambda event, **values: events.append(dict(event=event, **values)))
    exec(code, env)
    env['receive'].buffer = b''
    def receive(value):
        os.write(writer, (json.dumps(value) + '\n').encode())
        env['receive'](None, 1)
    def releases():
        return len([row for row in events if row['event'] == 'released'])
    results = []
    def record(scenario, passed):
        row = dict(scenario=scenario, passed=passed)
        results.append(row)
        print(json.dumps(row), flush=True)
    try:
        env['acquire']()
        receive(dict(secure=True))
        env['prepare'](True)
        first = next(row for row in reversed(events) if row['event'] == 'prepare').get('window')
        record('cached-before-window', bool(first) and releases() == 0)
        receive(dict(window='foreign', secure=True))
        record('foreign-window', releases() == 0)
        receive(dict(window=first, secure=False))
        record('negative-current-window', releases() == 0)
        for label, raw in (('malformed-json', b'{bad}\n'), ('non-object-json', b'1\n')):
            os.write(writer, raw)
            try:
                watching = env['receive'](None, 1)
            except (ValueError, AttributeError):
                watching = False
            record(label + '-retains-watch', watching is True and releases() == 0)
        receive(dict(window=first, secure=True))
        record('confirmed-current-window', releases() == 1)
        env['prepare'](False)
        env['prepare'](True)
        second = next(row for row in reversed(events) if row['event'] == 'prepare').get('window')
        record('new-window-withdraws-confirmation', bool(second) and second != first and releases() == 1)
        receive(dict(window=first, secure=True))
        record('previous-window-receipt', releases() == 1)
        env['prepare'](True)
        record('duplicate-prepare', next(row for row in reversed(events) if row['event'] == 'prepare').get('window') == second)
        clock[0] += 5
        env['check_window']()
        record('configured-expiry', releases() == 2 and any(row['event'] == 'unconfirmed' for row in events))
    finally:
        env['release']()
        os.close(reader)
        os.close(writer)
    (work / 'result.json').write_text(json.dumps(dict(results=results, events=events), indent=2))
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
