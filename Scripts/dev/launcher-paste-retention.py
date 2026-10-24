#!/usr/bin/env python3
"""A committed paste's native-release obligation outlives every other way it can end.

Private shell (fixtures/launcher-paste-retention.qml) with a real mapped layer
source holding its native keyboard. Its paste ends copy-only because a new
launcher session starts; the session is then finished again directly and by
deferred producer destruction. Until the compositor acknowledges the keyboard
release, the source must stay retained, visible and active and the old
session alive; after the genuine release it retires and the source unmaps.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import time
import zlib

from launcher_workspace import ROOT
from launcher_paste_support import profile_environment

PAYLOAD = 'K5 cancellation retention payload'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('flow', Path(__file__).with_name('launcher-flow-e2e.py'))
    flow = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(flow)
    flow.boundary()
    output, runtime = ROOT / 'evidence' / args.label, ROOT / 'runtime' / args.label
    output.mkdir()
    tree = runtime / 'tree'
    shutil.copytree(args.source, tree, symlinks=True)
    shell = tree / 'shell.qml'
    shell.write_text((Path(__file__).parent / 'fixtures/launcher-paste-retention.qml').read_text())
    env = profile_environment(runtime / 'profile', tree)
    # Quickshell's per-instance logs go to the runtime dir: keep them on the
    # task disk, not in the session's RAM-backed /run/user. A short path keeps
    # the IPC socket under the Unix socket length limit.
    run = ROOT / 'runtime' / ('r%06d' % (zlib.crc32(args.label.encode()) % 10**6))
    run.mkdir(mode=0o700)
    assert len(str(run / 'quickshell/by-id/0123456789/ipc.sock').encode()) < 104
    (run / 'wayland-1').symlink_to('/run/user/1000/wayland-1')
    env['XDG_RUNTIME_DIR'] = str(run)

    def ipc(method, check=True):
        return subprocess.run(['timeout', '10', 'qs', '-p', str(shell), 'ipc', 'call', 'pasteRetention', method],
                              env=env, capture_output=True, text=True, check=check, timeout=15)

    def state():
        return json.loads(ipc('state').stdout)

    def clipboard():
        return flow.command(['wl-paste', '--no-newline'], check=False).stdout

    steps = {}
    checks = {}
    result = dict(complete=False, steps=steps, checks=checks)
    try:
        with (output / 'shell.log').open('x') as log:
            process = subprocess.Popen(['timeout', '--kill-after=5', '60', 'qs', '-p', str(shell), '--no-color'],
                                       cwd=tree, env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                flow.wait(lambda: ipc('state', False).returncode == 0, 15)
                steps['owner'] = flow.wait(lambda: (s if s['active'] and s['hadKeyboard'] else None) if (s := state()) else None, 10)
                ipc('commit')
                steps['committed_held'] = flow.wait(lambda: (s if s['pending'] == 1 and s['retained'] else None) if (s := state()) else None)
                ipc('supersede')
                flow.wait(lambda: state()['pending'] == 0 and clipboard() == PAYLOAD)
                steps['copied_before_release'] = state()
                ipc('finishAgain')
                time.sleep(.15)
                steps['finished_again'] = state()
                ipc('destroyProducer')
                time.sleep(.15)  # deferred destruction finishes the session once more
                steps['producer_destroyed'] = state()
                for name in ('copied_before_release', 'finished_again', 'producer_destroyed'):
                    s = steps[name]
                    checks[name + '_retained'] = (s['retained'] and s['visible'] and s['active'] and s['oldAlive']
                                                  and s['retired'] is False and s['released'] is False and s['acknowledgements'] == 0)
                checks['copied_only'] = steps['copied_before_release']['queued'] == 0 and clipboard() == PAYLOAD
                ipc('releaseKeyboard')
                steps['released'] = flow.wait(lambda: (s if s['acknowledgements'] == 1 and not s['oldAlive'] else None) if (s := state()) else None, 10)
                time.sleep(.15)
                steps['after_release'] = state()
                s = steps['after_release']
                checks['retired_after_genuine_release'] = (s['acknowledgements'] == 1 and not s['oldAlive'] and not s['retained']
                                                           and not s['visible'] and s['sessions'] == 1)
                result['complete'] = True
            except Exception as error:
                result['error'] = repr(error)
                try:
                    steps['at_error'] = state()
                except Exception:
                    pass
            finally:
                ipc('exitControl', False)
                process.wait(timeout=10)
    finally:
        with tarfile.open(output / 'quickshell-runtime-logs.tar.gz', 'x:gz') as archive:
            for p in run.rglob('*'):
                if p.is_file() and not p.is_symlink() and p.suffix in ('.log', '.qslog'):
                    archive.add(p, arcname=str(p.relative_to(run)), recursive=False)
        shutil.rmtree(run)
        shutil.rmtree(runtime)
    result['passed'] = result['complete'] and len(checks) == 5 and all(checks.values())
    (output / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(dict(passed=result['passed'], checks=checks, error=result.get('error')), indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
