#!/usr/bin/env python3
"""Guest-only display association -> managed emergency lock -> real PAM proof.

This is a narrow adapter/client proof, not the full main-shell owner matrix.
The installed UI gains read-only test observations; authentication is unchanged.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import time

from locker_test_support import manage, recover_known_pam_hang, require_guest, run, wait_for


PROBE = '''
  IpcHandler {
    target: "associationProof"
    function state(): string { return JSON.stringify({secure: lock.secure,
      busy: lockAuth.unlockInProgress, failed: lockAuth.showFailure,
      terminal: client.terminal}); }
  }
  Connections {
    target: lockAuth
    function onDiagnostic(message) { console.log("AUTH_DIAGNOSTIC " + message); }
  }
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--recover-known-pam-hang', action='store_true')
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    discovery = manage(source, {'operation': 'discover'})
    sid = discovery['session']
    old = manage(source, {'operation': 'inspect', 'session': sid})
    assert not old['descriptor'] or old['descriptor']['phase'] == 'settled', 'existing generation is not a target'
    configs = work / 'quickshell'
    run(['bash', str(source / 'Scripts/bash/install-locker-configs'), str(source), str(configs)], timeout=60)
    shell = configs / 'atmosphera-emergency-lock/shell.qml'
    ui = shell.with_name('EmergencyLock.qml')
    original = ui.read_text()
    assert original.count('  id: root\n') == 1
    ui.write_text('import Quickshell.Io\n' + original.replace('  id: root\n', '  id: root\n' + PROBE))
    descriptor = manage(source, {'operation': 'begin', 'session': sid,
        'snapshot': {'adapter': 'bundled'}})
    base = {'session': sid, 'generation': descriptor['generation']}
    password = secrets.token_hex(16)
    credential = work / 'credential'
    credential.touch(mode=0o600)
    credential.write_text(password)
    original_hash = run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1]
    record = None
    restored = False

    def inspect():
        return manage(source, dict(base, operation='inspect'))

    def journal():
        return run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
            '_SYSTEMD_INVOCATION_ID=' + record['identity']['InvocationID']]).stdout

    def ui_state():
        result = run(['qs', 'ipc', '-p', str(shell), 'call', 'associationProof', 'state'])
        return json.loads(result.stdout)

    try:
        run(['sudo', '-n', 'chpasswd'], input='tester:' + password + '\n')
        record = manage(source, dict(base, operation='launch', role='emergency',
            command=shlex.join(['env', 'WAYLAND_DEBUG=client', 'qs', '-p', str(shell)])))
        wait_for(lambda: (inspect()['descriptor']['units']['emergency'].get('client') or {}).get('secure'), 20)
        secure = inspect()
        assert secure['units']['emergency']['sameInvocation']
        assert ui_state() == {'secure': True, 'busy': False, 'failed': False, 'terminal': False}
        run(['wtype', 'wrong-password'])
        run(['wtype', '-k', 'Return'])
        if args.recover_known_pam_hang:
            time.sleep(3)
            recover_known_pam_hang(source, sid, 'emergency', work)
        wait_for(lambda: ui_state()['failed'] and not ui_state()['busy'], 20)
        refused = inspect()
        assert refused['descriptor']['phase'] != 'unlocking'
        assert refused['descriptor']['units']['emergency']['client']['secure']
        assert 'unlock_and_destroy' not in journal(), 'wrong-password authentication unlocked'
        # Readiness is observed, not a fixed delay before the second attempt.
        run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace'])
        authenticated_at = time.monotonic()
        with credential.open() as secret:
            run(['wtype', '-'], stdin=secret)
        run(['wtype', '-k', 'Return'])
        wait_for(lambda: inspect()['units']['emergency']['gone'], 20)
        final = inspect()
        client = final['descriptor']['units']['emergency']
        assert client['protocolOutcome'] == 'authenticated-unlock'
        assert client['client']['authenticated'] and final['descriptor']['phase'] == 'unlocking'
        assert not final['units']['emergency']['members']
        text = journal()
        assert re.search(r'ext_session_lock_v1#\d+\.locked\(\)', text), 'no native secure event'
        assert text.count('unlock_and_destroy') == 1
        assert text.index('AUTH_DIAGNOSTIC Authentication successful') < text.index('unlock_and_destroy')
        manage(source, dict(base, operation='settle'))
        (work / 'result.json').write_text(json.dumps(dict(passed=True, discovery=discovery,
            wrongPasswordRetainedLock=True, realPamAuthenticated=True,
            authenticatedInputAt=authenticated_at, final=final), indent=2))
        print('PASS association-native-PAM', os.environ['XDG_CURRENT_DESKTOP'], work)
    finally:
        # Restore independently of inspection/teardown errors; never kill a
        # secure holder as cleanup. A failure retains its exact descriptor.
        try:
            run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
            restored = True
        finally:
            if restored:
                credential.unlink()
            if record is not None:
                text = '\n'.join(line for line in journal().splitlines() if 'wl_keyboard' not in line)
                (work / 'native-journal.txt').write_text(text)


if __name__ == '__main__':
    main()
