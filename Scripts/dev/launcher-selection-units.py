#!/usr/bin/env python3
"""QML core/selection and actual list/grid hover consumer regressions in private sway."""
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
    (tree / 'shell.qml').write_text((source / 'Scripts/dev/fixtures/launcher-selection.qml').read_text().replace('"../../../Modules/', '"Modules/'))
    build = runtime / 'pointer-build'
    build.mkdir()
    env = dict(profile_env(profile), LAUNCHER_INPUT_HELPER=str(ROOT / 'tools/filechooser_input.py'))
    protocol = source / 'Scripts/dev/wlr-virtual-pointer-unstable-v1.xml'
    for mode, name in [('client-header', 'virtual-pointer-client.h'), ('private-code', 'virtual-pointer-protocol.c')]:
        subprocess.run(['timeout', '15', 'wayland-scanner', mode, protocol, build / name], check=True, timeout=20, env=env)
    flags = subprocess.run(['timeout', '5', 'pkg-config', '--cflags', '--libs', 'wayland-client'], env=env,
                           capture_output=True, text=True, check=True, timeout=10).stdout.split()
    subprocess.run(['timeout', '30', 'cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I', build,
                    source / 'Scripts/dev/launcher-test-pointer.c', build / 'virtual-pointer-protocol.c',
                    *flags, '-o', build / 'pointer'], env=env, check=True, timeout=35)
    pointer = subprocess.Popen(['timeout', '30', build / 'pointer'], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        assert pointer.stdout.readline().strip() == 'POINTER_READY'
        proc = subprocess.run(['timeout', '--kill-after=5', '20', 'qs', '-p', str(tree / 'shell.qml')],
                              env=env, cwd=tree, capture_output=True, text=True, timeout=30)
    finally:
        pointer.stdin.close()
        assert pointer.wait(timeout=10) == 0
    log = proc.stdout + proc.stderr
    (out / 'run.log').write_text(log)
    cases = [json.loads(line.split('LAUNCHER_SELECTION|', 1)[1]) for line in log.splitlines() if 'LAUNCHER_SELECTION|' in line]
    errors = [line for line in log.splitlines() if re.search(r'ReferenceError|TypeError|Cannot assign|Failed to load configuration|is not a type', line)]
    result = dict(passed=proc.returncode == 0 and len(cases) == 25 and all(c['pass'] for c in cases) and not errors and 'LAUNCHER_SELECTION_DONE' in log,
                  exit=proc.returncode, cases=cases, errors=errors)
    (out / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
