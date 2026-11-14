#!/usr/bin/env python3
"""Historical migration parity and ConfigStore source/file/restart outcomes.

Execute only inside the assigned project VM. All payloads and temporary files
stay below --work-root; the surrounding gate owns restoration and collection.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


VERSIONS = [27, 28, 32, 33, 35, 36, 37, 38, 40, 42, 43, 44, 45, 46,
            47, 48, 49, 50, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62]
EFFECTS = {36: 'clear-emoji-usage', 44: 'create-legacy-pam',
           46: 'remove-legacy-pam', 47: 'clear-network-stats',
           49: 'clear-launcher-usage', 56: 'migrate-color-schemes'}


def effect_rows(version):
    return [dict(effectId='settings-migration-'+str(v), version=v,
                 action=action, arguments={}) for v, action in EFFECTS.items() if version < v]


def original(version):
    return dict(settingsVersion=version,
                ui=dict(settingsPanelAttachToBar=False),
                bar=dict(floating=True, transparent=True, marginVertical=.5, marginHorizontal=2,
                         widgets=dict(left=[dict(id='TaskbarGrouped', labelMode='',
                                                 showLabelsOnlyWhenOccupied=False,
                                                 opaque=dict(keep=True)), dict(id='WiFi', opaque=dict(keep=True))],
                                      center=[], right=[])),
                systemMonitor=dict(enableNvidiaGpu=True),
                wallpaper=dict(randomEnabled=False, recursiveSearch=True, transitionType='random'),
                templates=dict(gtk=True, qt=False, niri=True, future=True),
                notifications=dict(batteryWarningThreshold=27, batteryCriticalThreshold=9),
                general=dict(keybinds=dict(keyUp='F9', keyDown='F8', keyLeft='', keyRight='F7',
                                          keyEnter=['Return', 'F6'], keyEscape='Escape', keyRemove=['Del'])),
                sessionMenu=dict(powerOptions=[dict(action='lock', enabled=True, opaque=dict(keep=True)),
                                               dict(action='shutdown', enabled=False)]),
                controlCenter=dict(openAtMouseOnBarRightClick=False,
                                   shortcuts=dict(left=[dict(widgetId='WiFi', opaque=dict(keep=True))], right=[])),
                audio=dict(cavaFrameRate=47), dock=dict(dockType='static'),
                opaque=dict(keep=[False, 0, None, '']))


def parity_cases():
    cases = [dict(id='version-'+str(v), raw=original(v)) for v in range(0, 64)]
    for name, patch in [
        ('attach-true', dict(ui=dict(settingsPanelAttachToBar=True))),
        ('missing-v33-v45', {}),
        ('transparent-false', dict(bar=dict(transparent=False))),
        ('numeric-boundaries', dict(bar=dict(marginVertical=1, marginHorizontal=-.5))),
        ('nonnumeric-margin', dict(bar=dict(marginVertical='0.5', marginHorizontal=None))),
        ('atom-shaped-dictionary', dict(bar=dict(marginVertical=dict(decimal='0.5')))),
        ('wifi-string-and-alias', dict(bar=dict(widgets=dict(left=['WiFi', dict(widgetId='WiFi', opaque=False)], center=[], right=[])))),
        ('new-keys-win', dict(wallpaper=dict(randomEnabled=False, automationEnabled=True,
                                           recursiveSearch=True, viewMode='single'),
                             templates=dict(gtk=True, activeTemplates=[]))),
        ('keyenter-raw-string', dict(general=dict(keybinds=dict(keyEnter='Return', keyRemove=[])))),
        ('keyenter-existing', dict(general=dict(keybinds=dict(keyEnter=['Return', 'Enter'], keyRemove=['F9'])))),
        ('power-custom', dict(sessionMenu=dict(powerOptions=[dict(action='lock', keybind='F9'), dict(action='shutdown')]))),
        ('transition-none', dict(wallpaper=dict(transitionType='none'))),
        ('transition-specific', dict(wallpaper=dict(transitionType='wipe'))),
        ('valid-input-method', dict(inputMethod=dict(switches=[], nextKeys=['F9'], launchFcitx5=False, legacyI18nChecked=True), bindings=dict(environment='macos'))),
        ('invalid-input-method', dict(inputMethod=dict(switches=False, nextKeys=None, launchFcitx5=0, legacyI18nChecked='no'), bindings=dict(environment=False))),
        ('v55-present-bar', dict(controlCenter=dict(openAtMouseOnBarRightClick=False), bar=dict(rightClickFollowMouse=True))),
    ]:
        raw = dict(settingsVersion=0, **patch)
        cases.append(dict(id=name, raw=raw))
    # The control must select a post-v45 version so only the raw-only v55 field
    # differs. The historical adapter remains true; raw compatibility becomes false.
    cases[-1]['raw']['settingsVersion'] = 54
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--installed', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--work-root', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    args.work_root.mkdir(parents=True, exist_ok=False)
    defaults = json.loads((args.source/'Configs/defaults.json').read_text())
    resource = args.installed/'Commons/Migrations/SettingsMigrationSource.js'
    original_resource = resource.read_bytes()
    assert original_resource == (args.source/'Commons/Migrations/SettingsMigrationSource.js').read_bytes()
    probe = args.installed/'i5-migrations.qml'
    fixture = (args.source/'Scripts/dev/fixtures/settings-migration-projection.qml').read_bytes()
    assert fixture.count(b'../../../Commons/Migrations/SettingsMigrationSource.js') == 1
    with probe.open('xb') as stream:
        stream.write(fixture.replace(b'../../../Commons/Migrations/SettingsMigrationSource.js',
                                    b'./Commons/Migrations/SettingsMigrationSource.js'))
    rows = []

    def run(name, spec, negative=None):
        env = dict(os.environ, I5_MIGRATION_SPEC=json.dumps(spec), QML_DISABLE_DISK_CACHE='1')
        result = subprocess.run(['timeout', '30', 'qs', '-p', str(probe), '--no-color'],
                                env=env, capture_output=True, text=True, timeout=35)
        text = result.stdout+result.stderr
        (args.output/(name+'.log')).write_text(text)
        print(text, end='', flush=True)
        if negative:
            assert result.returncode == 2 and negative in text, (name, result.returncode, text[-6000:])
            assert 'I5_MIGRATIONS: PARITY_PASS' not in text
        else:
            marker = 'PARITY_PASS' if spec.get('parity') else 'RESTART_PASS' if spec.get('restart') else 'SAVED_PASS'
            assert result.returncode == 0 and 'I5_MIGRATIONS: '+marker in text, (name, result.returncode, text[-6000:])
            assert not any(token in text for token in ['TypeError:', 'ReferenceError:', 'SyntaxError:', 'I5_MIGRATION_ASSERT:'])
        rows.append(dict(id=name, status='PASS', negative=bool(negative)))

    def identity(path):
        st = path.stat()
        return dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), inode=st.st_ino,
                    mtimeNs=st.st_mtime_ns, mode=st.st_mode)

    try:
        parity = dict(parity=True, directory=str(args.work_root), defaults=defaults, cases=parity_cases())
        run('historical-parity', parity)
        for name, old, new, failure in [
            ('negative-margin', b'Math.round(number * 18)', b'Math.round(number * 17)', 'historical effective parity'),
            ('negative-raw-only', b'put(compatibilityRaw, ["bar", "rightClickFollowMouse"]', b'put(values, ["bar", "rightClickFollowMouse"]', 'historical effective parity'),
            ('negative-effect-order', b'effect(44, "create-legacy-pam")', b'effect(46, "create-legacy-pam")', 'six ordered effects'),
        ]:
            assert original_resource.count(old) == 1
            resource.write_bytes(original_resource.replace(old, new))
            try:
                run(name, parity, failure)
            finally:
                resource.write_bytes(original_resource)

        for name, version, legacy, expected, user in [
            ('legacy-all', 0, original(0), {'ui.settingsPanelMode':'centered', 'bar.marginVertical':9,
                'bar.barType':'floating', 'wallpaper.automationEnabled':False, 'wallpaper.viewMode':'recursive',
                'systemMonitor.batteryWarningThreshold':27, 'systemMonitor.batteryCriticalThreshold':9,
                'general.keybinds.keyUp':['F9'], 'general.keybinds.keyEnter':['Return','Enter','F6'],
                'general.keybinds.keyRemove':['Shift+Del'], 'audio.spectrumFrameRate':47,
                'dock.dockType':'attached', 'bindings.environment':'none', 'inputMethod.launchFcitx5':True,
                'bar.widgets.left':[dict(id='Workspace', showApplications=True, labelMode='index',
                    hideUnoccupied=False, showLabelsOnlyWhenOccupied=False, colorizeIcons=False),
                    dict(id='Network', opaque=dict(keep=True))],
                'templates.activeTemplates':[dict(id='gtk', enabled=True),dict(id='niri', enabled=True)],
                'sessionMenu.powerOptions':[dict(action='lock',enabled=True,keybind='1',opaque=dict(keep=True)),
                                           dict(action='shutdown',enabled=False,keybind='6')]}, {}),
            ('raw-only-55', 54, dict(settingsVersion=54, bar=dict(rightClickFollowMouse=True),
                controlCenter=dict(openAtMouseOnBarRightClick=False)), {'bar.rightClickFollowMouse':True}, {}),
            ('sections-shadow', 59, dict(settingsVersion=59, bindings=dict(environment=False),
                inputMethod=dict(launchFcitx5='invalid')), {'bindings.environment':'macos',
                'inputMethod.launchFcitx5':False, 'general.keybinds.keyRemove':['Del']},
                {'bindings':dict(environment='macos'), 'inputMethod':dict(launchFcitx5=False),
                 'general':dict(keybinds=dict(keyRemove=['Del']), foreignUnknown=dict(keep=True))}),
            ('fresh', 62, None, {'bar.barType':defaults['bar']['barType'], 'bindings.environment':'none'}, {}),
            ('current-legacy', 62, dict(settingsVersion=62, bar=dict(barType='framed'),
                general=dict(keybinds=dict(keyRemove=['Del']))), {'bar.barType':'framed', 'general.keybinds.keyRemove':['Del']}, {}),
        ]:
            directory = args.work_root/name
            (directory/'settings').mkdir(parents=True)
            legacy_path = directory/'settings.json'
            if legacy is not None:
                # Unknown wide/prototype members exercise actual frozen worker
                # atoms and preserving file codec, not only synthetic test atoms.
                payload = json.dumps(legacy)[:-1]+',"wide":18446744073709551615,"__proto__":{"constructor":false}}\n'
                legacy_path.write_text(payload)
                before = identity(legacy_path)
            else:
                before = None
            for section, value in user.items():
                (directory/'settings'/(section+'.json')).write_text(json.dumps(value)+'\n')
            spec = dict(directory=str(directory), expected=expected,
                        effects=effect_rows(version) if legacy is not None else [])
            for restart in [False, True]:
                spec['restart'] = restart
                run(name+('-restart' if restart else '-save'), spec)
                assert (identity(legacy_path) if before else None) == before, 'legacy identity changed'
                assert bool(legacy_path.exists()) == bool(before)
                expected_files = dict(user)
                expected_files['general'] = dict(user.get('general', {}), scaleRatio=1.41)
                actual = {p.stem:json.loads(p.read_text()) for p in (directory/'settings').glob('*.json')}
                assert actual == expected_files, (name, actual, expected_files)
            print('I5_MIGRATION_FILES: '+json.dumps(dict(case=name, legacyIdentity=before,
                sparseFiles=actual)), flush=True)
        assert resource.read_bytes() == original_resource
        (args.output/'result.json').write_text(json.dumps(dict(status='PASS', cases=rows,
            historicalCases=len(parity['cases']), versions=VERSIONS), indent=2)+'\n')
        print('SETTINGS_MIGRATIONS: PASS (historical parity, 3 rejecting controls, 5 worker save/restart pairs)')
    finally:
        resource.write_bytes(original_resource)
        probe.unlink()


if __name__ == '__main__':
    main()
