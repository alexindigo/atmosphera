#!/usr/bin/env python3
"""Retained preview assertions on actual native preference owners. Guest only."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'installed', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    args.work_root.mkdir(parents=True, exist_ok=False)
    args.output.mkdir(parents=True, exist_ok=False)
    root = args.work_root
    config = root/'c'
    (config/'settings/plugins').mkdir(parents=True)
    (config/'settings.json').write_text('{"settingsVersion":62}')
    (config/'plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
    failure = root/'readonly'
    failure.mkdir()
    (failure/'settings.json').write_text('{"label":"failure-base"}')
    for name, label in [('i4-preview', 'base'), ('i4-preview-fail', 'failure-base'), ('i4-dead-preview', 'alive')]:
        directory = config/'plugins'/name
        directory.mkdir(parents=True)
        fields = dict(label=dict(type='String'), other=dict(type='String'),
                      opaque=dict(type='Record', open=True, fields=dict(keep=dict(type='Boolean'))))
        manifest = dict(id=name, name='Preview', author='Fixture', description='Native preview test', license='MIT',
                        version='1.0.0', entryPoints=dict(settings='Preview.qml'),
                        metadata=dict(defaultSettings=dict(label=label, other='old', opaque=dict(keep=True)),
                                      settingsSchema=dict(version=1, fields=fields)))
        (directory/'manifest.json').write_text(json.dumps(manifest))
        (directory/'Preview.qml').write_bytes((args.source/'Scripts/dev/fixtures/plugin-preview-page.qml').read_bytes())
    (config/'settings/plugins/i4-preview-fail.json').symlink_to(failure/'settings.json')
    failure.chmod(0o555)
    probe = args.installed/'i5-retained-preview.qml'
    with probe.open('xb') as stream:
        stream.write((args.source/'Scripts/dev/fixtures/plugin-settings-preview.qml').read_bytes())
    try:
        for mode in ('save', 'cold'):
            env = dict(os.environ, I4_VERIFY='1' if mode == 'cold' else '0',
                       ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(root/'cache'),
                       ATMOSPHERA_STATE_DIR=str(root/'state'), QML_DISABLE_DISK_CACHE='1')
            result = subprocess.run(['timeout', '50', 'qs', '-p', str(probe), '--no-color'],
                                    env=env, capture_output=True, text=True, timeout=55)
            text = result.stdout+result.stderr
            (args.output/(mode+'.log')).write_text(text)
            print(mode+': exit='+str(result.returncode), flush=True)
            marker = 'I4_PREVIEW: '+('RESTART_PASS' if mode == 'cold' else 'SAVED_PASS')
            assert result.returncode == 0 and marker in text, text[-6500:]
            assert not any(error in text for error in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text[-6500:]
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS',
            fixture='plugin-settings-preview.qml', legs=['save', 'cold']), indent=2)+'\n')
        print('SETTINGS_RETAINED_PREVIEW: PASS')
    finally:
        failure.chmod(0o755)
        probe.unlink()


if __name__ == '__main__':
    main()
