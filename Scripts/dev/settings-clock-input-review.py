#!/usr/bin/env python3
"""Actual Clock signal-order, sparse publication and cold consumer regression."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import subprocess

from probe_files import ProbeFiles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if subprocess.check_output(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid']).decode().strip() != '12f17a02-25e9-474c-9dae-fea092c2d2be':
        raise RuntimeError('assigned guest required')
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    with closing(ProbeFiles(source, source / 'Scripts/dev/fixtures/settings-clock-input-review.qml')) as probes:
        probe = probes.probe
        for mode in ('bar', 'desktop'):
            root = output / mode
            config = root / 'config'
            (config / 'settings/plugins').mkdir(parents=True)
            (config / 'settings.json').write_text('{"settingsVersion":62}')
            (config / 'plugins.json').write_text('{"version":5,"sources":[],"states":{}}')
            runtime = root / 'r'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM='wayland', XDG_RUNTIME_DIR=str(runtime),
                       WAYLAND_DISPLAY='/run/user/1000/wayland-1', ATMOSPHERA_CONFIG_DIR=str(config),
                       ATMOSPHERA_SETTINGS_FILE=str(config / 'settings.json'),
                       ATMOSPHERA_CACHE_DIR=str(root / 'cache'), ATMOSPHERA_STATE_DIR=str(root / 'state'),
                       CLOCK_INPUT_MODE=mode)
            for phase in ('save', 'cold'):
                if phase == 'cold':
                    env['CLOCK_INPUT_VERIFY'] = '1'
                result = subprocess.run(['timeout', '35', 'dbus-run-session', '--', 'qs', '-p', str(probe), '--no-color'],
                                        env=env, capture_output=True, text=True, timeout=40)
                log = result.stdout + result.stderr
                (root / (phase + '.log')).write_text(log)
                marker = 'CLOCK_INPUT: ' + ('SAVED_PASS' if phase == 'save' else 'COLD_PASS') + ' ' + mode
                passed = result.returncode == 0 and marker in log and not any(
                    token in log for token in ('TypeError:', 'ReferenceError:', 'CLOCK_INPUT_ASSERT:', 'Failed to load configuration'))
                rows.append(dict(id=mode + '-' + phase, status='PASS' if passed else 'FAIL', exit=result.returncode))
                print(json.dumps(rows[-1]), flush=True)
                if not passed:
                    break
        (output / 'result.json').write_text(json.dumps(rows, indent=2) + '\n')
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
