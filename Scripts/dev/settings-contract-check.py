#!/usr/bin/env python3
"""Shared staged-index/full-checkout settings gates. No runtime shell or build."""
import argparse
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

ROOT=Path(__file__).resolve().parents[2]


def staged_snapshot(root,destination):
    tree=subprocess.check_output(['git','write-tree'],cwd=root,text=True,timeout=15).strip()
    archive=subprocess.check_output(['git','archive','--format=tar',tree],cwd=root,timeout=30)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        members=[entry for entry in tar.getmembers() if '.envrc' not in Path(entry.name).parts]
        tar.extractall(destination,members=members,filter='data')
    return tree


def check(root):
    for script,args in [
        ('build-settings-schema.py',['--check']),
        ('check-settings-writes.py',['--check']),
        ('build-settings-search-index.py',['--check']),
        ('settings-schema-selftest.py',[]),
        ('settings-writes-selftest.py',[]),
        ('settings-staged-selftest.py',[]),
    ]:
        result=subprocess.run([sys.executable,'-B',str(root/'Scripts/dev'/script),*args],cwd=root,timeout=120)
        if result.returncode:
            return result.returncode
    print('SETTINGS_CONTRACTS: PASS')
    return 0


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged',action='store_true')
    parser.add_argument('--root',type=Path,default=ROOT)
    args=parser.parse_args()
    if args.staged:
        with tempfile.TemporaryDirectory(prefix='settings-index-') as name:
            snapshot=Path(name)
            tree=staged_snapshot(args.root,snapshot)
            print('Settings staged tree:',tree,flush=True)
            # Run the checker/generators FROM the final index too, including
            # formatter restaging; unrelated unstaged source is never consulted.
            return subprocess.run([sys.executable,'-B',str(snapshot/'Scripts/dev/settings-contract-check.py')],
                                  cwd=snapshot,timeout=300).returncode
    return check(args.root)


if __name__=='__main__':
    sys.exit(main())
