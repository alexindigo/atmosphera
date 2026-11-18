#!/usr/bin/env python3
"""Guest-only controls of actual observer ingestion, not native lock evidence."""
import argparse
import ast
import json
import os
from pathlib import Path
import time

from locker_test_support import require_guest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    source, work = require_guest(args.work, args.source)
    observer = source / 'Scripts/dev/locker-compositor-observer.py'
    tree = ast.parse(observer.read_text())
    # Execute the actual closure's ingestion function, with captured output and
    # synthetic journal records. Do not copy its normalization into the test.
    consume = next(node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef) and node.name == 'consume_journal')
    helpers = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'compositor_journal_event']
    code = compile(ast.Module(body=[*helpers, consume], type_ignores=[]), str(observer), 'exec')
    start = Path(f'/proc/{os.getpid()}/stat').read_text().split(') ', 1)[1].split()[19]
    identity = dict(pid=os.getpid(), start=start, uid=os.getuid(), source='journal', since=0)
    record = dict(_COMM='niri', _PID=str(os.getpid()), _UID=str(os.getuid()),
        __MONOTONIC_TIMESTAMP=str(int(time.monotonic() * 1_000_000)), MESSAGE='unlocking session')
    results = []
    cases = ('journal-exact', 'foreign-pid', 'foreign-uid', 'stale-start', 'before-source', 'file-source')
    for scenario in cases:
        events = []
        selected, message = dict(identity), dict(record)
        if scenario == 'foreign-pid':
            message['_PID'] = '0'
        elif scenario == 'foreign-uid':
            message['_UID'] = str(os.getuid() + 1)
        elif scenario == 'stale-start':
            selected['start'] = '0'
        elif scenario == 'before-source':
            selected['since'] = time.monotonic() + 60
        elif scenario == 'file-source':
            selected['source'] = 'file'
        env = dict(json=json, os=os, Path=Path, pending=bytearray(), compositor_identity=selected,
            emit=lambda kind, **values: events.append(dict(kind=kind, **values)))
        exec(code, env)
        error = None
        try:
            raw = (json.dumps(message) + '\n').encode()
            # The same journal line can arrive across pipe-read boundaries.
            env['consume_journal'](raw[:17])
            env['consume_journal'](raw[17:])
        except AssertionError as failure:
            error = str(failure)
        compositor = [event for event in events if event['kind'] == 'compositor-log']
        if scenario == 'journal-exact':
            passed = error is None and len(compositor) == 1 and compositor[0].get('pid') == identity['pid'] and compositor[0].get('start') == start
        elif scenario == 'stale-start':
            passed = bool(error) and not compositor
        else:
            passed = error is None and not compositor
        row = dict(scenario=scenario, passed=passed, events=events, error=error)
        results.append(row)
        print(json.dumps(row), flush=True)
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
