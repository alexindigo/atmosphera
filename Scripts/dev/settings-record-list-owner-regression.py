#!/usr/bin/env python3
"""Mandatory seven-leaf retained fixture on the production ConfigQml owner."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'installed', 'output', 'work-root'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    args.work_root.mkdir(parents=True, exist_ok=False)
    probe = args.installed/'i5-record-list-owner.qml'
    fixture = (args.source/'Scripts/dev/fixtures/settings-record-list-editors.qml').read_bytes()
    with probe.open('xb') as stream:
        stream.write(fixture.replace(b'../../../Helpers/', b'./Helpers/'))
    helper = args.installed/'Helpers/SettingsListCommands.js'
    original = helper.read_bytes()

    def seed(name):
        root = args.work_root/name
        (root/'c/settings').mkdir(parents=True)
        (root/'c/settings.json').write_text('{"settingsVersion":62}')
        return root

    def run(name, root, restart=False, failure=None):
        env = dict(os.environ, I4_SETTINGS_OWNER='configqml', I4_VERIFY='1' if restart else '0',
                   ATMOSPHERA_CONFIG_DIR=str(root/'c'), ATMOSPHERA_CACHE_DIR=str(root/'cache'),
                   ATMOSPHERA_STATE_DIR=str(root/'state'), QML_DISABLE_DISK_CACHE='1')
        result = subprocess.run(['timeout', '40', 'qs', '-p', str(probe), '--no-color'],
                                env=env, capture_output=True, text=True, timeout=45)
        text = result.stdout+result.stderr
        (args.output/(name+'.log')).write_text(text)
        print(name+': exit='+str(result.returncode), flush=True)
        if failure:
            assert result.returncode == 2 and failure in text, text[-4000:]
        else:
            marker = 'RESTART_PASS' if restart else 'SAVED_PASS'
            assert result.returncode == 0 and 'I4_RECORD_LIST_EDITORS: '+marker in text, text[-4000:]
            assert not any(error in text for error in ('XFAIL', 'TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text[-4000:]

    try:
        needle = b'try { validateRanges(commands); }'
        assert original.count(needle) == 1
        helper.write_bytes(original.replace(needle, b'try { /* negative control: bypass range refusal */ }'))
        try:
            run('negative-range-refusal', seed('negative'), failure='invalid batch refused')
        finally:
            helper.write_bytes(original)
        root = seed('native')
        run('retained-save', root)
        run('retained-cold', root, restart=True)
        files = {p.stem: json.loads(p.read_text()) for p in (root/'c/settings').glob('*.json')}
        bar, shortcuts = files['bar'], files['controlCenter']['shortcuts']
        leaves = [bar['widgets'][part] for part in ('left', 'center', 'right')]
        leaves += [shortcuts[part] for part in ('left', 'right')]
        leaves += [bar['screenOverrides'][0]['widgets']['left'], files['desktopWidgets']['monitorWidgets'][0]['widgets']]
        for rows in leaves:
            assert [row['tag'] for row in rows] == ['second', 'edited']
            assert rows[1]['opaque'] == dict(keep=True) and 'removeMe' not in rows[1]
            assert all(rows[1][key] == dict(safe=True) for key in ('__proto__', 'constructor', 'prototype'))
        assert (root/'c/settings.json').read_text() == '{"settingsVersion":62}'
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS', owner='configqml', leaves=7,
            cases=['negative-range-refusal', 'settings-record-list-editors.qml/save', 'settings-record-list-editors.qml/cold'],
            files=files), indent=2)+'\n')
        print('SETTINGS_RECORD_LIST_OWNER: PASS (original hard assertions, seven actual owning leaves, confirmed save/file/cold, no XFAIL)')
    finally:
        helper.write_bytes(original)
        probe.unlink()


if __name__ == '__main__':
    main()
