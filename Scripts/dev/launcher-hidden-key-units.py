#!/usr/bin/env python3
"""Actual retained-focus header/QuickLook and generic-item real-key regressions."""
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
    p.add_argument('--case', choices=['generic', 'header', 'overlay', 'readiness', 'all'], default='all')
    a = p.parse_args()
    source = a.source.resolve()
    assert source.is_relative_to(ROOT / 'sources')
    out, runtime = ROOT / 'evidence' / a.label, ROOT / 'runtime' / a.label
    assert not out.exists() and not runtime.exists()
    out.mkdir()
    fixture = a.fixture or source / 'Scripts/dev/fixtures/launcher-hidden-keys.qml'
    cases, errors = [], []
    for kind in (['generic', 'header', 'overlay', 'readiness'] if a.case == 'all' else [a.case]):
        tree, profile = runtime / kind / 'tree', runtime / kind / 'profile'
        shutil.copytree(source, tree, symlinks=True)
        case_fixture = (source / 'Scripts/dev/fixtures/launcher-guard-readiness.qml') if kind == 'readiness' and not a.fixture else fixture
        (tree / 'shell.qml').write_text(case_fixture.read_text())
        env = dict(profile_env(profile), LAUNCHER_KEY_CASE=kind,
                   LAUNCHER_GUARD_AVAILABLE='1' if (tree / 'Widgets/NInputGuard.qml').exists() else '0',
                   LAUNCHER_INPUT_HELPER=str(ROOT / 'tools/filechooser_input.py'))
        proc = subprocess.run(['timeout', '--kill-after=5', '15', 'qs', '-p', str(tree / 'shell.qml')],
                              env=env, cwd=tree, capture_output=True, text=True, timeout=25)
        log = proc.stdout + proc.stderr
        (out / (kind + '.log')).write_text(log)
        rows = [json.loads(line.split('HIDDEN_KEYS|', 1)[1]) for line in log.splitlines() if 'HIDDEN_KEYS|' in line]
        errors.extend(line for line in log.splitlines() if re.search(r'ReferenceError|TypeError|Cannot assign|Binding loop|Failed to load configuration|is not a type', line))
        cases.extend(rows)
        if proc.returncode != 0 or 'HIDDEN_KEYS_DONE' not in log:
            errors.append(f'{kind}: exit={proc.returncode}, complete={"HIDDEN_KEYS_DONE" in log}')
    expected = 46 if a.case == 'all' else (3 if a.case == 'readiness' else 15 if a.case == 'overlay' else 14)
    result = dict(passed=len(cases) == expected and all(c['pass'] for c in cases) and not errors,
                  cases=cases, errors=errors, source=str(source), fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest())
    (out / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
