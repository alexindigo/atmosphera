#!/usr/bin/env python3
"""Guest-only strict compositor/session association regression inputs.

Synthetic proc/logind inputs test rejection boundaries, not native lock or PAM.
The lifecycle proofs separately exercise discovery in a real graphical session.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import stat
from types import SimpleNamespace
from unittest.mock import patch

from locker_test_support import require_guest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    spec = importlib.util.spec_from_file_location('locker_unit', source / 'Scripts/python/locker-unit.py')
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    uid = os.getuid()
    results = []
    for compositor in ('niri', 'Hyprland'):
        cases = [
            ('scope', {'scope': '42'}, True),
            ('scope-online', {'scope': '42', 'State': 'online'}, True),
            ('scope-ignores-environment', {'scope': '42', 'env_sid': '99', 'env_seat': 'seat9'}, True),
            ('service', {}, True),
            ('service-online', {'State': 'online'}, True),
            ('scope-mismatch', {'scope': '99'}, False),
            ('scope-ineligible-no-fallback', {'scope': '99', 'extra_session': True}, False),
            ('service-mismatch', {'env_sid': '99'}, False),
            ('service-foreign', {'User': str(uid + 1)}, False),
            ('service-tty', {'Type': 'tty'}, False),
            ('service-manager', {'Class': 'manager'}, False),
            ('service-remote', {'Remote': 'yes'}, False),
            ('service-closing', {'State': 'closing'}, False),
            ('service-seat-mismatch', {'env_seat': 'seat1'}, False),
            ('service-missing-seat', {'env_seat': ''}, False),
            ('service-missing-session', {'env_sid': ''}, False),
            ('service-unseated-session', {'Seat': ''}, False),
            ('service-caller-cannot-override', {'env_sid': '', 'env_seat': ''}, False),
            ('wanted-mismatch', {'wanted': '99'}, False),
            ('wrong-process-user', {'proc_uid': uid + 1}, False),
            ('wrong-process-comm', {'comm': 'not-the-compositor'}, False),
            ('departed-process', {'departed': True}, False),
            ('unreadable-environment', {'unreadable': True}, False),
            ('scope-foreign', {'scope': '42', 'User': str(uid + 1)}, False),
        ]
        for name, change, accepted in cases:
            info = dict(Id='42', User=str(uid), Type='wayland', Class='user', State='active', Remote='no', Seat='seat0')
            info.update({key: value for key, value in change.items() if key in info})
            group = ('0::/user.slice/user-1000.slice/session-' + change['scope'] + '.scope\n'
                     if 'scope' in change else '0::/user.slice/user-1000.slice/user@1000.service/session.slice/compositor.service\n')
            environment = {'XDG_SESSION_ID': change.get('env_sid', '42'), 'XDG_SEAT': change.get('env_seat', 'seat0')}
            caller = {'XDG_SESSION_ID': '42', 'XDG_SEAT': 'seat0'}
            caller.update({'NIRI_SOCKET': '/run/user/1000/niri.wayland-1.4242.sock'} if compositor == 'niri'
                          else {'HYPRLAND_INSTANCE_SIGNATURE': 'test-instance'})

            def command(argv):
                if argv[:2] == ['loginctl', 'list-sessions']:
                    return SimpleNamespace(stdout='42 1000 tester\n' + ('99 1000 tester\n' if change.get('extra_session') else ''))
                assert argv == ['hyprctl', '-j', 'instances'], argv
                return SimpleNamespace(stdout=json.dumps([{'instance': 'test-instance', 'pid': 4242}]))

            def properties(argv):
                assert argv[:2] == ['loginctl', 'show-session'], argv
                return info if argv[2] == '42' else dict(info, Id='99', Type='tty')

            def read_text(path, *args, **kwargs):
                if str(path) == '/proc/4242/comm':
                    return change.get('comm', compositor) + '\n'
                assert str(path) == '/proc/4242/cgroup', path
                return group

            def read_bytes(path):
                assert str(path) == '/proc/4242/environ', path
                if change.get('unreadable'):
                    raise PermissionError('fixture environment unreadable')
                return b'\0'.join((key + '=' + value).encode() for key, value in environment.items()) + b'\0'

            identity = {'pid': 4242, 'start': '123'}
            with patch.dict(os.environ, caller, clear=True), \
                    patch.object(adapter, 'command', command), \
                    patch.object(adapter, 'properties', properties), \
                    patch.object(adapter, 'proc_identity', return_value=identity), \
                    patch.object(adapter, 'same_process', return_value=not change.get('departed')), \
                    patch.object(Path, 'read_text', read_text), \
                    patch.object(Path, 'read_bytes', read_bytes), \
                    patch.object(Path, 'stat', return_value=SimpleNamespace(st_uid=change.get('proc_uid', uid))), \
                    patch.object(os, 'stat', return_value=SimpleNamespace(st_uid=uid, st_mode=stat.S_IFSOCK)):
                try:
                    sid = adapter.graphical_session(change.get('wanted'))
                except adapter.Refused as error:
                    assert not accepted, (compositor, name, str(error))
                    result = {'compositor': compositor, 'case': name, 'refused': str(error)}
                else:
                    assert accepted and sid == '42', (compositor, name, sid)
                    result = {'compositor': compositor, 'case': name, 'session': sid}
            results.append(result)
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    print('PASS session-association', len(results), work)


if __name__ == '__main__':
    main()
