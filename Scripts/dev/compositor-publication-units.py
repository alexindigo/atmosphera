#!/usr/bin/env python3
"""Compositor facade publication contract with a scripted backend, both orders.

Runs a private shell (fixtures/compositor-publication.qml) on a copy of the
source tree, with no compositor environment so no live backend competes. Each
step changes the scripted backend's windows and focused id, then emits its
notifications list-first or focus-first. Every facade notification callback
(and a focused-title binding) must read one coherent state: focused id, index,
row flags, getFocusedWindow() and the title all describing the same window,
and a focus the window list does not contain is never published.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

from launcher_workspace import ROOT
from launcher_paste_support import profile_environment
from workspace_guard import require_disk_backed_paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--workspace', type=Path, default=ROOT)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('flow', Path(__file__).with_name('launcher-flow-e2e.py'))
    flow = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(flow)
    workspace = args.workspace.resolve()
    if workspace == ROOT:
        flow.boundary()
    else:
        require_disk_backed_paths(workspace, os.environ.get('TMPDIR', ''), args.source)
        if not Path(os.environ['XDG_RUNTIME_DIR'], os.environ['WAYLAND_DISPLAY']).is_socket():
            parser.error('the fixture needs the guest Wayland session')
    output, runtime = workspace / 'evidence' / args.label, workspace / 'runtime' / args.label
    output.mkdir(parents=True)
    tree = runtime / 'tree'
    shutil.copytree(args.source, tree, symlinks=True)
    shell = tree / 'shell.qml'
    shell.write_text((Path(__file__).parent / 'fixtures/compositor-publication.qml').read_text())
    env = profile_environment(runtime / 'profile', tree)
    for name in ('NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'SWAYSOCK', 'LABWC_PID', 'XDG_CURRENT_DESKTOP'):
        env.pop(name, None)
    log_path = output / 'shell.log'
    with log_path.open('x') as log:
        process = subprocess.run(['timeout', '--kill-after=5', '60', 'qs', '-p', str(shell), '--no-color'],
                                 env=env, cwd=tree, stdout=log, stderr=subprocess.STDOUT, timeout=70)
    lines = [line.split('PUBLICATION_RESULT|', 1)[1] for line in log_path.read_text().splitlines() if 'PUBLICATION_RESULT|' in line]
    steps = json.loads(lines[-1]) if lines else []
    for row in steps:
        bad = sorted({r['signal'] for r in row['records'] if not r['coherent']})
        print(row['name'], 'PASS' if row['passed'] else 'FAIL', 'settled' if row['settled'] else 'unsettled', bad, flush=True)
    result = dict(passed=process.returncode == 0 and len(steps) == 17 and all(r['passed'] for r in steps),
                  complete=len(steps) == 17, exit=process.returncode, cases=steps)
    (output / 'result.json').write_text(json.dumps(result, indent=2))
    shutil.rmtree(runtime)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
