#!/usr/bin/env python3
"""Native draft preview and inherited instance consumers. Assigned guest only."""
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
    for name in ('plugin/code', 'plugin/user', 'c/settings', 'cache', 'state'):
        (root/name).mkdir(parents=True)
    (root/'plugin/code/manifest.json').write_text(json.dumps(dict(id='i5-owner', version='1.0.0', metadata=dict(
        defaultSettings=dict(label='default', amount=3),
        settingsSchema=dict(version=1, fields=dict(label=dict(type='String'), amount=dict(type='Integer')))))))
    original = b'{"label":"legacy","amount":7,"wide":18446744073709551615}'
    (root/'plugin/code/settings.json').write_bytes(original)
    (root/'c/settings.json').write_text('{"settingsVersion":62}')
    (root/'c/plugins.json').write_text('{"version":5,"states":{},"sources":[]}')
    (root/'c/settings/bar.json').write_text('{"widgets":{"left":[{"id":"plugin:i5-owner"}]}}')
    probe = args.installed/'i5-preview-native.qml'
    with probe.open('xb') as stream:
        stream.write((args.source/'Scripts/dev/fixtures/settings-instance-live.qml').read_bytes())
    try:
        env = dict(os.environ, I5_PLUGIN_DIR=str(root/'plugin'), I5_INSTANCE_PREVIEW='1',
                   I5_INSTANCE_RESTART='0', ATMOSPHERA_CONFIG_DIR=str(root/'c'),
                   ATMOSPHERA_CACHE_DIR=str(root/'cache'), ATMOSPHERA_STATE_DIR=str(root/'state'),
                   QML_DISABLE_DISK_CACHE='1')
        result = subprocess.run(['timeout', '40', 'qs', '-p', str(probe), '--no-color'],
                                env=env, capture_output=True, text=True, timeout=45)
        text = result.stdout+result.stderr
        (args.output/'preview.log').write_text(text)
        print('preview: exit='+str(result.returncode), flush=True)
        assert result.returncode == 0 and 'I5_INSTANCE_PREVIEW: PASS' in text, text[-5000:]
        assert not any(marker in text for marker in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text[-5000:]
        assert (root/'plugin/code/settings.json').read_bytes() == original
        assert not (root/'plugin/user/settings.json').exists()
        assert 'instanceSettings' not in json.loads((root/'c/settings/bar.json').read_bytes())['widgets']['left'][0]
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS',
            cases=['shared-preview', 'instance-inheritance', 'unpreviewed-current-underlying', 'close-to-current-base']), indent=2)+'\n')
        print('SETTINGS_PLUGIN_PREVIEW: PASS')
    finally:
        probe.unlink()


if __name__ == '__main__':
    main()
