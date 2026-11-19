#!/usr/bin/env python3
"""Actual bootstrap/path/diagnostic contracts; run only in an explicit test VM."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from guest_profile import activate_profile, profile_argument, protect_owned_process


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--work-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    profile_argument(parser)
    args = parser.parse_args()
    if not __debug__:
        raise SystemExit('optimized test execution is not supported')
    profile = activate_profile(args.guest_profile)
    source = args.source.resolve()
    work, output = args.work_root.resolve(), args.output.resolve()
    for path in (work, output):
        if not path.is_relative_to(profile.workspace) or path == profile.workspace:
            raise SystemExit('test outputs must be inside the assigned guest workspace')
        path.mkdir(parents=True, exist_ok=False)
    probe = source / 'settings-startup-boundaries.qml'
    fixture = (source / 'Scripts/dev/fixtures/settings-startup-boundaries.qml').read_bytes()
    rows = []
    with probe.open('xb') as stream:
        stream.write(fixture)
    try:
        for name, count in [('absolute', 0), ('relative', 0), ('unclean', 0),
                            ('state-unavailable', 0), ('state-lazy', 0),
                            ('diagnostics-64', 64), ('diagnostics-65', 65), ('diagnostics-200', 200)]:
            directory = work / name
            (directory / 'config/settings').mkdir(parents=True)
            raw = dict(fontDefaultScale=1.23, **{'unknown'+str(i): 'private-value' for i in range(count)})
            (directory / 'config/settings/ui.json').write_text(json.dumps(raw))
            state = directory / 'state'
            if name == 'state-unavailable':
                state.write_text('not a directory\n')
            env = dict(os.environ, **profile.session_environment(),
                       ATMOSPHERA_CONFIG_DIR=str(directory / 'config'),
                       ATMOSPHERA_CACHE_DIR='./cache' if name == 'relative' else
                           str(directory / 'cache') + ('/../cache' if name == 'unclean' else ''),
                       ATMOSPHERA_STATE_DIR=str(state),
                       ATMOSPHERA_SETTINGS_FILE=str(directory / 'config/settings.json'),
                       QML_DISABLE_DISK_CACHE='1')
            log = output / (name + '.log')
            with log.open('x') as stream:
                child = subprocess.Popen(['timeout', '--kill-after=5', '15', 'qs', '-p', str(probe), '--no-color'],
                                         cwd=directory, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                         start_new_session=True)
                guard = None
                try:
                    guard = protect_owned_process(child)
                    code = child.wait(timeout=25)
                finally:
                    if child.poll() is None:
                        if guard:
                            guard.terminate()
                        else:
                            child.terminate()
                        child.wait(timeout=10)
            text = log.read_text()
            markers = [line.split('STARTUP_BOUNDARY_RESULT:', 1)[1] for line in text.splitlines()
                       if 'STARTUP_BOUNDARY_RESULT:' in line]
            errors = []
            if code != 0 or len(markers) != 1:
                errors.append('native owner did not become ready and close cleanly')
            if markers:
                result = json.loads(markers[0])
                expected = dict(cache=str(directory / 'cache')+'/', config=str(directory / 'config')+'/',
                                state=str(state)+'/', settingsFile=str(directory / 'config/settings.json'),
                                fontScale=1.23, warnings=min(count, 64), truncated=int(count > 64))
                if result != expected:
                    errors.append({'expected': expected, 'actual': result})
            if name == 'state-unavailable' and state.read_text() != 'not a directory\n':
                errors.append('bootstrap changed an unavailable optional state destination')
            if name == 'state-lazy' and state.exists():
                errors.append('bootstrap eagerly created optional state')
            if 'private-value' in text:
                errors.append('diagnostics leaked unknown values')
            row = dict(case=name, exit=code, status='FAIL' if errors else 'PASS', errors=errors)
            rows.append(row)
            (output / 'result.json').write_text(json.dumps(dict(cases=rows), indent=2)+'\n')
            print(json.dumps(row), flush=True)
        profile.verify()
        return 1 if any(row['status'] != 'PASS' for row in rows) else 0
    finally:
        probe.unlink()


if __name__ == '__main__':
    raise SystemExit(main())
