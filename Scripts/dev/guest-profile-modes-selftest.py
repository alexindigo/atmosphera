#!/usr/bin/env python3
"""Qualify explicit VM/container profile admission in the actual target."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from guest_profile import (GuestProfile, HeadlessWaylandProfile, ProcessIdentity, ProfileBlocked,
                           activate_profile, current_profile, profile_argument)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    if args.output.exists() or args.output != args.output.resolve() or not args.output.is_relative_to(profile.journal_base):
        raise ProfileBlocked('fresh canonical profile-journal output required')
    args.output.mkdir(parents=True, mode=0o700)
    data = json.loads(args.guest_profile.read_bytes())
    results = []

    def check(name, condition):
        assert condition, name
        results.append(dict(id=name, status='PASS'))
        print('CASE ' + name + ': PASS', flush=True)

    def refused(name, call):
        try:
            call()
        except ProfileBlocked:
            check(name, current_profile() is profile)
        else:
            raise AssertionError('required refusal did not occur: ' + name)

    def bad(name, changes):
        path = args.output / (name + '.json')
        path.write_text(json.dumps(dict(data, **changes)))
        refused(name, lambda: activate_profile(path))

    headless = isinstance(profile, HeadlessWaylandProfile)
    check('explicit-profile-class', type(profile) is (HeadlessWaylandProfile if headless else GuestProfile))
    bad('reject-unknown-version', dict(version=999))
    bad('reject-wrong-account', dict(uid=profile.uid + 1))
    bad('reject-overlapping-roots', dict(runtimeBase=str(profile.work_base)))
    if headless:
        bad('reject-wrong-container', dict(containerId='not-the-current-container'))
        bad('reject-wrong-engine', dict(engine='docker' if profile.engine == 'podman' else 'podman'))
        bad('reject-compositor-start-change', dict(compositor=dict(data['compositor'], start='not-the-start')))
        bad('reject-foreign-runtime', dict(sessionRuntime='/run/user/1000'))
        bad('reject-foreign-display', dict(waylandDisplay='wayland-999'))
        refused('no-headless-live-console', lambda: activate_profile(args.guest_profile, require_console=True))
        refused('no-headless-hardware-input', lambda: profile.qmp_command({}))
    else:
        bad('reject-wrong-uuid', dict(uuid='00000000-0000-0000-0000-000000000001'))
        bad('reject-wrong-mac', dict(mac='00:00:00:00:00:01'))
        bad('reject-wrong-host-key', dict(sshHostKey='ssh-ed25519 AAAA'))
        container = {k: data[k] for k in ('name', 'uid', 'home', 'workspace', 'workBase', 'journalBase', 'runtimeBase')}
        container.update(version=2, mode='container-headless-wayland', engine='podman', containerId=Path('/etc/hostname').read_text().strip(),
                         sessionRuntime=str(profile.runtime_base / 'no-compositor'), waylandDisplay='wayland-0',
                         compositor=dict(ProcessIdentity.read(os.getpid()).record(), argv=['sway']))
        path = args.output / 'not-a-container.json'
        path.write_text(json.dumps(container))
        refused('no-headless-container-admission-on-vm', lambda: activate_profile(path))
    copied = args.output / 'changed.json'
    copied.write_text(json.dumps(data))
    captured = (HeadlessWaylandProfile if headless else GuestProfile)(copied)
    captured.verify()
    copied.write_text(json.dumps(data) + '\n')
    refused('captured-profile-content-fence', captured.verify)
    link = args.output / 'profile-link.json'
    link.symlink_to(args.guest_profile)
    refused('reject-profile-symlink', lambda: activate_profile(link))
    child = profile.child_environment('profile-modes-')
    check('owned-disk-child-runtime', Path(child['XDG_RUNTIME_DIR']).is_relative_to(profile.runtime_base))
    if headless:
        check('real-private-wayland-environment', child['QT_QPA_PLATFORM'] == 'wayland'
              and child['WAYLAND_DISPLAY'] == str(profile.session_runtime / profile.wayland_display))
    else:
        check('vm-keeps-real-wayland-session', child['WAYLAND_DISPLAY'] == str(profile.session_runtime / profile.wayland_display))
        query = ['timeout', '10', 'systemctl', '--user', 'show', '-p', 'Version', '--value']
        original = subprocess.run(query, capture_output=True, text=True, check=True, timeout=15)
        forwarded = subprocess.run(query, env=dict(os.environ, **child), capture_output=True, text=True, check=True, timeout=15)
        check('vm-keeps-real-session-manager', bool(original.stdout.strip()) and original.stdout == forwarded.stdout)
    profile.verify()
    (args.output / 'result.json').write_text(json.dumps(dict(status='PASS', profile=profile.record(), cases=results), indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
