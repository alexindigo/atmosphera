#!/usr/bin/env python3
"""Real private-seat Return/Escape across hidden/disabled/inactive/reopened scopes."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

from launcher_workspace import ROOT
sys.path.insert(0, str(ROOT / 'tools'))
from filechooser_isolation import enter, guest, profile_env


def main():
    enter(runtime_seconds=90)
    guest()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--label', required=True)
    a = p.parse_args()
    source = a.source.resolve()
    assert source.is_relative_to(ROOT / 'sources')
    out, runtime = ROOT / 'evidence' / a.label, ROOT / 'runtime' / a.label
    assert not out.exists() and not runtime.exists()
    out.mkdir()
    tree, profile = runtime / 'tree', runtime / 'profile'
    shutil.copytree(source, tree, symlinks=True)
    (tree / 'shell.qml').write_text((source / 'Scripts/dev/fixtures/launcher-shortcut-scope.qml').read_text())
    env = dict(profile_env(profile), LAUNCHER_INPUT_HELPER=str(ROOT / 'tools/filechooser_input.py'))
    proc = subprocess.run(['timeout', '--kill-after=5', '20', 'qs', '-p', str(tree / 'shell.qml')],
                          env=env, cwd=tree, capture_output=True, text=True, timeout=30)
    log = proc.stdout + proc.stderr
    (out / 'run.log').write_text(log)
    cases = [json.loads(line.split('LAUNCHER_SCOPE|', 1)[1]) for line in log.splitlines() if 'LAUNCHER_SCOPE|' in line]
    errors = [line for line in log.splitlines() if re.search(r'ReferenceError|TypeError|Cannot assign|Binding loop|Failed to load configuration|is not a type', line)]
    result = dict(passed=proc.returncode == 0 and len(cases) == 5 and all(c['pass'] for c in cases) and not errors and 'LAUNCHER_SCOPE_DONE' in log,
                  exit=proc.returncode, cases=cases, errors=errors)
    (out / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
