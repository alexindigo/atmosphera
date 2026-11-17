#!/usr/bin/env python3
"""Guest-only actual-main locker acceptance entry points.

Each subproof retains its complete native/PAM/identity assertions. Source-based
orphan red/green is intentionally separate from main-root install acceptance.
"""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
import time

from locker_test_support import manage, require_guest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=('fast', 'slow', 'boundary', 'rejected', 'resources', 'external', 'contract', 'restart', 'packaging', 'cold-load', 'orphan-acceptance'), required=True)
    parser.add_argument('--sample-seconds', type=float, default=10)
    parser.add_argument('--post-unlock-seconds', type=float, default=10)
    parser.add_argument('--delays', default='2.9,3.0,3.1,29.9,30.0,30.1')
    parser.add_argument('--states', default='engaged,starting,fallback,handing-over')
    parser.add_argument('--variants', default='existing,missing,slow5,slow40,nonzero,crash,pipeline,daemonizing,term-resistant')
    parser.add_argument('--ui', choices=('builtin', 'demo'), default='builtin')
    parser.add_argument('--delay', type=float, default=5)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--recover-known-pam-hang', action='store_true')
    args = parser.parse_args()
    driver = Path(__file__).resolve().parents[2]
    source, work = require_guest(args.work, args.source)
    if args.case != 'orphan-acceptance' and source != driver:
        parser.error('--source is currently supported only by orphan-acceptance')
    initial = None
    if args.case in ('rejected', 'resources'):
        sid = manage(driver, {'operation': 'discover'})['session']
        initial = manage(driver, {'operation': 'inspect', 'session': sid})
    commands = []
    if args.case in ('rejected', 'resources'):
        command = ['locker-rejected-proof.py', '--sample-seconds', str(args.sample_seconds),
            '--post-unlock-seconds', str(args.post_unlock_seconds)]
        if args.case == 'resources':
            command.append('--resources')
        if args.recover_known_pam_hang:
            command.append('--recover-known-pam-hang')
        commands.append(('primary', command))
    elif args.case == 'external':
        # Validate the unchanged PR #21 checker with real side-effecting inputs.
        # Availability checking must never execute any part of the expression.
        marker = work / 'checker-side-effect'
        executable = work / 'checker-executable'
        executable.write_text('#!/bin/sh\nprintf executed > ' + shlex.quote(str(marker)) + '\n')
        executable.chmod(0o700)
        checks = [(str(executable), 'available'),
                  (str(work / 'nonexistent-checker-executable'), 'missing'),
                  (str(executable) + '; touch ' + shlex.quote(str(marker)), 'unverified'),
                  ('sh -c ' + shlex.quote('touch ' + str(marker)), 'available')]
        for expression, expected in checks:
            result = subprocess.run(['python3', '-B', str(driver / 'Scripts/python/check-external-command.py'), expression],
                text=True, capture_output=True, timeout=5, check=True)
            assert result.stdout.strip() == expected and not marker.exists(), (expression, result.stdout)
        (work / 'availability.json').write_text(json.dumps({'checks': len(checks), 'sideEffect': marker.exists()}))
        for variant in args.variants.split(','):
            command = ['locker-owner-proof.py', '--main-shell', '--case', 'external', '--external-variant', variant]
            if args.recover_known_pam_hang:
                command.append('--recover-known-pam-hang')
            commands.append((variant, command))
        # Preserve the already-defined cooperative and event-driven opaque
        # checks as part of this entry point, not as claims inferred from units.
        cooperative = ['locker-owner-proof.py', '--main-shell', '--case', 'slow', '--delay', '5']
        if args.recover_known_pam_hang:
            cooperative.append('--recover-known-pam-hang')
        commands.append(('cooperative', cooperative))
        for case in ('opaque-holder', 'opaque-sleep', 'opaque-crash', 'opaque-race', 'opaque-withdraw'):
            commands.append((case, ['locker-owner-proof.py', '--case', case]))
    elif args.case in ('packaging', 'cold-load'):
        commands.append(('layout', ['locker-package-proof.py']))
        commands.append(('settings-readonly', ['locker-settings-proof.py']))
        for ui in ('builtin', 'demo'):
            command = ['locker-owner-proof.py', '--main-shell', '--case', 'fast', '--ui', ui]
            if args.recover_known_pam_hang:
                command.append('--recover-known-pam-hang')
            commands.append((ui, command))
        commands.append(('emergency', ['locker-contract-proof.py', '--variant', 'normal']))
    elif args.case == 'boundary':
        for delay in args.delays.split(','):
            command = ['locker-owner-proof.py', '--main-shell', '--case', 'boundary', '--delay', str(float(delay))]
            if args.recover_known_pam_hang:
                command.append('--recover-known-pam-hang')
            commands.append(('ready-' + delay, command))
        commands.append(('policy-orderings', ['locker-state-proof.py']))
        commands.append(('auth-before-ready', ['locker-owner-proof.py', '--main-shell', '--case', 'slow',
            '--delay', '5', '--emergency-auth-before-ready']))
    elif args.case == 'restart':
        for state in args.states.split(','):
            assert state in ('engaged', 'starting', 'fallback', 'handing-over'), 'unknown restart state'
            command = ['locker-owner-proof.py', '--main-shell']
            command += ['--case', 'fast'] if state == 'engaged' else ['--case', 'slow', '--delay', '5', '--restart-state', state]
            if args.recover_known_pam_hang:
                command.append('--recover-known-pam-hang')
            commands.append((state, command))
    elif args.case == 'contract':
        for variant in ('normal', 'error', 'no-engagement', 'disappearing'):
            command = ['locker-contract-proof.py', '--variant', variant]
            if args.recover_known_pam_hang:
                command.append('--recover-known-pam-hang')
            commands.append((variant, command))
    elif args.case == 'orphan-acceptance':
        commands.append(('orphan', ['locker-orphan-proof.py', '--source', str(source)]))
    else:
        common = ['locker-owner-proof.py', '--main-shell', '--case', args.case, '--ui', args.ui]
        if args.recover_known_pam_hang:
            common.append('--recover-known-pam-hang')
        if args.case == 'slow':
            common += ['--delay', str(args.delay)]
        commands.append(('primary', common))
        if args.case == 'slow' and args.delay < 30:
            commands.append(('emergency-auth-before-ready', common + ['--emergency-auth-before-ready']))
    for name, command in commands:
        command = ['python3', '-B', str(driver / 'Scripts/dev' / command[0]), *command[1:], '--work', str(work / name)]
        with (work / (name + '-output.txt')).open('x') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=240)
        print((work / (name + '-output.txt')).read_text(), end='', flush=True)
        assert result.returncode == 0, str(command)
    if args.case in ('packaging', 'cold-load'):
        emergency = (work / 'emergency/fixture-protocol.txt').read_text()
        assert 'Registry' not in emergency and 'PluginService' not in emergency, 'emergency initialized non-lock runtime'
        assert emergency.count('unlock_and_destroy') == 1, 'emergency did not authenticate/tear down normally'
    if args.case != 'orphan-acceptance':
        sid = manage(driver, {'operation': 'discover'})['session']
        time.sleep(10)
        final = manage(driver, {'operation': 'inspect', 'session': sid})
        if args.case in ('rejected', 'resources'):
            # Independent rejection fixtures create no generation. A fresh
            # guest can correctly have no owner descriptor at all.
            assert final['descriptor'] == initial['descriptor'], 'independent clients changed owner generation'
            if final['descriptor'] is None:
                assert 'units' not in final, 'unit observations without a generation'
            else:
                assert all(unit['gone'] and not unit['members'] for unit in final['units'].values())
        else:
            assert final['descriptor']['phase'] == 'settled'
            assert all(unit['gone'] and not unit['members'] for unit in final['units'].values())
        (work / 'post-unlock.json').write_text(json.dumps(final, indent=2))
    recovery = any((work / name / 'known-pam-hang-recovery.json').exists() for name, _ in commands)
    suffix = ' (known native PAM hang recovered)' if recovery else ''
    (work / 'result.txt').write_text('PASS ' + args.case + suffix + '\n')
    print('PASS ' + args.case + suffix, work)


if __name__ == '__main__':
    main()
