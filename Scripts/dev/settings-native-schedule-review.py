#!/usr/bin/env python3
"""Native schedule markers promise complete JSON and a ready FIFO reader."""
import argparse
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import resource
import shutil
import time

from guest_profile import activate_profile, profile_argument
from native_settings_controls import prepare
from probe_files import ProbeFiles
from presentation_harness import run_harness


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
                       XDG_CACHE_HOME=str(root/'cache'), XDG_CONFIG_HOME=str(root/'xdg'),
                       XDG_STATE_HOME=str(root/'state'), XDG_DATA_HOME=str(root/'data'),
                       SCHEDULE_RELEASE='1' if case == 'failure' else '0', QML_DISABLE_DISK_CACHE='1')
            execution = None
            error = None
            try:
                supervised = root/'execution'
                supervised.mkdir()
                # Expected native aborts can fork Quickshell crash helpers.
                # Own the whole descendant lifetime, not just Popen's child.
                command = ['env', 'LD_PRELOAD='+env.pop('LD_PRELOAD'), 'qs', '-p', str(probes.probe), '--no-color']
                with ThreadPoolExecutor(max_workers=1) as supervisor:
                    future = supervisor.submit(run_harness, command, supervised, env, 30)
                    try:
                        if case != 'missing-reader':
                            deadline = time.monotonic()+20
                            while not marker.exists():
                                assert not future.done() and time.monotonic() < deadline, 'native hold missing'
                                time.sleep(.001)
                            observation = json.loads(marker.read_text())
                            assert observation['phase'] == 'rename' and observation['file'] == str(target)
                            fd = os.open(gate, os.O_WRONLY | os.O_NONBLOCK)
                            try:
                                os.write(fd, b'1\n' if case == 'failure' else b'0\n')
                            finally:
                                os.close(fd)
                    finally:
                        execution = future.result(timeout=40)
                        shutil.copyfile(supervised/'shell.log', output/(case+'.log'))
                assert execution['cleanup_complete'] and not execution['timed_out'], execution
                if case == 'missing-reader':
                    assert execution['exit_code'] != 0, 'missing FIFO must fail instrumentation'
                    assert not marker.exists(), 'marker falsely advertised an unavailable FIFO reader'
                else:
                    assert execution['exit_code'] == 0
                    assert 'NATIVE_SCHEDULE: PASS' in (output/(case+'.log')).read_text()
                    if case == 'normal':
                        assert json.loads(target.read_text())['fontDefaultScale'] == 1.25
            except Exception as caught:
                error = repr(caught)
            finally:
                if execution is not None and execution['cleanup_complete']:
                    shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))
                else:
                    error = (error or '')+'; namespace not proven quiet; runtime retained'
            rows.append(dict(case=case, status='FAIL' if error else 'PASS', error=error, execution=execution))
            print(json.dumps(rows[-1]), flush=True)
    profile.verify()
    (output/'result.json').write_text(json.dumps(dict(cases=rows, nativeControls=contract), indent=2)+'\n')
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
