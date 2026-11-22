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
import time

from guest_profile import ProcessIdentity, ProfileBlocked, activate_profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--engine', choices=('podman', 'docker'), required=True)
    parser.add_argument('--qt-webp', choices=('present', 'absent'), required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--cohort', choices=('all', 'profile', 'owner', 'chooser', 'boundary', 'worker'), default='all')
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
    with (artifacts / ('compositor-' + args.label + '.log')).open('x') as log:
        compositor = subprocess.Popen(['/usr/bin/sway', '--config', str(config)], env=environment,
                                      stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        captured = ProcessIdentity.read(compositor.pid)
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
            profile_path = workspace / ('ci-profile-' + args.label + '.json')
            profile = dict(version=2, mode='container-headless-wayland', name='image-decoding-ci', engine=args.engine,
                           containerId=Path('/etc/hostname').read_text().strip(), uid=os.getuid(), home=str(Path.home()), workspace=str(workspace),
                           workBase=str(workspace / 'work'), journalBase=str(workspace / 'artifacts'), runtimeBase=str(workspace / 'r'),
                           sessionRuntime=str(runtime), waylandDisplay=displays[0].name, compositor=captured.record())
            with profile_path.open('x') as output:
                json.dump(profile, output, indent=2)
            admitted = activate_profile(profile_path)
            admitted.prepare_roots()
            return run(args, workspace, admitted)
        finally:
            unexpected = compositor.poll() is not None
            if not unexpected:
                if ProcessIdentity.read(compositor.pid) != captured:
                    raise ProfileBlocked('owned compositor identity changed before termination')
                os.killpg(compositor.pid, signal.SIGTERM)
            code = compositor.wait(timeout=15)
            (artifacts / ('compositor-' + args.label + '.json')).write_text(json.dumps(
                dict(identity=captured.record(), exit=code, unexpected=unexpected), indent=2) + '\n')
            if unexpected:
                raise ProfileBlocked('private compositor exited before its consumers finished')


def run(args, workspace, admitted):
    profile_path = admitted.path
    source, plugins = workspace / 'shell', workspace / 'plugins'
    commands = {
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
    for name in ('profile', 'owner', 'chooser', 'boundary', 'worker') if args.cohort == 'all' else (args.cohort,):
        with (admitted.journal_base / (name + '-' + args.label + '.log')).open('x') as log:
            result = subprocess.run(['timeout', '1800', *commands[name]], stdout=log, stderr=subprocess.STDOUT, timeout=1830)
        rows.append(dict(cohort=name, exit=result.returncode, argv=commands[name]))
        print('CI_COHORT ' + name + ': ' + ('PASS' if result.returncode == 0 else 'FAIL'), flush=True)
    (admitted.journal_base / ('ci-' + args.label + '.json')).write_text(json.dumps(rows, indent=2) + '\n')
    return 0 if all(row['exit'] == 0 for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
