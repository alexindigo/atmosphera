#!/usr/bin/env python3
"""Guest adapter transaction controls plus real systemd command-byte transport.

Synthetic records are not native lock or PAM evidence and never acquire a lock.
"""
import argparse
from contextlib import contextmanager
import copy
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
from types import SimpleNamespace
from unittest.mock import patch

from locker_test_support import manage, require_guest, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    source, work = require_guest(args.work, args.source)
    spec = importlib.util.spec_from_file_location('admission_adapter', source / 'Scripts/python/locker-unit.py')
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    results = []

    def case(name, check):
        try:
            check()
        except Exception as error:
            results.append(dict(case=name, passed=False, error=repr(error)))
        else:
            results.append(dict(case=name, passed=True))
        print(json.dumps(results[-1]), flush=True)

    state = None
    class Session:
        def __init__(self, session):
            self.session = session
        @contextmanager
        def locked(self, generation=None):
            yield state
        def write(self, value):
            pass
        def name(self, role):
            return 'fixture-' + role

    def fresh():
        return dict(session='fixture', generation='g', phase='starting', deadline=10**20,
            snapshot={'adapter': 'bundled'}, authRole=None, handoverCommitted=False, units={})

    def record(role):
        identity = adapter.proc_identity(os.getpid())
        return dict(name='fixture-' + role, identity={'InvocationID': role, 'ControlGroup': '/fixture/' + role},
            clientIdentity=identity, client={'ready': True, 'secure': True, 'terminal': False},
            protocolReport={'sequence': 1, 'event': 'locked', 'everSecure': True}, grant=True, retire=False)

    live = dict(sameInvocation=True, gone=False, members=[])
    dead = dict(sameInvocation=True, gone=True, members=[])
    def handover_dead():
        nonlocal state
        state = fresh()
        state['units'] = {role: record(role) for role in ('real', 'emergency')}
        with patch.object(adapter, 'Session', Session), patch.object(adapter, 'observe',
                side_effect=lambda r: dead if r['name'] == 'fixture-real' else live):
            result = adapter.manage(dict(operation='handover', session='fixture', generation='g'))
        assert not result['committed'] and not state['units']['emergency']['retire'], (result, state)
    case('exit-between-inspect-and-handover-retains-emergency', handover_dead)

    def terminal_publication_not_ready():
        nonlocal state
        state = fresh()
        real = record('real')
        real.pop('protocolReport')
        real['grant'] = False
        parent = adapter.proc_identity(os.getppid())
        real['clientIdentity'] = parent
        state['units'] = {'real': real}
        observed = dict(sameInvocation=True, gone=False, members=[parent])
        with patch.object(adapter, 'Session', Session), patch.object(adapter, 'observe', return_value=observed), \
                patch.object(adapter, 'client_reply', return_value={}):
            adapter.manage(dict(operation='client', session='fixture', generation='g', role='real', pid=os.getppid(),
                status={'session': 'fixture', 'generation': 'g', 'role': 'real', 'ready': True, 'terminal': True,
                        'settlement': 'retired'}))
            assert not state['units']['real']['client']['ready'], state['units']['real']['client']
            granted = adapter.manage(dict(operation='grant', session='fixture', generation='g', role='real'))
        assert not granted['granted'], granted
    case('terminal-client-publication-is-not-ready', terminal_publication_not_ready)

    def timeout_stop_keeps_secure(secure):
        nonlocal state
        state = fresh()
        real = record('real')
        real.pop('protocolReport')
        real['client']['secure'] = secure
        state['units'] = {'real': real}
        stops = []
        with patch.object(adapter, 'Session', Session), patch.object(adapter, 'observe', return_value=live), \
                patch.object(adapter, 'refresh_report', lambda *args: None), \
                patch.object(adapter, 'stop_record', side_effect=lambda r: stops.append(r['name']) or {'gone': True}):
            adapter.manage(dict(operation='stop', session='fixture', generation='g', role='real', unlessSecure=True))
        assert stops == ([] if secure else ['fixture-real']), stops
        assert state['units']['real']['retire'] is not secure
    case('timeout-stop-keeps-newly-secure-candidate', lambda: timeout_stop_keeps_secure(True))
    case('timeout-stop-retires-insecure-candidate', lambda: timeout_stop_keeps_secure(False))

    def dead_secure(consumer):
        nonlocal state
        state = fresh()
        state['snapshot']['adapter'] = 'opaque' if consumer == 'probe-race' else 'bundled'
        state['units'] = {role: record(role) for role in ('real', 'emergency')}
        state['units']['emergency']['clientIdentity'] = {'pid': 2147483647, 'start': 'missing'}
        with patch.object(adapter, 'Session', Session), patch.object(adapter, 'observe', return_value=live):
            result = adapter.manage(dict(operation=consumer, session='fixture', generation='g'))
        assert not result['retained' if consumer == 'probe-race' else 'committed'], (result, state)
        assert state['units']['emergency']['everSecure'] and not state['units']['emergency']['client']['secure']
    for consumer in ('probe-race', 'handover'):
        case('dead-client-live-wrapper-' + consumer, lambda c=consumer: dead_secure(c))

    def auth_retry():
        nonlocal state
        state = fresh()
        state['units'] = {role: record(role) for role in ('real', 'emergency', 'prehook')}
        calls = []
        def stop(record):
            calls.append(record['name'])
            if len(calls) == 1:
                raise adapter.Refused('controlled transient peer-stop failure')
            return dead
        job = dict(operation='authenticated', session='fixture', generation='g', role='emergency', pid=os.getpid())
        with patch.object(adapter, 'Session', Session), patch.object(adapter.os, 'getppid', return_value=os.getpid()), \
                patch.object(adapter, 'valid_client', side_effect=lambda d, r, p: d['units'][r]), \
                patch.object(adapter, 'stop_record', side_effect=stop):
            try:
                adapter.manage(job)
            except adapter.Refused:
                pass
            else:
                raise AssertionError('failed stop returned an unlock permit')
            assert state['phase'] == 'unlocking' and state['authRole'] == 'emergency'
            assert adapter.manage(job) == {'unlock': True, 'retire': False}
        assert calls == ['fixture-real', 'fixture-real', 'fixture-prehook'], calls
    case('existing-authenticated-transaction-retry', auth_retry)

    def wrapper_session(result):
        nonlocal state
        state = fresh()
        state['units']['real'] = record('real')
        seen = []
        ticks = iter((0, 2, 3, 4))
        def command(argv, **kwargs):
            seen.append(argv)
            if argv[0] == 'loginctl':
                if isinstance(result, Exception):
                    raise result
                return result
            return SimpleNamespace(returncode=0, stdout='')
        args = SimpleNamespace(generation='g', command=['not-executed'], deadline=None)
        with patch.dict(os.environ, ATMOSPHERA_LOCK_SESSION='fixture', ATMOSPHERA_LOCK_ROLE='real', INVOCATION_ID='real'), \
                patch.object(adapter, 'Session', Session), patch.object(adapter, 'command', command), \
                patch.object(adapter.subprocess, 'Popen', return_value=SimpleNamespace(poll=lambda: 0, returncode=0)), \
                patch.object(adapter, 'cgroup_members', side_effect=[[{'pid': os.getpid()+1}], []]), \
                patch.object(adapter.time, 'monotonic', side_effect=lambda: next(ticks)), patch.object(adapter.time, 'sleep'):
            adapter.run_unit(args)
        stops = [argv for argv in seen if argv[0] == 'systemctl']
        expected = not isinstance(result, Exception) and result.returncode == 0 and result.stdout.strip() == 'closing'
        assert bool(stops) == expected, seen
    case('logind-nonzero-is-inconclusive', lambda: wrapper_session(SimpleNamespace(returncode=1, stdout='')))
    case('logind-timeout-is-inconclusive', lambda: wrapper_session(subprocess.TimeoutExpired('loginctl', 10)))
    case('logind-confirmed-closing-stops', lambda: wrapper_session(SimpleNamespace(returncode=0, stdout='closing\n')))

    def command_bytes():
        sid = manage(source, {'operation': 'discover'})['session']
        descriptor = manage(source, dict(operation='begin', session=sid, snapshot={'adapter': 'opaque'}))
        base = dict(session=sid, generation=descriptor['generation'])
        output = work / 'literal command output'
        text = 'printf \'%s\\n\' \'${HOME} "$USER" $$\' "$HOME" > ' + shlex.quote(str(output))
        try:
            manage(source, dict(base, operation='launch', role='prehook', command=text))
            wait_for(lambda: manage(source, dict(base, operation='inspect'))['units']['prehook']['gone'])
            assert output.read_text() == '${HOME} "$USER" $$\n' + os.environ['HOME'] + '\n', output.read_text()
        finally:
            view = manage(source, dict(base, operation='inspect'))
            for role, observation in view['units'].items():
                if not observation['gone']:
                    manage(source, dict(base, operation='stop', role=role))
            manage(source, dict(base, operation='settle'))
    case('actual-systemd-literal-and-shell-expanded-command', command_bytes)
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
