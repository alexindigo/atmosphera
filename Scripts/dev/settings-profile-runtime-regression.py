#!/usr/bin/env python3
"""Actual shell-profiles Main callbacks and native save/reload/cold consumers."""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'plugins', 'installed', 'work-root', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((args.plugins/'shell-profiles/manifest.json').read_text())
    assert tuple(map(int, manifest['version'].split('.'))) >= (1, 0, 8)
    assert manifest['minAtmospheraVersion'] == '0.10.0'
    registry = json.loads((args.plugins/'registry.json').read_text())
    entry = next(item for item in registry['plugins'] if item['id'] == 'shell-profiles')
    assert entry['version'] == manifest['version'] and entry['minAtmospheraVersion'] == manifest['minAtmospheraVersion']
    args.work_root.mkdir(parents=True, exist_ok=False)
    args.output.mkdir(parents=True, exist_ok=False)
    probe = args.installed/'i5-profile-runtime.qml'
    with probe.open('xb') as stream:
        stream.write((args.source/'Scripts/dev/fixtures/settings-profile-runtime.qml').read_bytes().replace(
            b'../../../Helpers/OwnedProcess.js', b'./Helpers/OwnedProcess.js'))
    roles = ['mPrimary', 'mOnPrimary', 'mSecondary', 'mOnSecondary', 'mTertiary', 'mOnTertiary',
             'mStandout', 'mOnStandout', 'mError', 'mOnError', 'mSurface', 'mOnSurface',
             'mSurfaceVariant', 'mOnSurfaceVariant', 'mOutline', 'mShadow', 'mHover', 'mOnHover']
    cases = []
    try:
        for name in ('settings', 'wallpapers', 'backup-failure', 'copy-failure', 'receipt-failure', 'wallpaper-failure', 'save-failure', 'concurrent-failure'):
            root = args.work_root/name
            config = root/'c'
            (config/'settings/plugins').mkdir(parents=True)
            shutil.copytree(args.plugins/'shell-profiles', config/'plugins/shell-profiles')
            (config/'settings.json').write_text('{"settingsVersion":62}')
            (config/'settings/bar.json').write_text('{"position":"bottom","opaque":18446744073709551615}')
            (config/'settings/plugins/shell-profiles.json').write_text('{"lastAppliedProfile":"previous","backupEnabled":true}')
            (config/'colors.json').write_text(json.dumps({key: '#123456' for key in roles}))
            registry_bytes = b'{"version":5,"states":{"shell-profiles":{"enabled":false,"sourceUrl":null}},"sources":[],"opaque":18446744073709551615}'
            (config/'plugins.json').write_bytes(registry_bytes)
            image = root/'wallpaper.png'
            image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3ioAAAAASUVORK5CYII='))
            negative = name.endswith('failure')
            for mode in ((name,) if negative else (name, 'cold')):
                env = dict(os.environ, I5_PROFILE_MODE=mode, I5_PROFILE_IMAGE=str(image),
                           ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(root/'cache'),
                           ATMOSPHERA_STATE_DIR=str(root/'state'), QML_DISABLE_DISK_CACHE='1')
                result = subprocess.run(['timeout', '50', 'qs', '-p', str(probe), '--no-color'],
                                        env=env, capture_output=True, text=True, timeout=55)
                text = result.stdout+result.stderr
                label = name+'-'+mode
                (args.output/(label+'.log')).write_text(text)
                print(label+': exit='+str(result.returncode), flush=True)
                assert result.returncode == 0 and 'I5_PROFILE_RUNTIME: PASS '+mode in text, text[-6000:]
                assert not any(key in text for key in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text[-6000:]
                expected = 'top' if negative and name not in ('receipt-failure', 'save-failure', 'concurrent-failure') else 'bottom'
                assert json.loads((config/'settings/bar.json').read_bytes()) == dict(position=expected, opaque=18446744073709551615)
                assert json.loads((config/'settings/plugins/shell-profiles.json').read_bytes())['lastAppliedProfile'] == ('previous' if negative else 'saved')
                assert (config/'settings.json').read_bytes() == b'{"settingsVersion":62}'
                if not negative:
                    assert (config/'plugins.json').read_bytes() == registry_bytes
                cases.append(dict(id=label, status='PASS'))
            if negative:
                if name == 'save-failure':
                    assert not (config/'profiles/saved').exists()
                continue
            profile = config/'profiles/saved'
            snapshot = json.loads((profile/'_config-files.json').read_bytes())
            assert 'settings/bar.json' in snapshot['entries'] and 'settings/plugins/shell-profiles.json' in snapshot['entries']
            backups = list((config/'profiles/_backups').glob('*/_config-files.json'))
            assert len(backups) == 1
            assert json.loads((backups[0].parent/'settings/bar.json').read_bytes())['position'] == 'top'
            assert json.loads((backups[0].parent/'plugins.json').read_bytes())['states']['shell-profiles']['enabled'] is True
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS', cases=cases), indent=2)+'\n')
        print('SETTINGS_PROFILE_RUNTIME: PASS')
    finally:
        probe.unlink()
        for name in ('backup-failure/c/profiles/_backups', 'receipt-failure/c/settings/plugins', 'save-failure/c/settings'):
            path = args.work_root/name
            if path.exists():
                path.chmod(0o755)


if __name__ == '__main__':
    main()
