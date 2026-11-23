#!/usr/bin/env python3
"""Actual Hermes bridge/PTY cancellation and parent-death proof, with inert SSH."""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import time

from fixture_resources import FixtureResources
from guest_profile import activate_profile, profile_argument

STUB = '''#!/usr/bin/env python3
import json, os
from pathlib import Path
import signal, sys, time
case = Path(os.environ['HERMES_HELPER_CASE'])
row = dict(pid=os.getpid(), start=Path('/proc/self/stat').read_text().split(') ', 1)[1].split()[19], pgid=os.getpgrp(), argv=sys.argv[1:])
(case / 'child.json').write_text(json.dumps(row))
def stop(signum, frame):
 (case / 'child-stopped.json').write_text(json.dumps(dict(signal=signum)))
 raise SystemExit(0)
signal.signal(signal.SIGTERM, stop)
print('INERT_REMOTE_PTY_OUTPUT', flush=True)
while True: time.sleep(0.02)
'''
SSH_ARGV = ['-tt', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ServerAliveInterval=30', '-p', '2222', 'synthetic-user@inert.invalid', 'TERM=xterm-256color COLORTERM=truecolor hermes']


def state(row):
    path = Path('/proc') / str(row['pid']) / 'stat'
    try: parts = path.read_text().split(') ', 1)[1].split()
    except FileNotFoundError: return 'absent'
    return 'reused-pid' if parts[19] != row['start'] else parts[0]


def active(row): return state(row) not in ('absent', 'reused-pid', 'Z', 'X')
def absent(row): return state(row) in ('absent', 'reused-pid')
def check(ok, message):
    if not ok: raise AssertionError(message)


def cleanup(row):
    if active(row):
        check(os.getpgid(row['pid']) == row['pgid'] == row['pid'], 'owned inert child identity changed')
        os.killpg(row['pgid'], signal.SIGTERM)
    deadline = time.monotonic() + 3
    while not absent(row) and time.monotonic() < deadline: time.sleep(0.02)
    check(absent(row), 'owned inert child identity not absent after cleanup')


@receipt_run
def run(args, helper, mode):
    case = args.work_root / mode; out = args.output / mode; case.mkdir(); out.mkdir()
    (case / 'bin').mkdir(); (case / 'home').mkdir()
    executable = case / 'bin/ssh'; executable.write_text(STUB); executable.chmod(0o755)
    env = dict(os.environ, HOME=str(case / 'home'), PATH=str(case / 'bin') + ':' + os.environ['PATH'], HERMES_HELPER_CASE=str(case))
    result = dict(mode=mode)
    with FixtureResources() as resources:
        resources.defer(lambda: stage_receipt(out / 'result.json', result))

        def cleanup_owned_child():
            receipt = case / 'child.json'
            if receipt.is_file():
                child = json.loads(receipt.read_text())
                cleanup(child)
                result['ownedCharacterizerCleanup'] = state(child)

        resources.defer(cleanup_owned_child)
        try:
            return characterize(args, helper, mode, case, env, resources, result)
        except BaseException as error:
            result.update(status='FAIL', assertion=str(error))
            raise


def characterize(args, helper, mode, case, env, resources, result):
        logs = []
        command = ['python3', '-B', str(helper)]
        if mode == 'parent-race': command += ['--owned-ssh-child', '1', 'ssh', *SSH_ARGV]
        proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, start_new_session=True, bufsize=0)
        for stream in (proc.stdin, proc.stdout, proc.stderr): resources.defer(stream.close)

        def capture_stderr():
            if proc.poll() is not None:
                result['stderr'] = proc.stderr.read().decode(errors='replace')

        def stop():
            if proc.poll() is None: proc.terminate()

        resources.defer(capture_stderr)
        resources.defer(proc.wait, timeout=8)
        resources.defer(stop)
        if mode == 'parent-race':
            deadline = time.monotonic() + 5
            while proc.poll() is None and not (case / 'child.json').exists() and time.monotonic() < deadline: time.sleep(0.02)
            check(not (case / 'child.json').exists(), 'parent-race refused before SSH exec')
            check(proc.wait(timeout=3) == -signal.SIGKILL, 'parent-race kills mismatched child')
            result.update(status='PASS', helperExit=proc.returncode, sshNeverExecuted=True)
            return result
        proc.stdin.write((json.dumps(dict(type='connect', host='inert.invalid', port=2222, user='synthetic-user', password='', rows=32, cols=80)) + '\n').encode()); proc.stdin.flush()
        selector = selectors.DefaultSelector()
        resources.defer(selector.close)
        selector.register(proc.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + 10; connected = False
        while time.monotonic() < deadline:
            if not selector.select(0.1): continue
            line = proc.stdout.readline()
            if not line: break
            row = json.loads(line); logs.append(row)
            if row.get('status') == 'connected': connected = True; break
        selector.close()
        check(connected and (case / 'child.json').is_file(), 'actual inert SSH PTY output and connected status')
        child = json.loads((case / 'child.json').read_text())
        check(active(child) and child['pgid'] == child['pid'] and child['argv'] == SSH_ARGV, 'actual SSH child/group/literal auth argv')
        if mode == 'disconnect': proc.stdin.write(b'{"type":"disconnect"}\n'); proc.stdin.flush()
        elif mode == 'owner-closed': proc.stdin.close()
        elif mode == 'sigterm': proc.terminate()
        elif mode == 'sigkill': proc.kill()
        code = proc.wait(timeout=8); time.sleep(0.15)
        survived = active(child)
        result.update(helperExit=code, childSurvivedHelperExit=survived, childStateAfterHelperExit=state(child), childIdentity=child, actualPtyOutput=logs)
        stop = case / 'child-stopped.json'
        result['childStopReceipt'] = json.loads(stop.read_text()) if stop.exists() else None
        if args.original_red:
            check(survived == (mode in ('sigterm', 'sigkill')), 'original SSH orphan class reproduced')
        else:
            if mode == 'sigterm': check(code == 0, 'helper SIGTERM uses clean termination')
            check(not survived, 'SSH child survived helper ' + mode.upper())
            deadline = time.monotonic() + 3
            while not absent(child) and time.monotonic() < deadline: time.sleep(0.02)
            check(absent(child), 'SSH child identity absent after helper ' + mode.upper())
            if mode != 'sigkill': check(code == 0 and result['childStopReceipt'] == dict(signal=15), 'normal stop joins SSH process group')
        result['status'] = 'RED_REPRODUCED' if args.original_red and mode in ('sigterm', 'sigkill') else 'PASS'
        return result


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__); profile_argument(parser)
    for key in ('source', 'plugins', 'work-root', 'output'): parser.add_argument('--' + key, type=Path, required=True)
    oracle = parser.add_mutually_exclusive_group()
    oracle.add_argument('--original-red', action='store_true')
    oracle.add_argument('--negative-control', choices=('parent-death', 'sigterm', 'parent-race'))
    args = parser.parse_args(); profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-hermes-helper-regression.py': parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent): parser.error('fresh owned guest roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); args.work_root.mkdir(); args.output.mkdir()
        original = args.plugins / 'hermes-ssh-chat/helpers/hermes_ssh_bridge.py'
        helper = args.work_root / 'hermes_ssh_bridge.py'; shutil.copy2(original, helper)
        wanted = None
        if args.negative_control:
            old, new, wanted = {
                'parent-death': ('    bind_parent_death(expected_parent)\n    os.execvp', '    expected_parent = expected_parent\n    os.execvp', 'SSH child survived helper SIGKILL'),
                'sigterm': ('signal.signal(signal.SIGTERM, stop_requested)', 'signal.signal(signal.SIGTERM, signal.SIG_DFL)', 'helper SIGTERM uses clean termination'),
                'parent-race': ('if os.getppid() != expected_parent:', 'if False:', 'parent-race refused before SSH exec')
            }[args.negative_control]
            text = helper.read_text(); check(text.count(old) == 1, 'review Hermes helper control anchor'); helper.write_text(text.replace(old, new))
        (args.output / 'inputs.json').write_text(json.dumps(dict(source=str(original), sourceSha256=hashlib.sha256(original.read_bytes()).hexdigest(), driverSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), inertSshSha256=hashlib.sha256(STUB.encode()).hexdigest(), control=args.negative_control), indent=2) + '\n')
        results = []
        modes = ('disconnect', 'sigterm', 'sigkill') if args.original_red else ('disconnect', 'sigterm', 'sigkill', 'owner-closed', 'parent-race')
        try:
            for mode in modes: results.append(run(args, helper, mode))
        except AssertionError as error:
            if not wanted or str(error) != wanted: raise
            report = dict(status='PASS', rejectedAt=wanted, control=args.negative_control, physicalProof=False)
        else:
            check(not wanted, 'Hermes helper control escaped')
            report = dict(status='PASS', originalRed=args.original_red, rows=results, realSshOrNetwork=False, helperOnly=True, completeMemberAcceptance=False)
        stage_receipt(args.output / 'result.json', report); print(json.dumps(report))


if __name__ == '__main__': main()
