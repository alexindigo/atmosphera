#!/usr/bin/env python3
"""Deterministic launch/readiness controls; real profile admission stays strict."""
import argparse
from dataclasses import replace
import importlib.util
import json
import os
from pathlib import Path
import signal
from unittest.mock import Mock, patch

from guest_profile import ProcessIdentity, ProfileBlocked, activate_profile, profile_argument


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    if args.output.exists() or args.output != args.output.resolve() or not args.output.is_relative_to(profile.journal_base):
        raise ProfileBlocked('fresh canonical profile-journal output required')
    args.output.mkdir(mode=0o700)
    spec = importlib.util.spec_from_file_location('image_ci', Path(__file__).with_name('image-decoding-ci.py'))
    ci = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ci)
    argv = ('/usr/bin/sway', '--config', '/private/sway.conf')
    pid = os.getpid() + 100000
    launch = ProcessIdentity(pid, '12345', os.getuid(), pid, ())
    ready = replace(launch, argv=argv)
    process = Mock(pid=pid)
    process.poll.return_value = None
    rows = []

    def check(name, condition):
        assert condition, name
        rows.append(dict(id=name, status='PASS'))
        print('CASE ' + name + ': PASS', flush=True)

    def refused(name, call):
        try:
            call()
        except ProfileBlocked:
            check(name, True)
        else:
            raise AssertionError('required refusal did not occur: ' + name)

    with patch.object(ci.ProcessIdentity, 'read', return_value=launch):
        owned = ci.CompositorOwnership(process)
    with patch.object(ci.ProcessIdentity, 'read', return_value=ready):
        check('empty-launch-argv-settles-at-ready', owned.ready(argv) == ready)
    for field, value in (('pid', pid + 1), ('start', 'changed'), ('uid', os.getuid() + 1), ('pgid', pid + 1)):
        changed = replace(ready, **{field: value})
        with patch.object(ci.ProcessIdentity, 'read', return_value=changed), patch.object(ci.os, 'killpg') as kill:
            refused('reject-ready-' + field + '-change', lambda: owned.ready(argv))
            refused('reject-teardown-' + field + '-change', owned.terminate)
            check('never-signal-changed-' + field, not kill.called)
    for name, args_value in (('empty', ()), ('foreign', ('other',)), ('wrong-config', ('/usr/bin/sway', '--config', '/other'))):
        with patch.object(ci.ProcessIdentity, 'read', return_value=replace(ready, argv=args_value)):
            refused('reject-ready-' + name + '-argv', lambda: owned.ready(argv))
    with patch.object(ci.ProcessIdentity, 'read', return_value=replace(ready, argv=('diagnostic-change',))), patch.object(ci.os, 'killpg') as kill:
        owned.terminate()
        check('teardown-uses-kernel-launch-ownership', kill.call_args.args == (pid, signal.SIGTERM))
    for name, changed in (('foreign-account', replace(launch, uid=os.getuid() + 1)),
                          ('nonleader', replace(launch, pgid=pid + 1)),
                          ('runner-group', replace(launch, pgid=os.getpgrp()))):
        with patch.object(ci.ProcessIdentity, 'read', return_value=changed):
            refused('reject-launch-' + name, lambda: ci.CompositorOwnership(process))
    process.poll.return_value = 0
    with patch.object(ci.ProcessIdentity, 'read') as read, patch.object(ci.os, 'killpg') as kill:
        owned.terminate()
        check('exited-child-never-signalled', not read.called and not kill.called)
    data = json.loads(args.guest_profile.read_bytes())
    if data.get('mode') == 'container-headless-wayland':
        invalid = args.output / 'empty-ready-argv.json'
        data['compositor']['argv'] = []
        invalid.write_text(json.dumps(data))
        refused('profile-still-rejects-empty-ready-argv', lambda: activate_profile(invalid))
    profile.verify()
    (args.output / 'result.json').write_text(json.dumps(dict(status='PASS', profile=profile.record(), cases=rows), indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
