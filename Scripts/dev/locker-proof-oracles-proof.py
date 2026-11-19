#!/usr/bin/env python3
"""Guest-only rejecting controls for supervision and evidence admission."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

from locker_test_support import require_guest, run, supervise_proof
from locker_proof_oracles import authenticated_unlocks, process_report_commit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--baseline-support', type=Path)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    results = []
    def check(name, action):
        try:
            action()
        except Exception as error:
            row = dict(case=name, passed=False, error=repr(error))
        else:
            row = dict(case=name, passed=True)
        results.append(row)
        print(json.dumps(row), flush=True)
    def rejected(action):
        try:
            action()
        except AssertionError:
            return
        raise AssertionError('bad evidence was accepted')
    support = args.baseline_support or source / 'Scripts/dev/locker_test_support.py'
    def optimized():
        marker = work / 'optimized-side-effect'
        command = 'import runpy; from pathlib import Path; runpy.run_path(' + repr(str(support)) + '); Path(' + repr(str(marker)) + ').touch()'
        result = subprocess.run([sys.executable, '-O', '-c', command], capture_output=True, text=True, timeout=10)
        (work / 'optimized-output.txt').write_text(result.stdout + result.stderr)
        assert result.returncode != 0 and not marker.exists(), 'optimized entry reached workload side effect'
    check('optimized-entry-before-side-effects', optimized)
    def cancelled(forced=False):
        name = 'forced' if forced else 'cooperative'
        marker = work / (name + '-cleaned')
        child = ('import signal,time; from pathlib import Path\n'
            + ('signal.signal(signal.SIGTERM, signal.SIG_IGN)\n' if forced else
               'def cancel(*args): raise KeyboardInterrupt()\nsignal.signal(signal.SIGTERM, cancel)\n')
            + 'try: time.sleep(5)\nfinally: Path(' + repr(str(marker)) + ').touch()\n')
        command = [sys.executable, '-c', child]
        receipt = work / (name + '-supervision.json')
        with (work / (name + '.log')).open('w') as log:
            if args.baseline_support:
                try:
                    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=.3)
                except subprocess.TimeoutExpired:
                    pass
                assert marker.exists(), 'old subprocess.run timeout killed child before finally'
                return
            result = supervise_proof(command, log, .3, receipt, source=source, recovery_root=work, cleanup_timeout=.3)
        row = json.loads(receipt.read_text())
        assert result.returncode != 0 and row['timedOut'] and row['forcedTermination'] == forced
        assert marker.exists() != forced
        assert 'guestState' in row and row['recoveryFiles'] == []
        assert row['cleanupCompleted'] is False, 'controller exit was promoted to verified cleanup'
    check('cooperative-timeout-runs-finally', cancelled)
    if not args.baseline_support:
        check('forced-controller-stop-retains-guest-state', lambda: cancelled(True))
    success = dict(kind='journal', invocation='holder', pid='123', sourceMonotonic=2,
        message='LOCKER_PAM_SUCCESS {"pid":123}')
    unlock = dict(kind='journal', invocation='holder', pid='123', sourceMonotonic=3,
        message='-> ext_session_lock_v1#7.unlock_and_destroy()')
    check('pam-before-native-unlock', lambda: authenticated_unlocks([success, unlock], 1))
    check('same-timestamp-ordered-pam-before-unlock', lambda: authenticated_unlocks(
        [dict(success, sourceMonotonic=3), unlock], 1))
    second = dict(unlock, sourceMonotonic=5, message='-> ext_session_lock_v1#8.unlock_and_destroy()')
    check('pam-per-native-unlock', lambda: authenticated_unlocks(
        [success, unlock, dict(success, sourceMonotonic=4), second], 2))
    check('reject-one-pam-two-unlocks', lambda: rejected(lambda: authenticated_unlocks(
        [success, unlock, second], 2)))
    check('reject-same-timestamp-pam-after-unlock', lambda: rejected(lambda: authenticated_unlocks(
        [unlock, dict(success, sourceMonotonic=3)], 1)))
    for name, events in (
            ('no-pam', [unlock]),
            ('pam-after-unlock', [dict(success, sourceMonotonic=4), unlock]),
            ('foreign-invocation', [dict(success, invocation='other'), unlock]),
            ('foreign-client', [dict(success, pid='456'), unlock]),
            ('missing-client', [dict(success, pid=''), dict(unlock, pid='')])):
        check('reject-' + name, lambda events=events: rejected(lambda: authenticated_unlocks(events, 1)))
    target = '/run/user/1000/atmosphera-lock/client.report.json'
    temporary = '/run/user/1000/atmosphera-lock/client.report.json.ABC'
    synced = (2.0, '2.0 fdatasync(9<' + temporary + '>) = 0')
    rename = (3.0, '3.0 rename("' + temporary + '", "' + target + '") = 0')
    check('process-surviving-report-commit', lambda: process_report_commit([synced, rename], target, 1, 4))
    anonymous = (2.0, '2.0 fdatasync(9</run/user/1000/atmosphera-lock/#123>(deleted)) = 0')
    link = (2.5, '2.5 linkat(AT_FDCWD, "/proc/self/fd/9", AT_FDCWD, "' + temporary + '", AT_SYMLINK_FOLLOW) = 0')
    check('qt-anonymous-file-materialized-before-rename',
        lambda: process_report_commit([anonymous, link, rename], target, 1, 4))
    check('qt-decoded-working-directory-descriptors', lambda: process_report_commit(
        [anonymous, (link[0], link[1].replace('AT_FDCWD,', 'AT_FDCWD</home/tester>,')), rename], target, 1, 4))
    for name, trace in (
            ('missing-materialization', [anonymous, rename]),
            ('failed-materialization', [anonymous, (2.5, link[1].replace('= 0', '= -1 EIO')), rename]),
            ('different-materialized-fd', [anonymous, (2.5, link[1].replace('/fd/9', '/fd/8')), rename]),
            ('closed-materialized-fd', [anonymous, (2.2, '2.2 close(9) = 0'), link, rename]),
            ('foreign-materialization-process', [(2, '[trace=other] ' + anonymous[1]), link, rename])):
        check('reject-' + name, lambda trace=trace: rejected(lambda: process_report_commit(trace, target, 1, 4)))
    for name, trace in (
            ('missing-file-sync', [rename]),
            ('failed-file-sync', [(2, synced[1].replace('= 0', '= -1 EIO')), rename]),
            ('other-file-sync', [(2, synced[1].replace(temporary, '/other')), rename]),
            ('failed-rename', [synced, (3, rename[1].replace('= 0', '= -1 EIO'))]),
            ('teardown-before-commit', [synced, (5, rename[1])])):
        check('reject-' + name, lambda trace=trace: rejected(lambda: process_report_commit(trace, target, 1, 4)))
    runtime = run(['findmnt', '-T', '/run/user/1000', '-n', '-o', 'FSTYPE']).stdout.strip()
    (work / 'report-contract.json').write_text(json.dumps(dict(runtimeFilesystem=runtime,
        scope='same-boot process survival; not power-loss or reboot persistence',
        directorySyncRequired=False), indent=2))
    (work / 'result.json').write_text(json.dumps(results, indent=2))
    return 0 if all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
