#!/usr/bin/env python3
"""Schema contract negatives; execute inside the assigned project VM."""
import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('schema', Path(__file__).with_name('build-settings-schema.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--qml',action='store_true',help='also observe the installed module through actual qs')
    args = parser.parse_args()
    defaults, tree, paths = module.schema(ROOT)
    assert len([p for p in paths if paths[p]['type']=='List']) == 36
    assert len(defaults)-1 == 29
    assert paths[('bar','fontScale')]['type']=='Real'
    assert paths[('dock','deadOpacity')]['type']=='Real'
    assert paths[('wallpaper','wallhavenApiKey')]['sensitive']
    assert paths[('bar','screenOverrides')]['machineLocal']
    assert all(not node.get('idField') for node in paths.values())
    assert paths[('bar','widgets','left')]['element']['fields']['instanceSettings']['optional']
    assert paths[('bar','widgets','left')]['element']['open']
    assert paths[('bar','widgets','left')]['element']['fields']['instanceSettings']['open']
    assert 'stringPattern' in paths[('wallpaper','fillColor')]
    expected_resources = module.outputs(ROOT)
    checked = 0
    with tempfile.TemporaryDirectory(prefix='schema-contract-') as name:
        root = Path(name)
        for relative in ('Configs/defaults.json', 'Configs/settings-schema-overlay.json',
                         'Modules/OSD/OSD.qml'):
            dest = root/relative
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/relative,dest)
        def negative(label, mutate):
            nonlocal checked
            for relative in ('Configs/defaults.json','Configs/settings-schema-overlay.json'):
                shutil.copyfile(ROOT/relative,root/relative)
            mutate(root)
            try:
                generated = module.outputs(root)
                # The production --check gate compares all generated resources.
                # After adapter retirement, a valid-but-unregenerated type or
                # validation edit must fail freshness, not a duplicate schema.
                if generated != expected_resources:
                    raise ValueError('stale generated resources')
            except ValueError:
                checked += 1
            else:
                raise AssertionError('negative control admitted: '+label)
        def overlay_edit(root, edit):
            path = root/'Configs/settings-schema-overlay.json'
            data = json.loads(path.read_text())
            edit(data)
            path.write_text(json.dumps(data))
        negative('unknown overlay path', lambda r: overlay_edit(r,lambda d:d['entries'].append(
            {'path':['bar','typo'],'type':'Boolean'})))
        negative('missing empty list descriptor', lambda r: overlay_edit(r,lambda d:d.update(
            entries=[e for e in d['entries'] if e['path']!=['bar','screenOverrides']])))
        negative('integral real misinferred', lambda r: overlay_edit(r,lambda d:d.update(
            entries=[e for e in d['entries'] if e['path']!=['bar','fontScale']])))
        negative('unreviewed identity', lambda r: overlay_edit(r,lambda d:d['entries'].append(
            {'path':['calendar','cards'],'ref':'cards','idField':'id'})))
        negative('cyclic reference', lambda r: overlay_edit(r,lambda d:d['definitions'].update(strings={'ref':'strings'})))
        negative('open on scalar', lambda r: overlay_edit(r,lambda d:d['definitions']['color'].update(open=True)))
        negative('non-Boolean open', lambda r: overlay_edit(r,lambda d:d['definitions']['widget'].update(open='yes')))
        negative('bad element default', lambda r: overlay_edit(r,lambda d:d['definitions'].update(strings={'type':'List','element':{'type':'Boolean'}})))
        negative('unvalidated color', lambda r: overlay_edit(r,lambda d:d.update(
            entries=[e for e in d['entries'] if e['path']!=['wallpaper','fillColor']])))
        def changed_default(root):
            path = root/'Configs/defaults.json'
            data = json.loads(path.read_text()); data['bar']['widgetSpacing'] += 1
            path.write_text(json.dumps(data))
        # Defaults are now authored once. A valid edit must change generated
        # resources, not fail against a retired runtime adapter's duplicate.
        for relative in ('Configs/defaults.json','Configs/settings-schema-overlay.json'):
            shutil.copyfile(ROOT/relative,root/relative)
        before = module.outputs(root)
        changed_default(root)
        after = module.outputs(root)
        assert before != after, 'default edit failed to invalidate generated resources'
        assert before['Commons/SettingsSchema.qml'] != after['Commons/SettingsSchema.qml']
        assert before['Helpers/SettingsDefaults.js'] != after['Helpers/SettingsDefaults.js']
        checked += 1
    for name,text in module.outputs(ROOT).items():
        assert (ROOT/name).read_bytes()==text.encode(), 'stale: '+name
    print(f'SETTINGS_SCHEMA_SELFTEST: PASS ({checked} rejecting controls; 36 lists, 29 shards)')
    if args.qml:
        probe = ROOT/'settings-schema-selftest.qml'
        fixture = (ROOT/'Scripts/dev/fixtures/settings-schema.qml').read_text()
        with probe.open('x') as stream:
            stream.write(fixture.replace('"../../../Helpers/SettingsDefaults.js"','"Helpers/SettingsDefaults.js"'))
        try:
            result = subprocess.run(['timeout','20','qs','-p',str(probe),'--no-color'],
                                    capture_output=True,text=True,timeout=25)
            print(result.stdout+result.stderr)
            assert result.returncode==0 and 'SETTINGS_SCHEMA_QML: PASS' in result.stdout+result.stderr
        finally:
            probe.unlink()


if __name__ == '__main__':
    main()
