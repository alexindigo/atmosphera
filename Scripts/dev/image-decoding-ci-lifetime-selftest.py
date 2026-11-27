#!/usr/bin/env python3
"""Real TERM-resistant CI children, detached descendants and terminal receipts."""
import argparse
from dataclasses import replace
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
from tempfile import TemporaryDirectory
import time
from types import SimpleNamespace
from unittest.mock import Mock, patch

from guest_profile import ProcessIdentity, activate_profile, profile_argument


def publish_controls(scratch, output):
    for control in ('cohort', 'compositor'):
        source = scratch / control / 'artifacts'
        if not source.is_dir():
            continue
        destination = output / control
        destination.mkdir()
        for entry in sorted(source.iterdir()):
            if entry.is_symlink() or not entry.is_file():
                raise AssertionError(f'not a regular control receipt: {entry}')
            (destination / entry.name).write_bytes(entry.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    assert args.output == args.output.resolve() and args.output.is_relative_to(profile.journal_base)
    args.output.mkdir(mode=0o700)
    spec = importlib.util.spec_from_file_location('image_ci', Path(__file__).with_name('image-decoding-ci.py'))
    ci = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ci)
    cases = []
    identities = []
    failures = []

    def check(name, condition, **evidence):
        cases.append(dict(id=name, passed=bool(condition), **evidence))
        if not condition:
            failures.append(name)
        print('CASE ' + name + ': ' + ('PASS' if condition else 'FAIL'), flush=True)

    def alive(identity):
        try:
            actual = ProcessIdentity.read(identity.pid)
        except (FileNotFoundError, ProcessLookupError):
            return False
        return (actual.pid, actual.start, actual.uid) == (identity.pid, identity.start, identity.uid)

    def retire_controls():
        for identity in identities:
            if alive(identity):
                os.kill(identity.pid, signal.SIGKILL)

    # The nested lane owns mutable inputs and IPC under scratch, never under
    # the upload journal. Publish only its regular receipts and logs.
    scratch = TemporaryDirectory(prefix='life-', dir=profile.work_base)
    try:
        work = Path(scratch.name) / 'cohort'
        (work / 'shell/Scripts/dev').mkdir(parents=True)
        (work / 'artifacts').mkdir()
        marker = work / 'children.json'
        child = ('import os,signal,time,json; from pathlib import Path; '
                 'signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                 'Path(' + repr(str(work / 'detached.json')) + ').write_text(json.dumps(dict(pid=os.getpid()))); '
                 'time.sleep(60)')
        body = ('import os,signal,subprocess,sys,time,json; from pathlib import Path; '
                'signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                'p=subprocess.Popen([sys.executable,"-c",' + repr(child) + '],start_new_session=True); '
                'records=[dict(pid=i,start=Path(f"/proc/{i}/stat").read_text().rsplit(")",1)[1].split()[19],'
                'uid=os.getuid(),pgid=os.getpgid(i),argv=[]) for i in (os.getpid(),p.pid)]; '
                'Path(' + repr(str(marker)) + ').write_text(json.dumps(records)); '
                'time.sleep(60)')
        fixture = work / 'shell/Scripts/dev/guest-profile-modes-selftest.py'
        fixture.write_text(body)
        admitted = SimpleNamespace(path=args.guest_profile, journal_base=work / 'artifacts', work_base=work / 'work')
        cohort_args = SimpleNamespace(label='held', cohort='profile', qt_readers='present')
        real_run = subprocess.run

        def short_old_timeout(argv, **kwargs):
            if argv[:2] == ['timeout', '1800']:
                argv = ['timeout', '.5', *argv[2:]]
                kwargs['timeout'] = .9
            return real_run(argv, **kwargs)

        # The production deadlines are not changed. Only this explicit control
        # substitutes a short deadline, including on the old GNU-timeout path.
        with patch.object(ci, 'COHORT_SECONDS', .5, create=True), \
                patch.object(ci, 'TERMINATE_GRACE', .2, create=True), \
                patch.object(ci.subprocess, 'run', side_effect=short_old_timeout):
            error = None
            try:
                code = ci.run(cohort_args, work, admitted)
            except Exception as caught:
                code, error = None, repr(caught)
        children = json.loads(marker.read_text())
        identities.extend(ProcessIdentity(**row) for row in children)
        receipt = work / 'artifacts/ci-held.json'
        rows = json.loads(receipt.read_text()) if receipt.is_file() else []
        check('timeout-has-terminal-cohort-receipt', code == 1 and len(rows) == 1
              and rows[0].get('timeout') is True and rows[0]['exit'] != 0, error=error, rows=rows)
        check('timeout-reaps-detached-consumer', len(children) == 2 and not any(alive(i) for i in identities),
              identities=[i.record() for i in identities])
        retire_controls()

        if hasattr(ci, 'run_cohort'):
            success = ci.run_cohort([sys.executable, '-c', 'print("cohort-result")'],
                                    work / 'artifacts/ordinary.log', seconds=5, grace=.2)
            check('ordinary-cohort-records-success', success['exit'] == 0 and not success['timeout']
                  and success['cleanupComplete'], receipt=success)
            # The real fixture waits for its private consumer group before it
            # can exit. Keep an orphan live until EOF, then require the outer
            # subreaper to reap it while the fixture itself is still running.
            settle = """
import os, subprocess, sys
from image_decoding_workspace import settle_fixture_session
worker = 'import os; child = os.fork(); os._exit(0) if child else os.read(0, 1)'
with subprocess.Popen([sys.executable, '-c', worker], stdin=subprocess.PIPE, start_new_session=True) as proc:
    assert proc.wait(timeout=2) == 0
    try:
        settle_fixture_session(proc, timeout=.1)
    except ValueError:
        pass
    else:
        raise AssertionError('settled with a live orphan')
    proc.stdin.close()
    settle_fixture_session(proc)
"""
            argv = [sys.executable, '-B', '-c', 'import sys; sys.path.insert(0, sys.argv[1]);' + settle,
                    str(Path(__file__).resolve().parent)]
            settled = ci.run_cohort(argv, work / 'artifacts/adopted.log', seconds=6, grace=.2)
            check('live-orphan-blocks-and-is-reaped-after-eof', settled['exit'] == 0 and settled['cleanupComplete'],
                  receipt=settled, stderr=(work / 'artifacts/adopted.stderr.log').read_text())
            with patch.object(ci.subprocess, 'Popen', side_effect=OSError('controlled spawn refusal')):
                failed = ci.run(SimpleNamespace(label='spawn', cohort='profile', qt_readers='present'), work, admitted)
            rows = json.loads((work / 'artifacts/ci-spawn.json').read_text())
            check('spawn-refusal-records-failure', failed == 1 and rows[0]['exit'] == 125
                  and 'controlled spawn refusal' in rows[0]['error'], rows=rows)

            # A successful direct command must not leave detached work either.
            # Keep the child's TERM resistance/long lifetime unchanged.
            fixture.write_text(body.rsplit('time.sleep(60)', 1)[0] + 'time.sleep(.1)')
            detached = ci.run_cohort([sys.executable, str(fixture)], work / 'artifacts/detached.log', seconds=5, grace=.2)
            children = json.loads(marker.read_text())
            captured = [ProcessIdentity(**row) for row in children]
            identities.extend(captured)
            check('ordinary-exit-reaps-detached-consumer', detached['exit'] == 0 and detached['cleanupComplete']
                  and len(captured) == 2 and not any(alive(i) for i in captured), receipt=detached,
                  identities=[i.record() for i in captured])

            fake = Mock(pid=os.getpid() + 100000)
            fake.poll.return_value = None
            launch_identity = ProcessIdentity(fake.pid, '12345', os.getuid(), fake.pid, ())
            argv = ('/usr/bin/sway', '--config', '/private/sway.conf')
            ready_identity = replace(launch_identity, argv=argv)
            with patch.object(ci.ProcessIdentity, 'read', return_value=launch_identity):
                owned = ci.CompositorOwnership(fake)
            with patch.object(ci.ProcessIdentity, 'read', return_value=ready_identity):
                check('exec-argv-settles-only-at-ready', owned.ready(argv) == ready_identity)
            for field, value in (('pid', fake.pid + 1), ('start', 'changed'), ('uid', os.getuid() + 1), ('pgid', fake.pid + 1)):
                with patch.object(ci.ProcessIdentity, 'read', return_value=replace(ready_identity, **{field: value})), \
                        patch.object(ci.os, 'killpg') as kill:
                    refused = []
                    for action in (lambda: owned.ready(argv), lambda: owned.terminate(signal.SIGKILL)):
                        try:
                            action()
                        except ci.ProfileBlocked:
                            refused.append(True)
                    check('changed-' + field + '-never-signalled', len(refused) == 2 and not kill.called)
            with patch.object(ci.ProcessIdentity, 'read', return_value=replace(ready_identity, argv=('diagnostic-change',))), \
                    patch.object(ci.os, 'killpg') as kill:
                owned.terminate(signal.SIGKILL)
                check('escalation-uses-kernel-not-argv', kill.call_args.args == (fake.pid, signal.SIGKILL))
            with patch.object(ci.ProcessIdentity, 'read', return_value=replace(ready_identity, argv=('foreign',))):
                try:
                    owned.ready(argv)
                except ci.ProfileBlocked:
                    refused = True
                else:
                    refused = False
                check('readiness-still-requires-exact-argv', refused)

        # Execute main's actual finally block with a real TERM-resistant child.
        # Only container detection/profile admission and the Sway executable
        # are replaced; the runner's lifetime implementation is untouched.
        work = Path(scratch.name) / 'compositor'
        work.mkdir()
        made = []
        sockets = []
        real_popen, real_read = subprocess.Popen, ProcessIdentity.read
        cli = ['ci', '--workspace', str(work), '--engine', 'podman',
               '--label', 'held', '--cohort', 'profile']
        marker_path = work / 'ready'
        body = ('import signal,time; from pathlib import Path; '
                'signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                'Path(' + repr(str(marker_path)) + ').touch(); time.sleep(60)')

        def launch(argv, **kwargs):
            process = real_popen([sys.executable, '-c', body], **kwargs)
            made.append(process)
            real_wait = process.wait
            process.wait = lambda timeout=None: real_wait(timeout=min(timeout, .2) if timeout else timeout)
            deadline = time.monotonic() + 5
            while not marker_path.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            assert marker_path.exists(), 'control did not become TERM-resistant'
            identities.append(real_read(process.pid))
            endpoint = socket.socket(socket.AF_UNIX)
            endpoint.bind(str(Path(kwargs['env']['XDG_RUNTIME_DIR']) / 'wayland-1'))
            sockets.append(endpoint)
            return process

        def detected(argv, **kwargs):
            if argv[:2] == ['systemd-detect-virt', '--container']:
                return subprocess.CompletedProcess(argv, 0, 'podman\n', '')
            return real_run(argv, **kwargs)

        def identity(pid):
            actual = real_read(pid)
            if made and pid == made[-1].pid:
                return replace(actual, argv=('/usr/bin/sway', '--config', str(work / 'r/s-held/sway.conf')))
            return actual

        real_is_file = Path.is_file
        try:
            with patch.object(sys, 'argv', cli), patch.object(ci.subprocess, 'Popen', side_effect=launch), \
                    patch.object(ci.subprocess, 'run', side_effect=detected), \
                    patch.object(ci.ProcessIdentity, 'read', side_effect=identity), \
                    patch.object(ci, 'activate_profile', side_effect=RuntimeError('controlled profile refusal')), \
                    patch.object(ci, 'TERMINATE_GRACE', .2, create=True), \
                    patch.object(Path, 'is_file', lambda p: True if p == Path('/run/.containerenv') else real_is_file(p)):
                try:
                    ci.main()
                except Exception as caught:
                    error = repr(caught)
            receipt = work / 'artifacts/compositor-held.json'
            row = json.loads(receipt.read_text()) if receipt.is_file() else {}
            check('compositor-escalates-reaps-and-records', made[0].poll() is not None
                  and row.get('escalated') is True and row.get('exit') == -signal.SIGKILL, error=error, receipt=row)
            check('compositor-preserves-primary-refusal', error == "RuntimeError('controlled profile refusal')", error=error)
        finally:
            for process in made:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
            for endpoint in sockets:
                endpoint.close()
        profile.verify()
    finally:
        primary = sys.exception()
        errors = []
        for action in (retire_controls, lambda: publish_controls(Path(scratch.name), args.output), scratch.cleanup):
            try:
                action()
            except Exception as error:
                errors.append(error)
        try:
            if primary is None and not errors:
                check('compositor-receipt-reopens-without-runtime',
                      json.loads((args.output / 'compositor/compositor-held.json').read_text()) == row
                      and not (args.output / 'compositor/r').exists())
            result = dict(passed=primary is None and not errors and not failures, cases=cases, failures=failures,
                          captured=[i.record() for i in identities])
            (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        except Exception as error:
            errors.append(error)
        if errors:
            if primary is None:
                raise ExceptionGroup('Lifetime evidence finalization failed', errors)
            for error in errors:
                primary.add_note('Lifetime evidence finalization failed: ' + repr(error))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
