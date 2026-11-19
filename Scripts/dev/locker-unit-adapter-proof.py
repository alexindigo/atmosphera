#!/usr/bin/env python3
"""Exact-unit/cgroup adapter proof; not the complete owner-state test matrix."""
import argparse
import json
import os
from pathlib import Path
import shlex
import sys
import time

from locker_test_support import manage, require_guest, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    sid = manage(source, {'operation': 'discover'})['session']
    results = []
    previous = None
    for name, flags in (('daemonized', ['--daemonize']), ('term-resistant', ['--daemonize', '--resist-term']), ('failed-exec', None), ('unready-deadline', [])):
        case = work / name
        case.mkdir()
        operation = manage(source, {'operation': 'begin', 'session': sid,
                                    'snapshot': {'adapter': 'bundled' if name == 'unready-deadline' else 'opaque'}})
        generation = operation['generation']
        base = {'session': sid, 'generation': generation}
        missing = manage(source, {'operation': 'phase', 'session': sid, 'phase': 'engaged'}, check=False)
        assert not missing['ok'], 'mutation accepted without a generation'
        if previous is not None:
            stale = manage(source, dict(base, operation='phase', generation=previous, phase='engaged'), check=False)
            assert not stale['ok'] and stale['error'] == 'stale locker generation', stale
        try:
            command = 'exec /this-locker-fixture-does-not-exist' if flags is None else shlex.join([
                sys.executable, str(source / 'Scripts/dev/fixtures/locker-unit-workload.py'), '--work', str(case), *flags])
            launched = manage(source, dict(base, operation='launch', role='real', command=command))
            (case / 'launch.json').write_text(json.dumps(launched, indent=2))
            saved_group = launched['identity']['ControlGroup']
            assert saved_group.endswith('/atmosphera-lockscreen-' + sid + '.service'), saved_group
            assert '/session.slice/' in saved_group
            if flags is not None:
                wait_for(lambda: (case / 'child.json').exists())
                status = manage(source, dict(base, operation='inspect'))
                assert status['units']['real']['sameInvocation'], status
                assert len(status['units']['real']['members']) >= 3, status
                marker = case / 'duplicate-launched'
                repeated = manage(source, dict(base, operation='launch', role='real', command='touch ' + shlex.quote(str(marker))))
                assert repeated['identity']['InvocationID'] == launched['identity']['InvocationID']
                assert not marker.exists(), 'duplicate request launched another workload'
            if name == 'unready-deadline':
                wait_for(lambda: manage(source, dict(base, operation='inspect'))['units']['real']['gone'], timeout=34)
                elapsed = time.monotonic() - operation['requestedAt']
                assert 29.9 <= elapsed <= 33, elapsed
            elif flags is None:
                wait_for(lambda: manage(source, dict(base, operation='inspect'))['units']['real']['gone'])
            else:
                before = time.monotonic()
                stopped = manage(source, dict(base, operation='stop', role='real'))
                assert stopped['gone'] and not stopped['members'], stopped
                if name == 'term-resistant':
                    assert time.monotonic() - before >= 1.8, 'fixture did not exercise stop escalation'
            final = manage(source, dict(base, operation='inspect'))
            assert final['units']['real']['gone'], final
            assert not final['units']['real']['members'], final
            assert not (Path('/sys/fs/cgroup') / saved_group.lstrip('/')).exists(), saved_group
            for pid_file in case.glob('*.json'):
                if pid_file.name == 'launch.json':
                    continue
                saved = json.loads(pid_file.read_text())
                path = Path('/proc') / str(saved['pid']) / 'stat'
                if path.exists():
                    current = path.read_text().rsplit(')', 1)[1].split()
                    assert current[19] != saved['start'] or current[0] == 'Z', saved
            (case / 'final.json').write_text(json.dumps(final, indent=2))
            manage(source, dict(base, operation='settle'))
            results.append({'case': name, 'pass': True})
            previous = generation
        finally:
            # These fixtures never acquire a session lock. Stop only their
            # recorded exact invocation, including TERM-resistant descendants.
            status = manage(source, dict(base, operation='inspect'))
            if 'real' in status['units'] and not status['units']['real']['gone']:
                manage(source, dict(base, operation='stop', role='real'))
            manage(source, dict(base, operation='settle'))
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    print('PASS unit-adapter', work)


if __name__ == '__main__':
    main()
