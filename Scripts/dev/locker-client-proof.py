#!/usr/bin/env python3
"""Real PAM proofs for the shared managed-client/fencing primitives on niri.

This is not the full shell/owner acceptance matrix. It uses the minimal actual
locker UI twice to isolate auth-before-handover and handover-before-auth.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import re
import time

from locker_test_support import manage, require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    assert os.environ['XDG_CURRENT_DESKTOP'] == 'niri', 'takeover proof here is niri-only'
    config = args.config.resolve(strict=True)
    assert config.is_relative_to(Path('/home/tester/Projects/locker'))
    sid = manage(source, {'operation': 'discover'})['session']
    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no', 'unexpected existing holder'
    command = shlex.join(['env', 'WAYLAND_DEBUG=client', 'qs', '-p', str(config)])
    password = secrets.token_hex(16)
    credential = work / 'credential'
    credential.touch(mode=0o600)
    credential.write_text(password)
    original_hash = run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1]
    run(['sudo', '-n', 'chpasswd'], input='tester:' + password + '\n')
    base = None
    try:
        for case_name in ('auth-before-handover', 'handover-before-auth'):
            case = work / case_name
            case.mkdir()
            descriptor = manage(source, {'operation': 'begin', 'session': sid, 'snapshot': {'adapter': 'bundled'}})
            base = {'session': sid, 'generation': descriptor['generation']}

            def inspect():
                return manage(source, dict(base, operation='inspect'))

            def client(role):
                return inspect()['descriptor']['units'].get(role, {}).get('client') or {}

            def gone(role):
                return inspect()['units'][role]['gone']

            emergency = manage(source, dict(base, operation='launch', role='emergency', command=command))
            wait_for(lambda: client('emergency').get('secure'))
            assert inspect()['units']['emergency']['sameInvocation']
            run(['wtype', 'wrong-password'])
            run(['wtype', '-k', 'Return'])
            time.sleep(3)
            assert client('emergency')['secure'], 'failed PAM released the lock'
            assert inspect()['descriptor']['phase'] != 'unlocking', 'failed PAM authorized unlock'
            run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace'])
            # A standalone losing client must settle without PAM and without
            # releasing the independent already-secure holder.
            rejected_env = {key: value for key, value in os.environ.items()
                            if not key.startswith('ATMOSPHERA_LOCK_')}
            rejected_env['WAYLAND_DEBUG'] = 'client'
            rejected = subprocess.run(['qs', '-p', str(config)], env=rejected_env,
                                      capture_output=True, text=True, timeout=10)
            rejected_log = '\n'.join(line for line in (rejected.stdout + rejected.stderr).splitlines()
                                     if 'wl_keyboard#' not in line)
            (case / 'rejected-journal.txt').write_text(rejected_log)
            assert rejected.returncode == 0, rejected_log
            assert re.search(r'ext_session_lock_v1#\d+\.finished\(\)', rejected_log)
            assert 'unlock_and_destroy' not in rejected_log
            assert client('emergency')['secure'], 'rejected client released holder'
            real = manage(source, dict(base, operation='launch', role='real', command=command))
            wait_for(lambda: client('real').get('ready'))
            assert not client('real')['requested'] and not client('real')['secure'], client('real')
            if case_name == 'auth-before-handover':
                with credential.open() as secret:
                    run(['wtype', '-'], stdin=secret)
                run(['wtype', '-k', 'Return'])
                wait_for(lambda: inspect()['descriptor']['phase'] == 'unlocking')
                assert not manage(source, dict(base, operation='handover'))['committed']
                wait_for(lambda: gone('real') and gone('emergency'))
                assert not manage(source, dict(base, operation='grant', role='real'))['granted']
            else:
                assert manage(source, dict(base, operation='handover'))['committed']
                wait_for(lambda: gone('emergency'))
                assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes', 'handover unlocked'
                assert manage(source, dict(base, operation='grant', role='real'))['granted']
                wait_for(lambda: client('real').get('secure'))
                # Cross the original startup deadline on the actual secure
                # holder. It is not an engaged runtime limit or a fresh clock.
                wait_for(lambda: time.monotonic() > descriptor['deadline'] + 1, timeout=33)
                current = inspect()
                assert current['units']['real']['sameInvocation'] and not current['units']['real']['gone']
                assert current['descriptor']['units']['real']['identity']['InvocationID'] == real['identity']['InvocationID']
                assert client('real')['secure']
                assert run(['systemctl', '--user', 'show', real['name'], '-p', 'RuntimeMaxUSec', '--value']).stdout.strip() == 'infinity'
                with credential.open() as secret:
                    run(['wtype', '-'], stdin=secret)
                run(['wtype', '-k', 'Return'])
                wait_for(lambda: gone('real'))
            assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
            final = inspect()
            (case / 'final.json').write_text(json.dumps(final, indent=2))
            for role, record in (('real', real), ('emergency', emergency)):
                journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                               '_SYSTEMD_INVOCATION_ID=' + record['identity']['InvocationID']]).stdout
                # Preserve lock protocol and application diagnostics, not typed
                # key events from the protected throwaway test credential.
                journal = '\n'.join(line for line in journal.splitlines() if 'wl_keyboard#' not in line)
                (case / (role + '-journal.txt')).write_text(journal)
                if role == 'real' and case_name == 'auth-before-handover':
                    assert not re.search(r'ext_session_lock_manager_v1#\d+\.lock\(', journal), 'revoked candidate requested a lock'
                else:
                    assert re.search(r'ext_session_lock_v1#\d+\.locked\(\)', journal), 'missing native secure confirmation'
                if role == ('emergency' if case_name == 'auth-before-handover' else 'real'):
                    assert journal.count('unlock_and_destroy') == 1, journal
                else:
                    assert 'unlock_and_destroy' not in journal, journal
                assert final['units'][role]['gone'] and not final['units'][role]['members'], final
            manage(source, dict(base, operation='settle'))
            base = None
        (work / 'result.txt').write_text('PASS managed-client-primitives\n')
        print('PASS managed-client-primitives', work)
    finally:
        # Stop only our recorded generation. This is fail-closed, not an
        # unauthenticated cleanup unlock. Preserve failure state for diagnosis.
        if base is not None:
            current = manage(source, dict(base, operation='inspect'))
            (work / 'failure-status.json').write_text(json.dumps(current, indent=2))
            for role in current['units']:
                manage(source, dict(base, operation='stop', role=role))
            manage(source, dict(base, operation='settle'))
        run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
        credential.unlink()


if __name__ == '__main__':
    main()
