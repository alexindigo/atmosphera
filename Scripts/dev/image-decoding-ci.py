#!/usr/bin/env python3
"""Run real image consumers in a container-private headless Wayland session."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
from tempfile import TemporaryDirectory
import time

from guest_profile import ProcessIdentity, ProfileBlocked, activate_profile


COHORT_SECONDS = 1800
TERMINATE_GRACE = 10


class CompositorOwnership:
    """Kernel launch ownership is stable across exec; argv is readiness data."""
    def __init__(self, process):
        self.process = process
        self.launch = ProcessIdentity.read(process.pid)
        if self.launch.uid != os.getuid() or self.launch.pgid != process.pid or self.launch.pgid == os.getpgrp():
            raise ProfileBlocked('owned compositor must be a private account/session leader')

    @staticmethod
    def kernel_identity(identity):
        return identity.pid, identity.start, identity.uid, identity.pgid

    def verify(self):
        observed = ProcessIdentity.read(self.process.pid)
        if self.kernel_identity(observed) != self.kernel_identity(self.launch):
            raise ProfileBlocked('owned compositor kernel identity changed')
        return observed

    def ready(self, argv):
        observed = self.verify()
        if observed.argv != tuple(argv):
            raise ProfileBlocked('socket-ready compositor does not match expected Sway command')
        return observed

    def terminate(self, signum=signal.SIGTERM):
        if self.process.poll() is None:
            self.verify()
            try:
                os.killpg(self.launch.pgid, signum)
            except ProcessLookupError:
                pass

    def finish(self, path, ready):
        unexpected = self.process.poll() is not None
        row = dict(launchIdentity=self.launch.record(), identity=ready.record() if ready else None,
                   exit=self.process.returncode, unexpected=unexpected, escalated=False, cleanupComplete=False)
        try:
            self.terminate()
            try:
                row['exit'] = self.process.wait(timeout=TERMINATE_GRACE)
            except subprocess.TimeoutExpired:
                row['escalated'] = True
                self.terminate(signal.SIGKILL)
                row['exit'] = self.process.wait(timeout=TERMINATE_GRACE)
            row['cleanupComplete'] = True
        except Exception as error:
            row['error'] = repr(error)
            raise
        finally:
            path.write_text(json.dumps(row, indent=2) + '\n')
        if unexpected:
            raise ProfileBlocked('private compositor exited before its consumers finished')


def run_cohort(argv, log, seconds=COHORT_SECONDS, grace=TERMINATE_GRACE):
    """The existing subreaper owns even consumers that create new sessions.

    GNU timeout provides TERM then KILL for the direct cohort group. The image
    command supervisor also retires and reaps detached descendants after either
    ordinary completion or timeout. Its stdin lifetime belongs only to us.
    """
    result_path = log.with_suffix('.supervisor.json')
    identity_path = log.with_suffix('.child.json')
    supervisor = Path(__file__).resolve().parents[1] / 'python/src/images/owned_command.py'
    # Foreground mode keeps timeout alive to report 137 when its child needs
    # KILL. The supervisor, not timeout, owns the complete process lifetime.
    spec = dict(argv=['timeout', '--foreground', '--kill-after=' + str(grace), str(seconds), *argv],
                timeout=seconds + grace + 1, stdout=str(log), stderr=str(log.with_suffix('.stderr.log')),
                identity=str(identity_path), result=str(result_path))
    row = dict(exit=125, timeout=False, cleanupComplete=False, supervisorResult=str(result_path))
    try:
        with log.with_suffix('.supervisor.log').open('x') as diagnostics:
            process = subprocess.Popen([sys.executable, '-B', str(supervisor), json.dumps(spec)],
                                       stdin=subprocess.PIPE, stdout=diagnostics, stderr=subprocess.STDOUT)
            try:
                process.wait(timeout=seconds + grace + 15)
            except subprocess.TimeoutExpired:
                row['timeout'] = True
            finally:
                process.stdin.close()
                process.wait(timeout=10)
        result = json.loads(result_path.read_text())
        row.update(exit=result['exit'], timeout=row['timeout'] or result['timeout'] or result['exit'] in (124, 137),
                   cleanupComplete=process.returncode == 0, supervisorExit=process.returncode,
                   child=result['child'])
        if row['timeout'] and row['exit'] == 0:
            row['exit'] = 124
        if not row['cleanupComplete'] and row['exit'] == 0:
            row['exit'] = 125
    except Exception as error:
        row.update(exit=125, error=repr(error))
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--engine', choices=('podman', 'docker'), required=True)
    parser.add_argument('--qt-webp', choices=('present', 'absent'), required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--cohort', choices=('all', 'lifetime', 'profile', 'owner', 'chooser', 'boundary', 'worker'), default='all')
    args = parser.parse_args()
    workspace = args.workspace
    marker = Path('/run/.containerenv' if args.engine == 'podman' else '/.dockerenv')
    detected = subprocess.run(['systemd-detect-virt', '--container'], capture_output=True, text=True, timeout=10)
    if not marker.is_file() or detected.returncode or detected.stdout.strip() != args.engine:
        raise ProfileBlocked('CI entry point must run inside the explicit container engine')
    if os.getuid() == 0 or workspace != workspace.resolve() or not workspace.is_relative_to(Path.home()) or workspace == Path.home():
        raise ProfileBlocked('non-root owned workspace beneath container home required')
    if not re.fullmatch('[a-z0-9-]+', args.label):
        raise ValueError('label must contain lowercase letters, digits and hyphens')
    if not workspace.is_dir() or workspace.stat().st_uid != os.getuid():
        raise ProfileBlocked('bind-mounted workspace is not owned by the container account')
    # Each invocation owns its scratch; the journal survives both pass and fail.
    with TemporaryDirectory(prefix='work-', dir=workspace) as work:
        return run_lane(args, workspace, Path(work))


def run_lane(args, workspace, work):
    (workspace / 'tmp').mkdir(exist_ok=True)
    os.environ['TMPDIR'] = str(workspace / 'tmp')
    runtime = workspace / 'r' / ('s-' + args.label)
    runtime.mkdir(parents=True, mode=0o700)
    artifacts = workspace / 'artifacts'
    artifacts.mkdir(exist_ok=True)
    config = runtime / 'sway.conf'
    config.write_text('output * mode 1600x1000\nxwayland disable\ndefault_border none\n')
    environment = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), WLR_BACKENDS='headless', WLR_RENDERER='pixman',
                       WLR_LIBINPUT_NO_DEVICES='1')
    for key in ('WAYLAND_DISPLAY', 'DISPLAY', 'SWAYSOCK', 'NIRI_SOCKET'):
        environment.pop(key, None)
    argv = ['/usr/bin/sway', '--config', str(config)]
    with (artifacts / ('compositor-' + args.label + '.log')).open('x') as log:
        compositor = subprocess.Popen(argv, env=environment,
                                      stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        owned = CompositorOwnership(compositor)
        captured = None
        try:
            deadline = time.monotonic() + 20
            displays = []
            while compositor.poll() is None and time.monotonic() < deadline:
                displays = [p for p in runtime.glob('wayland-*') if p.is_socket()]
                if len(displays) == 1:
                    break
                time.sleep(.05)
            if compositor.poll() is not None or len(displays) != 1:
                raise ProfileBlocked('private headless Sway did not establish its Wayland socket')
            captured = owned.ready(argv)
            profile_path = workspace / ('ci-profile-' + args.label + '.json')
            profile = dict(version=2, mode='container-headless-wayland', name='image-decoding-ci', engine=args.engine,
                           containerId=Path('/etc/hostname').read_text().strip(), uid=os.getuid(), home=str(Path.home()), workspace=str(workspace),
                           workBase=str(work), journalBase=str(workspace / 'artifacts'), runtimeBase=str(workspace / 'r'),
                           sessionRuntime=str(runtime), waylandDisplay=displays[0].name, compositor=captured.record())
            with profile_path.open('x') as output:
                json.dump(profile, output, indent=2)
            admitted = activate_profile(profile_path)
            admitted.prepare_roots()
            return run(args, workspace, admitted)
        finally:
            primary = sys.exception()
            try:
                owned.finish(artifacts / ('compositor-' + args.label + '.json'), captured)
            except Exception as error:
                if primary is None:
                    raise
                primary.add_note('compositor cleanup failed: ' + repr(error))


def run(args, workspace, admitted):
    profile_path = admitted.path
    source, plugins = workspace / 'shell', workspace / 'plugins'
    commands = {
        'lifetime': [sys.executable, '-B', str(source / 'Scripts/dev/image-decoding-ci-lifetime-selftest.py'),
                     '--guest-profile', str(profile_path), '--output', str(admitted.journal_base / ('lifetime-' + args.label))],
        'profile': [sys.executable, '-B', str(source / 'Scripts/dev/guest-profile-modes-selftest.py'),
                    '--guest-profile', str(profile_path), '--output', str(admitted.journal_base / ('profile-' + args.label))],
        'boundary': [sys.executable, '-B', str(source / 'Scripts/dev/image-decoding-boundary-check.py'),
                     '--source', str(source), '--plugins', str(plugins), '--selftest',
                     '--manifest', str(source / 'Scripts/dev/fixtures/image-decoding/consumers.json'),
                     '--report', str(admitted.journal_base / ('boundary-' + args.label + '.json'))],
        'worker': [sys.executable, '-B', str(source / 'Scripts/dev/image-decoding-worker-tests.py'),
                   '--guest-profile', str(profile_path), '--source', str(source),
                   '--work-root', str(admitted.work_base / ('worker-' + args.label)),
                   '--output', str(admitted.journal_base / ('worker-' + args.label))],
    }
    for case in ('owner', 'chooser'):
        commands[case] = [sys.executable, '-B', str(source / 'Scripts/dev/image-decoding-regression.py'),
                          '--guest-profile', str(profile_path), '--source', str(source), '--plugins', str(plugins),
                          '--case', case, '--qt-webp', args.qt_webp,
                          '--work-root', str(admitted.work_base / (case + '-' + args.label)),
                          '--output', str(admitted.journal_base / (case + '-' + args.label))]
    rows = []
    for name in ('lifetime', 'profile', 'owner', 'chooser', 'boundary', 'worker') if args.cohort == 'all' else (args.cohort,):
        result = run_cohort(commands[name], admitted.journal_base / (name + '-' + args.label + '.log'),
                            seconds=COHORT_SECONDS, grace=TERMINATE_GRACE)
        rows.append(dict(cohort=name, argv=commands[name], **result))
        (admitted.journal_base / ('ci-' + args.label + '.json')).write_text(json.dumps(rows, indent=2) + '\n')
        print('CI_COHORT ' + name + ': ' + ('PASS' if result['exit'] == 0 else 'FAIL'), flush=True)
    return 0 if all(row['exit'] == 0 for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
