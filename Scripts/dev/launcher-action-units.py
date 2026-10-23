#!/usr/bin/env python3
"""Real process side effects after synchronous launcher/provider destruction."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path('/home/tester/Projects/atmosphera-launcher')
sys.path.insert(0, str(ROOT / 'tools'))
from filechooser_isolation import enter, guest, profile_env


def main():
    enter(runtime_seconds=90)
    guest()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--label', required=True)
    p.add_argument('--fixture', type=Path)
    a = p.parse_args()
    source = a.source.resolve()
    assert source.is_relative_to(ROOT / 'sources')
    out, runtime = ROOT / 'evidence' / a.label, ROOT / 'runtime' / a.label
    assert not out.exists() and not runtime.exists()
    out.mkdir()
    fixture = a.fixture or source / 'Scripts/dev/fixtures/launcher-action-lifetime.qml'
    cases = []
    for kind in ('application', 'command'):
        tree = runtime / kind / 'tree'
        profile = runtime / kind / 'profile'
        shutil.copytree(source, tree, symlinks=True)
        (tree / 'shell.qml').write_text(fixture.read_text().replace('"../../../Modules/', '"Modules/'))
        result = out / (kind + '.consumer')
        executable = out / (kind + '.sh')
        expression = "printf '%s' 'survived-" + kind + "' > '" + str(result) + "'"
        executable.write_text('#!/bin/sh\n' + expression + '\n')
        executable.chmod(0o700)
        env = dict(profile_env(profile), LAUNCHER_ACTION_KIND=kind,
                   LAUNCHER_ACTION_COMMAND=expression, LAUNCHER_ACTION_EXECUTABLE=str(executable))
        proc = subprocess.run(['timeout', '--kill-after=5', '15', 'qs', '-p', str(tree / 'shell.qml')],
                              env=env, cwd=tree, capture_output=True, text=True, timeout=25)
        log = proc.stdout + proc.stderr
        (out / (kind + '.log')).write_text(log)
        actual = result.read_text() if result.exists() else None
        errors = [line for line in log.splitlines() if re.search(r'ReferenceError|TypeError|Cannot assign|Failed to load configuration|is not a type', line)]
        cases.append(dict(name=kind + '-survives-immediate-destruction', passed=proc.returncode == 0 and
                          'LAUNCHER_LIFETIME_DESTROYED|true' in log and actual == 'survived-' + kind and not errors,
                          exit=proc.returncode, actual=actual, errors=errors))
    receipt = dict(passed=all(row['passed'] for row in cases), source=str(source), cases=cases,
                   fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest())
    (out / 'result.json').write_text(json.dumps(receipt, indent=2))
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
