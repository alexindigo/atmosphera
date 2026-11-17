#!/usr/bin/env python3
"""Guest-only actual-main locker acceptance entry points.

Each subproof retains its complete native/PAM/identity assertions. Source-based
orphan red/green is intentionally separate from main-root install acceptance.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

from locker_test_support import manage, require_guest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=('fast', 'slow', 'orphan-acceptance'), required=True)
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
    commands = []
    if args.case == 'orphan-acceptance':
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
    if args.case != 'orphan-acceptance':
        sid = manage(driver, {'operation': 'discover'})['session']
        time.sleep(10)
        final = manage(driver, {'operation': 'inspect', 'session': sid})
        assert final['descriptor']['phase'] == 'settled'
        assert all(unit['gone'] and not unit['members'] for unit in final['units'].values())
        (work / 'post-unlock.json').write_text(json.dumps(final, indent=2))
    recovery = any((work / name / 'known-pam-hang-recovery.json').exists() for name, _ in commands)
    suffix = ' (known native PAM hang recovered)' if recovery else ''
    (work / 'result.txt').write_text('PASS ' + args.case + suffix + '\n')
    print('PASS ' + args.case + suffix, work)


if __name__ == '__main__':
    main()
