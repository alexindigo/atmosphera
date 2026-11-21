#!/usr/bin/env python3
"""Settings gates: --quick for commit sanity; full analysis/regressions in CI."""
import argparse
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

ROOT=Path(__file__).resolve().parents[2]

# Keep the commit path to authored/generated-data sanity checks. The default
# remains the complete suite, so local full runs and CI cannot omit analysis.
QUICK_CHECKS = [
    ('build-settings-schema.py', ['--check']),
    ('build-settings-search-index.py', ['--check']),
    ('builtin-plugin-settings-check.py', []),
]
FULL_CHECKS = [
    QUICK_CHECKS[0],
    # Measured at 62.5s in the 2-CPU VM container and 100-130s on CI.
    # Five minutes allows runner variation without hiding an actual hang.
    ('check-settings-writes.py', ['--check']),
    *QUICK_CHECKS[1:],
    ('settings-schema-selftest.py', []),
    ('settings-formatter-selftest.py', []),
    ('settings-writes-selftest.py', []),
    ('settings-staged-selftest.py', []),
    ('settings-runner-paths-selftest.py', []),
    ('settings-hook-selftest.py', []),
]


def staged_snapshot(root,destination):
    tree=subprocess.check_output(['git','write-tree'],cwd=root,text=True,timeout=15).strip()
    archive=subprocess.check_output(['git','archive','--format=tar',tree],cwd=root,timeout=30)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        members=[entry for entry in tar.getmembers() if '.envrc' not in Path(entry.name).parts]
        tar.extractall(destination,members=members,filter='data')
    return tree


def check(root, quick=False):
    root = root.resolve()
    for script,args in QUICK_CHECKS if quick else FULL_CHECKS:
        deadline = 300 if script == 'check-settings-writes.py' else 10 if quick else 120
        try:
            result=subprocess.run([sys.executable,'-B',str(root/'Scripts/dev'/script),*args],cwd=root,timeout=deadline)
        except subprocess.TimeoutExpired:
            print(f'SETTINGS_CONTRACTS: {script} exceeded {deadline}s', file=sys.stderr)
            return 1
        if result.returncode:
            return result.returncode
    print('SETTINGS_SANITY: PASS' if quick else 'SETTINGS_CONTRACTS: PASS')
    return 0


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged',action='store_true')
    parser.add_argument('--quick',action='store_true',help='freshness/compatibility sanity only; no analysis or regressions')
    parser.add_argument('--root',type=Path,default=ROOT)
    args=parser.parse_args()
    args.root = args.root.resolve()
    if args.staged:
        with tempfile.TemporaryDirectory(prefix='settings-index-') as name:
            snapshot=Path(name)
            tree=staged_snapshot(args.root,snapshot)
            print('Settings staged tree:',tree,flush=True)
            # Run the checker/generators FROM the final index too, including
            # formatter restaging; unrelated unstaged source is never consulted.
            command = [sys.executable,'-B',str(snapshot/'Scripts/dev/settings-contract-check.py')]
            if args.quick:
                command.append('--quick')
            return subprocess.run(command,cwd=snapshot,timeout=60 if args.quick else 600).returncode
    return check(args.root, quick=args.quick)


if __name__=='__main__':
    sys.exit(main())
