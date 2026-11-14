#!/usr/bin/env python3
"""Guest-only failed-owner/profile/reload consumer regression."""
import argparse
import copy
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if subprocess.check_output(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid'], timeout=10).decode().strip() != '12f17a02-25e9-474c-9dae-fea092c2d2be':
        raise RuntimeError('assigned guest required')
    output.mkdir(parents=True, exist_ok=False)
    probe = source / 'Aowner-review.qml'
    with probe.open('x') as stream:
        stream.write((source / 'Scripts/dev/fixtures/settings-plugin-owner-review.qml').read_text().replace(
            '"../../../Helpers/', '"Helpers/'))
    rows = []
    try:
        for mode in ('cache', 'profile', 'retry', 'config'):
            root = output / mode
            config = root / 'config'
            plugin = config / 'plugins/owner-review'
            plugin.mkdir(parents=True)
            (config / 'settings.json').write_text('{"settingsVersion":62}')
            (config / 'plugins.json').write_text('{"version":5,"sources":[],"states":{}}')
            valid = {'id': 'owner-review', 'name': 'Owner review', 'version': '1.0.0',
                     'author': 'Regression fixture', 'description': 'Synthetic owner lifecycle', 'entryPoints': {},
                     'metadata': {'defaultSettings': {'label': 'ready'}, 'settingsSchema': {
                         'version': 1, 'fields': {'label': {'type': 'String'}}}}}
            invalid = copy.deepcopy(valid)
            invalid['metadata']['settingsSchema']['fields']['label']['type'] = 'NotAType'
            manifest = plugin / 'manifest.json'
            manifest.write_text(json.dumps(invalid))
            repaired = root / 'valid.json'
            repaired.write_text(json.dumps(valid))
            runtime = root / 'r'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM='wayland', XDG_RUNTIME_DIR=str(runtime),
                       WAYLAND_DISPLAY='/run/user/1000/wayland-1',
                       ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(root / 'cache'),
                       ATMOSPHERA_STATE_DIR=str(root / 'state'), OWNER_REVIEW_MODE=mode,
                       OWNER_REVIEW_VALID=str(repaired), OWNER_REVIEW_MANIFEST=str(manifest))
            result = subprocess.run(['timeout', '35', 'dbus-run-session', '--', 'qs', '-p', str(probe), '--no-color'],
                                    env=env, capture_output=True, text=True, timeout=40)
            log = result.stdout + result.stderr
            (root / 'engine.log').write_text(log)
            passed = result.returncode == 0 and 'OWNER_REVIEW: PASS ' + mode in log and not any(
                token in log for token in ('TypeError:', 'ReferenceError:', 'OWNER_REVIEW_ASSERT:', 'Failed to load configuration'))
            rows.append(dict(id=mode, status='PASS' if passed else 'FAIL', exit=result.returncode))
            print(json.dumps(rows[-1]), flush=True)
        (output / 'result.json').write_text(json.dumps(rows, indent=2) + '\n')
    finally:
        probe.unlink()
    return int(any(row['status'] != 'PASS' for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
