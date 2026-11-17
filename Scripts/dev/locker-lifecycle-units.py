#!/usr/bin/env python3
"""Guest-only lifecycle policy, exact-unit, client and inhibitor proof suite."""
import argparse
import os
from pathlib import Path
import subprocess

from locker_test_support import require_guest, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    config = stage / 'etc/xdg/quickshell/atmosphera-emergency-lock'
    commands = [
        ('state', 'locker-state-proof.py', []),
        ('adapter', 'locker-unit-adapter-proof.py', []),
        ('reports', 'locker-report-validation.py', []),
        ('client', 'locker-client-proof.py', ['--config', str(config)]),
        ('inhibitor', 'locker-inhibitor-proof.py', []),
    ]
    for name, script, extra in commands:
        command = ['python3', '-B', str(source / 'Scripts/dev' / script), '--work', str(work / name), *extra]
        with (work / (name + '-output.txt')).open('x') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        print((work / (name + '-output.txt')).read_text(), end='', flush=True)
        assert result.returncode == 0, str(command)
    (work / 'result.txt').write_text('PASS units\n')
    print('PASS units', work)


if __name__ == '__main__':
    main()
