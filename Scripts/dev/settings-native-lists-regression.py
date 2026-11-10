#!/usr/bin/env python3
"""Real-schema native list command prerequisite. Run only in the assigned VM."""
import argparse
import hashlib
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
    probe = args.installed/'i5-native-lists.qml'
    fixture = (args.source/'Scripts/dev/fixtures/settings-native-list-commands.qml').read_bytes()
    with probe.open('xb') as stream:
        stream.write(fixture.replace(b'../../../Helpers/SettingsListCommands.js', b'./Helpers/SettingsListCommands.js'))

    def row(tag):
        return dict(id='Repeat', tag=tag, opaque=dict(keep=True), removeMe=True,
                    instanceSettings=dict(keep=True), wide=18446744073709551615,
                    **{'__proto__': dict(original=True), 'constructor': dict(original=True), 'prototype': dict(original=True)})

    def seed(name):
        directory = args.work_root/name
        (directory/'settings').mkdir(parents=True)
        rows = [row('first'), row('second')]
        files = dict(bar=dict(widgets=dict(left=[dict(id='Ghost', opaque='hidden')]+rows, center=rows, right=rows),
                              screenOverrides=[dict(name='original', opaque='monitor', widgets=dict(left=rows))]),
                     controlCenter=dict(shortcuts=dict(left=rows, right=rows)),
                     desktopWidgets=dict(monitorWidgets=[dict(name='original', opaque='desktop', widgets=rows)]))
        for section, value in files.items():
            (directory/'settings'/(section+'.json')).write_text(json.dumps(value)+'\n')
        legacy = directory/'settings.json'
        legacy.write_text('{"settingsVersion":62,"opaque":18446744073709551615}\n')
        return directory

    def identity(path):
        st = path.stat()
        return dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), inode=st.st_ino,
                    mtimeNs=st.st_mtime_ns, mode=st.st_mode)

    def run(name, directory, restart=False, failure=None):
        env = dict(os.environ, I5_LIST_DIR=str(directory), I4_VERIFY='1' if restart else '0', QML_DISABLE_DISK_CACHE='1')
        result = subprocess.run(['timeout', '35', 'qs', '-p', str(probe), '--no-color'],
                                env=env, capture_output=True, text=True, timeout=40)
        text = result.stdout+result.stderr
        (args.output/(name+'.log')).write_text(text)
        print(text, end='', flush=True)
        if failure:
            assert result.returncode == 2 and failure in text, (name, result.returncode, text[-6000:])
            assert 'I5_NATIVE_LIST_COMMANDS: SAVED_PASS' not in text
        else:
            marker = 'RESTART_PASS' if restart else 'SAVED_PASS'
            assert result.returncode == 0 and 'I5_NATIVE_LIST_COMMANDS: '+marker in text, (name, result.returncode, text[-6000:])
            assert not any(x in text for x in ['TypeError:', 'ReferenceError:', 'SyntaxError:', 'I5_NATIVE_LIST_ASSERT:'])

    policies = args.installed/'Commons/SettingsRecordListPolicies.qml'
    original = policies.read_bytes()
    helper = args.installed/'Helpers/SettingsListCommands.js'
    original_helper = helper.read_bytes()
    results = []
    try:
        for name, old, new, failure in [
            ('negative-opaque-copy', b'copy(own(value, key), next)', b'copy(key === "__proto__" ? {} : own(value, key), next)', 'opaque display members 0'),
            ('negative-instance-preservation', b'preservedFields: ["instanceSettings"]', b'preservedFields: []', 'normalization preserves instance override'),
            ('negative-same-owner-refresh', b'targets.forEach(function (target) {\n                                if (active.some', b'active.forEach(function (target) {\n                                if (active.some', 'same owner endpoint refresh'),
        ]:
            target, content = (policies, original) if name == 'negative-instance-preservation' else (helper, original_helper)
            assert old in content
            target.write_bytes(content.replace(old, new))
            try:
                run(name, seed(name), failure=failure)
            finally:
                target.write_bytes(content)
            results.append(dict(id=name, status='PASS', negative=True))
        directory = seed('native')
        before = identity(directory/'settings.json')
        run('native-save', directory)
        run('native-restart', directory, restart=True)
        assert identity(directory/'settings.json') == before
        files = {p.stem: json.loads(p.read_text()) for p in (directory/'settings').glob('*.json')}
        assert set(files) == {'bar', 'controlCenter', 'desktopWidgets'}
        leaves = [files['bar']['widgets'][name] for name in ['left', 'center', 'right']]
        leaves += [files['controlCenter']['shortcuts'][name] for name in ['left', 'right']]
        leaves += [files['bar']['screenOverrides'][0]['widgets']['left'], files['desktopWidgets']['monitorWidgets'][0]['widgets']]
        for index, rows in enumerate(leaves):
            selected = rows[1 if index == 0 else 0]
            assert selected['tag'] == 'edited' and selected['opaque'] == {'keep': True}
            assert selected['wide'] == 18446744073709551615
            assert 'removeMe' not in selected
            assert all(selected[key] == {'safe': True} for key in ['__proto__', 'constructor', 'prototype'])
        left = files['bar']['widgets']['left']
        assert len(left) == 2 and left[0] == dict(id='Ghost', opaque='hidden')
        assert left[1]['showIcon'] is False and left[1]['instanceSettings'] == dict(keep=True)
        center = files['bar']['widgets']['center']
        assert len(center) == 3 and center[2] == row('second')  # No housekeeping defaults copied.
        created = files['bar']['screenOverrides'][1]
        assert set(created) == {'name', 'widgets'} and created['name'] == 'offline.屏/__proto__'
        assert set(created['widgets']) == {'right'} and created['widgets']['right'][0]['tag'] == 'created'
        assert created['widgets']['right'][0]['wide'] == 18446744073709551615
        assert files['controlCenter']['shortcuts']['right'][1]['tag'] == 'detached'
        assert files['bar']['screenOverrides'][0]['widgets']['right'][0]['tag'] == 'same-leaf'
        results.append(dict(id='native-save-restart', status='PASS', legacyIdentity=before, files=files))
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS', cases=results), indent=2)+'\n')
        print('SETTINGS_NATIVE_LISTS: PASS (seven leaves, native fences/mapping/transfer/containers, save/file/cold restart, 3 rejecting controls)')
    finally:
        policies.write_bytes(original)
        helper.write_bytes(original_helper)
        probe.unlink()


if __name__ == '__main__':
    main()
