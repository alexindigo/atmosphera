#!/usr/bin/env python3
"""Real production-owner IO scheduling and GUI responsiveness; assigned guest only."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time
from guest_profile import activate_profile, profile_argument, protect_owned_process
from native_settings_controls import prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'output', 'work-root'):
        parser.add_argument('--'+name, required=True, type=Path)
    profile_argument(parser)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    args.output.mkdir(parents=True, exist_ok=False)
    args.work_root.mkdir(parents=True, exist_ok=False)
    build, record = prepare(args.source)
    config = args.work_root/'config'
    (config/'settings').mkdir(parents=True)
    legacy = config/'settings.json'
    legacy.write_text('{"settingsVersion":62}')
    (config/'plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
    original = legacy.stat()
    target = config/'settings/ui.json'
    target.write_text('{"fontDefaultScale":1}')
    schedule, marker, gate = (args.work_root/name for name in ('native.json', 'held', 'release'))
    os.mkfifo(gate, 0o600)
    schedule.write_text(json.dumps(dict(rules=[dict(file=str(target), phase='rename', marker=str(marker), gate=str(gate))])))
    entry = args.source/'i5-native-io.qml'
    with entry.open('xb') as stream:
        stream.write((args.source/'Scripts/dev/fixtures/settings-native-io.qml').read_bytes())
    env = dict(os.environ, QML_IMPORT_PATH=str(build), LD_PRELOAD=str(build/'libatmosphera_native_io.so'),
               ATCQ_NATIVE_SCHEDULE=str(schedule), ATMOSPHERA_CONFIG_DIR=str(config),
               ATMOSPHERA_CACHE_DIR=str(args.work_root/'cache'), ATMOSPHERA_STATE_DIR=str(args.work_root/'state'))
    env.update(profile.child_environment('ni-'))
    proc = None
    try:
        with (args.output/'save.log').open('x') as log:
            proc = subprocess.Popen(['qs', '-p', str(entry), '--no-color'], env=env,
                                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic()+20
            while not marker.exists() or 'NATIVE_IO: HELD_GUI_PASS' not in (args.output/'save.log').read_text():
                assert proc.poll() is None and time.monotonic() < deadline, 'native hold/GUI observation unavailable'
                assert (args.output/'save.log').stat().st_size < 2*1024*1024
                time.sleep(.01)
            assert json.loads(target.read_text())['fontDefaultScale'] == 1
            descriptor = os.open(gate, os.O_WRONLY | os.O_NONBLOCK)
            try:
                os.write(descriptor, b'0\n')
            finally:
                os.close(descriptor)
            proc.wait(timeout=20)
        assert proc.returncode == 0 and 'NATIVE_IO: SAVED_PASS' in (args.output/'save.log').read_text()
        assert json.loads(target.read_text())['fontDefaultScale'] == 1.25
        cold_env = dict(env, NATIVE_IO_COLD='1')
        cold_env.pop('LD_PRELOAD')
        cold_env.pop('ATCQ_NATIVE_SCHEDULE')
        cold = subprocess.run(['timeout', '20', 'qs', '-p', str(entry), '--no-color'], env=cold_env,
                              capture_output=True, text=True, timeout=25)
        (args.output/'cold.log').write_text(cold.stdout+cold.stderr)
        assert cold.returncode == 0 and 'NATIVE_IO: COLD_PASS' in cold.stdout+cold.stderr
        after = legacy.stat()
        assert legacy.read_text() == '{"settingsVersion":62}' and (after.st_ino, after.st_mtime_ns, after.st_mode) == (original.st_ino, original.st_mtime_ns, original.st_mode)
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS', cases=['held-native-publication', 'GUI-consumer-while-held', 'saved-readback', 'cold-consumer'], controls=record,
            runtimeRoot=env['XDG_RUNTIME_DIR']), indent=2)+'\n')
        print('NATIVE_SETTINGS_CONTROLS: PASS')
    finally:
        if proc is not None and proc.poll() is None:
            protect_owned_process(proc)
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=5)
        entry.unlink()


if __name__ == '__main__':
    main()
