#!/usr/bin/env python3
"""Reject a runner that releases pending IO before native owner detach."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
from unittest.mock import patch

from guest_profile import activate_profile, profile_argument, protect_owned_process


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'runner', 'output', 'work-root'):
        parser.add_argument('--'+name, type=Path, required=True)
    profile_argument(parser)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    source, output, work = (path.resolve() for path in (args.source, args.output, args.work_root))
    if not all(path.is_relative_to(profile.workspace) and path != profile.workspace for path in (output, work)):
        raise SystemExit('outputs must stay in the assigned workspace')
    output.mkdir(parents=True, exist_ok=False)
    marker = output/'native-detached.json'
    module_spec = importlib.util.spec_from_file_location('engine_lifetime', args.runner)
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    popen, write = subprocess.Popen, os.write
    releases = []
    children = []
    entry = source/'i5-engine-lifetime.qml'
    entry_existed = entry.exists()

    def launch(command, **kwargs):
        nonlocal marker
        if command[0] == 'qs' and '-p' in command and 'ipc' not in command:
            marker = Path(kwargs['env'].get('ATCQ_NATIVE_DETACH_MARKER', str(marker)))
            kwargs['env'] = dict(kwargs['env'], ATCQ_NATIVE_DETACH_MARKER=str(marker))
        child = popen(command, **kwargs)
        if kwargs.get('start_new_session'):
            children.append((child, protect_owned_process(child)))
        return child

    def checked_write(fd, body):
        if body == b'0\n' and stat.S_ISFIFO(os.fstat(fd).st_mode):
            if not marker.is_file():
                raise AssertionError('rename released before native owner detach')
            observation = json.loads(marker.read_text())
            if observation['phase'] != 'owner-detached':
                raise AssertionError('native detach observation missing')
            releases.append(observation)
        return write(fd, body)

    error = None
    try:
        with patch.object(sys, 'argv', ['engine-lifetime', '--source', str(source), '--installed', str(source),
                                      '--output', str(output/'case'), '--work-root', str(work)]), \
             patch.object(module.subprocess, 'Popen', launch), patch.object(module.os, 'write', checked_write), \
             patch.dict(os.environ, WAYLAND_DISPLAY=str(profile.session_runtime/profile.wayland_display)):
            module.main()
        if len(releases) != 1:
            raise AssertionError('exactly one native-detach-fenced release required')
    except Exception as caught:
        error = repr(caught)
    finally:
        # The rejecting old runner cannot clean up after the injected refusal.
        # Release only this known FIFO, outside the checked assertion, then reap
        # only the child we launched (recorded independently below).
        gate = work/'release'
        if gate.exists():
            try:
                fd = os.open(gate, os.O_WRONLY | os.O_NONBLOCK)
            except OSError:
                pass
            else:
                try:
                    write(fd, b'0\n')
                finally:
                    os.close(fd)
        for child, guard in children:
            if child.poll() is None:
                guard.terminate()
            child.wait(timeout=10)
        if not entry_existed and entry.exists():
            entry.unlink()
    (output/'result.json').write_text(json.dumps(dict(status='FAIL' if error else 'PASS', error=error,
                                                   releases=releases), indent=2)+'\n')
    print('ENGINE_LIFETIME_REVIEW:', 'FAIL '+str(error) if error else 'PASS', flush=True)
    return int(error is not None)


if __name__ == '__main__':
    raise SystemExit(main())
