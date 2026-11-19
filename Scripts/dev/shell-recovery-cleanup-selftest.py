#!/usr/bin/env python3
"""Guest-only fault injection for recovery runner deadline and teardown."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--work', required=True, type=Path)
    ap.add_argument('--guest-profile', type=Path)
    args = ap.parse_args()
    assert Path('/sys/class/dmi/id/sys_vendor').read_text().strip() == 'QEMU', 'VM only'
    args.work.mkdir(parents=True, exist_ok=False)
    source = Path(__file__).resolve().parents[2]
    stub = args.work.resolve() / 'stub'
    stub.mkdir()
    (stub / 'ydotoold').write_text('''#!/usr/bin/env python3
import os, pathlib, time
root=pathlib.Path(os.environ['CLEANUP_TEST_ROOT'])
(root/'input-pid').write_text(str(os.getpid()))
pathlib.Path(os.environ['YDOTOOL_SOCKET']).touch()
time.sleep(180)
''')
    (stub / 'niri').write_text('''#!/usr/bin/env python3
import os, pathlib, signal, time
root=pathlib.Path(os.environ['CLEANUP_TEST_ROOT'])
(root/'restored').touch()
(root/'restore-pid').write_text(str(os.getpid()))
if os.environ['CLEANUP_TEST_MODE']=='timeout':
 signal.signal(signal.SIGTERM, signal.SIG_IGN)
 time.sleep(180)
''')
    for path in stub.iterdir():
        path.chmod(0o755)
    failures = []
    for mode, sig in (('deadline', signal.SIGTERM), ('timeout', signal.SIGINT)):
        root = args.work.resolve() / mode
        root.mkdir()
        (root / 'tmp').mkdir()
        env = dict(os.environ, PATH=f'{stub}:{os.environ["PATH"]}',
                   CLEANUP_TEST_ROOT=str(root), CLEANUP_TEST_MODE=mode, TMPDIR=str(root / 'tmp'))
        with (root / 'runner.log').open('w') as log:
            runner = subprocess.Popen([sys.executable, '-B', str(source / 'Scripts/dev/shell-recovery-regression.py'),
                                       '--work', str(root), '--inside', '--case', 'core-smoke',
                                       *(['--guest-profile', str(args.guest_profile)] if args.guest_profile else [])],
                                      env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            groups = {runner.pid}
            try:
                deadline = time.monotonic() + 15
                while not (root / 'input-pid').exists():
                    if runner.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError('runner did not reach owned child')
                    time.sleep(.05)
                child = int((root / 'input-pid').read_text())
                groups.add(os.getpgid(child))
                runner.send_signal(sig)
                runner.wait(timeout=25)
                receipt = json.loads((root / 'result.json').read_text()) if (root / 'result.json').exists() else None
                try:
                    os.kill(child, 0)
                    child_alive = True
                except ProcessLookupError:
                    child_alive = False
                errors = receipt.get('cleanup_errors', []) if receipt else []
                passed = (runner.returncode != 0 and receipt is not None and receipt['failure']
                          and (root / 'restored').exists() and not child_alive
                          and (bool(errors) if mode == 'timeout' else not errors))
                print(mode, 'PASS' if passed else 'FAIL',
                      dict(rc=runner.returncode, receipt=receipt, child_alive=child_alive), flush=True)
                if not passed:
                    failures.append(mode)
            finally:
                if (root / 'restore-pid').exists():
                    try:
                        groups.add(os.getpgid(int((root / 'restore-pid').read_text())))
                    except ProcessLookupError:
                        pass
                # Fault-injection cleanup owns only these synthetic process groups.
                for group in groups:
                    try:
                        os.killpg(group, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                runner.wait(timeout=5)
    print(f'{2-len(failures)}/2 passed')
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
