#!/usr/bin/env python3
"""Native instance runtime/reset/lifetime checks. Assigned project VM only."""
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
    probes = []
    for name in ('live', 'lifetime'):
        probe = args.installed/('i5-instance-'+name+'.qml')
        with probe.open('xb') as stream:
            fixture = (args.source/'Scripts/dev/fixtures'/('settings-instance-'+name+'.qml')).read_bytes()
            stream.write(fixture.replace(b'../../../Helpers/OwnedProcess.js', b'./Helpers/OwnedProcess.js'))
        probes.append(probe)

    def identity(path):
        stat = path.stat()
        return dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), inode=stat.st_ino,
                    mtimeNs=stat.st_mtime_ns, mode=stat.st_mode)

    def seed(name, override=False):
        root = args.work_root/name
        for part in ('plugin/code', 'plugin/user', 'c/settings', 'cache', 'state'):
            (root/part).mkdir(parents=True)
        manifest = dict(id='i5-owner', version='1.0.0', metadata=dict(
            defaultSettings=dict(label='default', amount=3),
            settingsSchema=dict(version=1, fields=dict(label=dict(type='String'), amount=dict(type='Integer')))))
        (root/'plugin/code/manifest.json').write_text(json.dumps(manifest))
        (root/'plugin/code/settings.json').write_text('{"label":"legacy","amount":7,"wide":18446744073709551615}')
        (root/'c/settings.json').write_text('{"settingsVersion":62}')
        row = dict(id='plugin:i5-owner', wide=18446744073709551615, **{'__proto__': dict(safe=True)})
        if override:
            row['instanceSettings'] = dict(label='custom')
        (root/'c/settings/bar.json').write_text(json.dumps(dict(widgets=dict(left=[row]))))
        return root

    def run(name, root, probe, restart=False, failure=None):
        env = dict(os.environ, I5_PLUGIN_DIR=str(root/'plugin'), I5_INSTANCE_RESTART='1' if restart else '0',
                   ATMOSPHERA_CONFIG_DIR=str(root/'c'), ATMOSPHERA_CACHE_DIR=str(root/'cache'),
                   ATMOSPHERA_STATE_DIR=str(root/'state'), QML_DISABLE_DISK_CACHE='1')
        result = subprocess.run(['timeout', '40', 'qs', '-p', str(probe), '--no-color'],
                                env=env, capture_output=True, text=True, timeout=45)
        text = result.stdout+result.stderr
        (args.output/(name+'.log')).write_text(text)
        (args.output/(name+'.exit')).write_text(str(result.returncode)+'\n')
        print(name+': exit='+str(result.returncode), flush=True)
        if failure:
            assert result.returncode == 2 and failure in text, text[-4000:]
        else:
            marker = 'I5_INSTANCE_LIFETIME: PASS' if probe == probes[1] else 'I5_INSTANCE_LIVE: PASS'
            assert result.returncode == 0 and marker in text, text[-4000:]
            assert not any(error in text for error in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text[-4000:]

    api = args.installed/'Services/Plugins/PluginInstanceApi.qml'
    original = api.read_bytes()
    roots = []
    cases = []
    try:
        live = seed('live')
        roots.append(live)
        before = identity(live/'plugin/code/settings.json')
        run('live-save', live, probes[0])
        run('live-cold', live, probes[0], restart=True)
        row = json.loads((live/'c/settings/bar.json').read_text())['widgets']['left'][0]
        assert row['instanceSettings'] == dict(label='live-second')
        assert row['wide'] == 18446744073709551615 and row['__proto__'] == dict(safe=True)
        assert identity(live/'plugin/code/settings.json') == before
        assert not (live/'plugin/user/settings.json').exists()
        cases.append(dict(id='live-save-cold', status='PASS', legacyIdentity=before))
        needle = b'if (result.status !== "failed" && result.refreshState === "current") editor.discard();'
        assert original.count(needle) == 1
        api.write_bytes(original.replace(needle, b'editor.discard();'))
        negative = seed('negative-reset-discard', override=True)
        roots.append(negative)
        try:
            run('negative-reset-discard', negative, probes[1], failure='failed reset retains native editor and work')
        finally:
            api.write_bytes(original)
            (negative/'c/settings').chmod(0o755)
        cases.append(dict(id='negative-reset-discard', status='PASS', negative=True))
        lifetime = seed('lifetime', override=True)
        roots.append(lifetime)
        before = identity(lifetime/'plugin/code/settings.json')
        run('reset-lifetime', lifetime, probes[1])
        row = json.loads((lifetime/'c/settings/bar.json').read_text())['widgets']['left'][0]
        assert 'instanceSettings' not in row and row['wide'] == 18446744073709551615
        assert row['__proto__'] == dict(safe=True)
        assert identity(lifetime/'plugin/code/settings.json') == before
        assert not (lifetime/'plugin/user/settings.json').exists()
        cases.append(dict(id='reset-open-cancel-lifetime', status='PASS', legacyIdentity=before))
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS', cases=cases), indent=2)+'\n')
        print('SETTINGS_PLUGIN_NATIVE: PASS (live queue/cold/sparse/raw, failed reset retention/retry, open refusal/cancel/destruction, negative control)')
    finally:
        api.write_bytes(original)
        for root in roots:
            (root/'c/settings').chmod(0o755)
        for probe in probes:
            probe.unlink()


if __name__ == '__main__':
    main()
