#!/usr/bin/env python3
"""Real logind fd acquisition/EOF cleanup, not a suspend-ordering proof."""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import time

from locker_test_support import require_guest, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    import dbus
    bus = dbus.SystemBus()
    proxy = bus.get_object('org.freedesktop.login1', '/org/freedesktop/login1')
    manager = dbus.Interface(proxy, 'org.freedesktop.login1.Manager')
    properties = dbus.Interface(proxy, 'org.freedesktop.DBus.Properties')
    assert not bool(properties.Get('org.freedesktop.login1.Manager', 'PreparingForSleep')), 'unexpected sleep in progress'
    with (work / 'stderr.txt').open('w') as errors:
        child = subprocess.Popen(['python3', '-B', str(source / 'Scripts/python/locker-sleep-inhibitor.py')],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors, text=True)
        try:
            readable, _, _ = select.select([child.stdout], [], [], 10)
            assert readable, 'inhibitor did not report acquisition'
            acquired = json.loads(child.stdout.readline())
            assert acquired['event'] == 'acquired', acquired
            assert acquired['maxDelay'] == int(properties.Get('org.freedesktop.login1.Manager', 'InhibitDelayMaxUSec')) / 1_000_000
            def owned():
                return [list(row) for row in manager.ListInhibitors() if int(row[5]) == child.pid]
            active = wait_for(owned)
            assert len(active) == 1 and active[0][0] == 'sleep' and active[0][3] == 'delay'
            assert int(active[0][4]) == os.getuid()
            (work / 'active.json').write_text(json.dumps({'pid': child.pid, 'acquired': acquired, 'inhibitors': active}, indent=2))
            output, _ = child.communicate(json.dumps({'secure': False, 'opaque': True}) + '\n', timeout=10)
            assert child.returncode == 0, (work / 'stderr.txt').read_text()
            events = [json.loads(line) for line in output.splitlines()]
            assert any(event['event'] == 'released' and not event['secure'] for event in events), events
            wait_for(lambda: not owned())
            (work / 'events.json').write_text(json.dumps(events, indent=2))
            assert not bool(properties.Get('org.freedesktop.login1.Manager', 'PreparingForSleep'))
            (work / 'result.txt').write_text('PASS inhibitor-fd\n')
            print('PASS inhibitor-fd', work)
        finally:
            if child.poll() is None:
                child.stdin.close()
                child.wait(timeout=10)


if __name__ == '__main__':
    main()
