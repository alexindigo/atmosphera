#!/usr/bin/env python3
"""Native schedule markers promise complete JSON and a ready FIFO reader."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import resource
import signal
import shutil
import subprocess
import time

from guest_profile import activate_profile, profile_argument, protect_owned_process
from native_settings_controls import prepare
from probe_files import ProbeFiles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    profile_argument(parser)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    source = args.source.resolve()
    work, output = args.work_root.resolve(), args.output.resolve()
    for path in (work, output):
        if not path.is_relative_to(profile.workspace) or path == profile.workspace:
            raise SystemExit('outputs must stay in the assigned workspace')
        path.mkdir(parents=True, exist_ok=False)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    build, contract = prepare(source)
    rows = []
    with closing(ProbeFiles(source, source/'Scripts/dev/fixtures/settings-native-schedule.qml')) as probes:
        for case in ('missing-reader', 'normal', 'failure'):
            root = work/case
            (root/'config/settings').mkdir(parents=True)
            (root/'config/settings.json').write_text('{"settingsVersion":62}')
            (root/'config/plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
            target = root/'config/settings/ui.json'
            target.write_text('{"fontDefaultScale":1}')
            marker, gate, schedule = (root/name for name in ('held.json', 'release', 'schedule.json'))
            if case != 'missing-reader':
                os.mkfifo(gate, 0o600)
            schedule.write_text(json.dumps(dict(rules=[dict(file=str(target), phase='rename', marker=str(marker), gate=str(gate))])))
            runtime = profile.child_environment('nr-')
            env = dict(os.environ, **runtime, ATMOSPHERA_CONFIG_DIR=str(root/'config'),
                       ATMOSPHERA_SETTINGS_FILE=str(root/'config/settings.json'),
                       ATMOSPHERA_CACHE_DIR=str(root/'cache'), ATMOSPHERA_STATE_DIR=str(root/'state'),
                       LD_PRELOAD=str(build/'libatmosphera_native_io.so'), ATCQ_NATIVE_SCHEDULE=str(schedule),
                       SCHEDULE_RELEASE='1' if case == 'failure' else '0', QML_DISABLE_DISK_CACHE='1')
            child = guard = None
            error = None
            try:
                with (output/(case+'.log')).open('x') as log:
                    child = subprocess.Popen(['qs', '-p', str(probes.probe), '--no-color'], env=env,
                                             stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                    guard = protect_owned_process(child)
                    if case == 'missing-reader':
                        assert child.wait(timeout=20) != 0, 'missing FIFO must fail instrumentation'
                        assert not marker.exists(), 'marker falsely advertised an unavailable FIFO reader'
                    else:
                        deadline = time.monotonic()+20
                        while not marker.exists():
                            assert child.poll() is None and time.monotonic() < deadline, 'native hold missing'
                            time.sleep(.001)
                        observation = json.loads(marker.read_text())
                        assert observation['phase'] == 'rename' and observation['file'] == str(target)
                        fd = os.open(gate, os.O_WRONLY | os.O_NONBLOCK)
                        try:
                            os.write(fd, b'1\n' if case == 'failure' else b'0\n')
                        finally:
                            os.close(fd)
                        assert child.wait(timeout=20) == 0
                        assert 'NATIVE_SCHEDULE: PASS' in (output/(case+'.log')).read_text()
                        if case == 'normal':
                            assert json.loads(target.read_text())['fontDefaultScale'] == 1.25
            except Exception as caught:
                error = repr(caught)
            finally:
                if child is not None and child.poll() is None:
                    if guard is None:
                        guard = protect_owned_process(child)
                    guard.terminate()
                    child.wait(timeout=5)
                shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))
            rows.append(dict(case=case, status='FAIL' if error else 'PASS', error=error))
            print(json.dumps(rows[-1]), flush=True)
    profile.verify()
    (output/'result.json').write_text(json.dumps(dict(cases=rows, nativeControls=contract), indent=2)+'\n')
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
